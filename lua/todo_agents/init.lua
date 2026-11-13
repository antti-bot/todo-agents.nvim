local M = {}
local task = require('todo_agents.task')
local worktree = require('todo_agents.worktree')
local config = { provider = 'codex', commands = { codex = { 'codex' }, claude = { 'claude' } },
  mappings = true, context = true, worktrees = true }
local live = {}
local uv = vim.uv or vim.loop

local function dir()
  local path = vim.fn.stdpath('state') .. '/todo-agents'
  vim.fn.mkdir(path, 'p', 448)
  return path
end
local function uuid()
  local hex = vim.fn.sha256(tostring(uv.hrtime()) .. tostring({}) .. tostring(vim.fn.getpid()))
  return hex:sub(1, 8) .. '-' .. hex:sub(9, 12) .. '-4' .. hex:sub(14, 16)
    .. '-a' .. hex:sub(18, 20) .. '-' .. hex:sub(21, 32)
end
local function save(record)
  local path = dir() .. '/' .. record.id .. '.json'
  if vim.fn.writefile({ vim.json.encode(record) }, path) ~= 0 then error('Cannot save session metadata') end
  uv.fs_chmod(path, 384)
end
local function load(id)
  local path = dir() .. '/' .. id .. '.json'
  if vim.fn.filereadable(path) == 0 then error('Session metadata missing on this machine: ' .. id) end
  return vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
end
local function cleanup(record)
  local ok, removed, message = pcall(worktree.cleanup, record)
  if not ok then
    vim.notify('todo-agents: worktree cleanup failed: ' .. tostring(removed), vim.log.levels.WARN)
  elseif not removed then
    vim.notify('todo-agents: ' .. message, vim.log.levels.WARN)
  end
end
local function current()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local parsed = task.parse(vim.api.nvim_get_current_line())
  if not parsed then error('Put the cursor on a Markdown checkbox task') end
  return parsed, row
end
-- Bind only a transcript containing this task's unique launch marker. Never use --last.
local function discover_codex(record, attempt)
  if record.session_id then return end
  local persisted = load(record.id)
  if persisted.session_id then record.session_id = persisted.session_id; return end
  local home = vim.env.CODEX_HOME or (vim.fn.expand('~') .. '/.codex')
  for _, path in ipairs(vim.fn.glob(home .. '/sessions/**/*.jsonl', false, true)) do
    local stat = uv.fs_stat(path)
    if stat and stat.mtime.sec >= record.started - 2 then
      local file = io.open(path, 'r')
      if file then
        local content = file:read(262144) or ''
        file:close()
        if content:find('todo-agent-task:' .. record.id, 1, true) then
          local ok, meta = pcall(vim.json.decode, content:match('[^\n]+') or '')
          if ok and meta.type == 'session_meta' and meta.payload and meta.payload.id then
            record.session_id = meta.payload.id
            save(record)
            return
          end
        end
      end
    end
  end
  if attempt < 30 then vim.defer_fn(function() discover_codex(record, attempt + 1) end, 2000) end
end
local function launch(record, resume)
  local existing = live[record.id]
  if existing and vim.api.nvim_buf_is_valid(existing.buf) then
    local windows = vim.fn.win_findbuf(existing.buf)
    if #windows > 0 then vim.api.nvim_set_current_win(windows[1])
    else vim.cmd('botright vsplit'); vim.api.nvim_win_set_buf(0, existing.buf) end
    vim.cmd('startinsert')
    return
  end
  local argv = vim.deepcopy(config.commands[record.provider])
  if not argv or not argv[1] then error('Unknown provider: ' .. tostring(record.provider)) end
  if vim.fn.executable(argv[1]) ~= 1 then error('Executable not found: ' .. argv[1]) end
  if resume then
    if record.provider == 'claude' then
      vim.list_extend(argv, { '--resume', record.session_id })
    elseif record.session_id then
      vim.list_extend(argv, { 'resume', record.session_id })
    else
      error('Codex session is not bound. Use :TodoAgentBind <ID> from Codex /status before reopening')
    end
  else
    if record.provider == 'claude' then
      record.session_id = record.id
      vim.list_extend(argv, { '--session-id', record.id })
    end
    table.insert(argv, record.prompt)
  end
  worktree.prepare(record, dir())
  save(record)
  vim.cmd('botright vsplit')
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)
  local ok, job = pcall(vim.fn.termopen, argv, { cwd = record.cwd, on_exit = function(_, code)
    -- Clear and clean together so reopening cannot race a queued cleanup.
    vim.schedule(function()
      live[record.id] = nil
      cleanup(record)
      if code ~= 0 then
        vim.notify('todo-agents: ' .. record.provider .. ' exited with code ' .. code, vim.log.levels.WARN)
      end
    end)
  end })
  if not ok or job <= 0 then
    cleanup(record)
    vim.api.nvim_buf_delete(buf, { force = true })
    error('Failed to start ' .. record.provider)
  end
  live[record.id] = { buf = buf, job = job, record = record }
  vim.bo[buf].bufhidden = 'hide'
  vim.b[buf].todo_agent_id = record.id
  save(record)
  if record.provider == 'codex' and not resume then
    vim.defer_fn(function() discover_codex(record, 1) end, 1000)
  end
  vim.cmd('startinsert')
end

function M.start(provider)
  local parsed, row = current()
  if parsed.id then return M.open() end
  if parsed.check:lower() == 'x' then error('Task is already checked; uncheck it before launching') end
  provider = provider or config.provider
  if not config.commands[provider] then error('Unknown provider: ' .. tostring(provider)) end
  if vim.fn.executable(config.commands[provider][1]) ~= 1 then
    error('Executable not found: ' .. config.commands[provider][1])
  end
  local buf = vim.api.nvim_get_current_buf()
  if not vim.bo[buf].modifiable then error('TODO buffer is not modifiable') end
  local path = vim.api.nvim_buf_get_name(buf)
  local base = path ~= '' and vim.fs.dirname(path) or vim.fn.getcwd()
  local root = base
  if vim.fn.executable('git') == 1 then
    local result = vim.system({ 'git', '-C', base, 'rev-parse', '--show-toplevel' }, { text = true }):wait(10000)
    if result.code == 0 then root = vim.trim(result.stdout) end
  end
  local id = uuid()
  local snapshot = dir() .. '/' .. id .. '.md'
  local prompt
  if config.context then
    if vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), snapshot) ~= 0 then
      error('Cannot write context snapshot')
    end
    uv.fs_chmod(snapshot, 384)
    prompt = task.prompt(parsed, path ~= '' and path or '[unnamed buffer]', row, snapshot)
  else
    prompt = 'Work on this TODO item:\n' .. parsed.text
  end
  prompt = prompt .. '\n\nLaunch marker: todo-agent-task:' .. id
  local record = { id = id, provider = provider, cwd = root, prompt = prompt, source = path, started = os.time(), isolated = config.worktrees }
  if config.worktrees then
    record.prompt = record.prompt .. '\nWork only in the task Git worktree provided as your working directory.'
  end
  -- Only change the TODO after the process has successfully started.
  launch(record, false)
  vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { task.link(parsed, provider, id) })
end

function M.open()
  local parsed = current()
  if not parsed.id then return M.start() end
  local record = load(parsed.id)
  if record.provider ~= parsed.provider then error('Link provider does not match session metadata') end
  launch(record, true)
end

function M.cleanup()
  local parsed = current()
  if not parsed.id then error('No agent linked to this task') end
  if live[parsed.id] then error('Stop the task agent before cleaning its worktree') end
  cleanup(load(parsed.id))
end

-- Stop processes before removing their directories during a normal Neovim exit.
vim.api.nvim_create_autocmd('VimLeavePre', {
  group = vim.api.nvim_create_augroup('TodoAgentsLifecycle', { clear = true }),
  callback = function()
    for _, session in pairs(live) do
      pcall(vim.fn.jobstop, session.job)
      local result = vim.fn.jobwait({ session.job }, 1000)[1]
      if result ~= -1 then cleanup(session.record) end
    end
  end,
})

function M.toggle()
  local parsed, row = current()
  local line = vim.api.nvim_get_current_line()
  local start = #parsed.prefix + 2
  local check = parsed.check == ' ' and 'x' or ' '
  vim.api.nvim_buf_set_lines(0, row - 1, row, false, { line:sub(1, start - 1) .. check .. line:sub(start + 1) })
end

function M.bind(id)
  if not id:match('^[%w_-]+$') then error('Invalid session ID') end
  local link_id = vim.b.todo_agent_id
  if not link_id then link_id = current().id end
  if not link_id then error('No agent linked to this task') end
  local record = load(link_id)
  record.session_id = id
  save(record)
  vim.notify('todo-agents: session bound to ' .. id)
end

function M.setup(opts)
  config = vim.tbl_deep_extend('force', config, opts or {})
  if config.mappings then
    vim.keymap.set('n', '<leader>aa', '<cmd>TodoAgent<cr>', { desc = 'Start/open TODO agent' })
    vim.keymap.set('n', '<leader>ac', '<cmd>TodoAgent claude<cr>', { desc = 'Start Claude TODO agent' })
    vim.keymap.set('n', '<leader>ax', '<cmd>TodoAgentToggle<cr>', { desc = 'Toggle TODO checkbox' })
    vim.keymap.set('n', 'gx', function()
      local parsed = task.parse(vim.api.nvim_get_current_line())
      if parsed and parsed.id then
        local ok, err = pcall(M.open)
        if not ok then vim.notify(tostring(err), vim.log.levels.ERROR) end
      else vim.ui.open(vim.fn.expand('<cfile>')) end
    end, { desc = 'Open TODO agent or URL' })
  end
end
return M
