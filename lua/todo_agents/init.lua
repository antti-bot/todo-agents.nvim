local M = {}
local task = require('todo_agents.task')
local repos = require('todo_agents.repos')
local worktree = require('todo_agents.worktree')
local ui = require('todo_agents.ui')
local uv = vim.uv or vim.loop
local config = { command = { 'codex' }, mappings = true }
local live, origins = {}, {}

local function state()
  local path = vim.fn.stdpath('state') .. '/todo-agents'
  vim.fn.mkdir(path, 'p', 448)
  return path
end

local function save(record)
  local keys = { record.id }
  if record.session_id and record.session_id ~= record.id then keys[#keys + 1] = record.session_id end
  for _, key in ipairs(keys) do
    local path = state() .. '/' .. key .. '.json'
    if vim.fn.writefile({ vim.json.encode(record) }, path) ~= 0 then error('Cannot save session', 0) end
    uv.fs_chmod(path, 384)
  end
end

local function load(id)
  local path = state() .. '/' .. id .. '.json'
  if vim.fn.filereadable(path) == 0 then error('Session metadata missing: ' .. id, 0) end
  return vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
end

local function relink(record)
  local buf = origins[record.id]
  if not record.session_id or not buf or not vim.api.nvim_buf_is_loaded(buf) or not vim.bo[buf].modifiable then return end
  for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local parsed = task.parse(line)
    if parsed and parsed.pending and parsed.id == record.id then
      local first, last = line:find('%(codex://task/[%w_-]+%)')
      vim.api.nvim_buf_set_text(buf, row - 1, first - 1, row - 1, last, { '(codex://' .. record.session_id .. ')' })
    end
  end
end

local function bind(record, id)
  if not id:match('^[%w_-]+$') then error('Invalid session ID', 0) end
  if record.session_id and record.session_id ~= id then error('Task is already bound to a session', 0) end
  record.session_id = id
  save(record)
  relink(record)
end

local function discover(record, attempt)
  record = load(record.id)
  if record.session_id then return relink(record) end
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
          if ok and meta.type == 'session_meta' and meta.payload and type(meta.payload.id) == 'string' then
            return bind(record, meta.payload.id)
          end
        end
      end
    end
  end
  if attempt < 30 then vim.defer_fn(function() ui.call(discover, record, attempt + 1) end, 2000) end
end

local function launch(record, resume, split)
  local running = live[record.id]
  if running and vim.api.nvim_buf_is_valid(running.buf) then
    if split then vim.cmd('botright vsplit') end
    vim.api.nvim_win_set_buf(0, running.buf)
    vim.cmd('startinsert')
    return
  end
  local argv = vim.deepcopy(config.command)
  if not argv[1] or vim.fn.executable(argv[1]) ~= 1 then error('Codex executable not found', 0) end
  if resume and not record.session_id then error('Session not bound; use :TodoAgentBind with the ID from /status', 0) end
  worktree.prepare(record, state())
  if resume then vim.list_extend(argv, { 'resume', record.session_id })
  else
    record.prompt = record.prompt .. '\nTask worktree: ' .. record.cwd .. '\nEdit only this repository.'
    argv[#argv + 1] = record.prompt
  end
  save(record)
  if split then vim.cmd('botright vsplit') end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)
  local ok, job = pcall(vim.fn.termopen, argv, { cwd = record.cwd, on_exit = function()
    vim.schedule(function()
      live[record.id] = nil
      ui.call(worktree.cleanup, record)
    end)
  end })
  if not ok or job <= 0 then
    ui.call(worktree.cleanup, record)
    vim.api.nvim_win_set_buf(0, origins[record.id])
    vim.api.nvim_buf_delete(buf, { force = true })
    error('Cannot start Codex', 0)
  end
  live[record.id] = { buf = buf, job = job, record = record }
  vim.bo[buf].bufhidden = 'hide'
  vim.b[buf].todo_agent_id = record.id
  if not resume then vim.defer_fn(function() ui.call(discover, record, 1) end, 1000) end
  vim.cmd('startinsert')
end

function M.open(split)
  local buf, row = vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)[1]
  M.attach(buf)
  local line = vim.api.nvim_get_current_line()
  local parsed = task.parse(line)
  local id = parsed and parsed.id or task.id(line)
  if id then
    local record = load(id)
    origins[record.id] = buf
    relink(record)
    return launch(record, true, split)
  end
  if not parsed then error('Cursor is not on a task or Codex link', 0) end
  if parsed.check:lower() == 'x' then error('Task is checked', 0) end
  if not vim.bo[buf].modifiable then error('TODO buffer is not modifiable', 0) end
  if not config.command[1] or vim.fn.executable(config.command[1]) ~= 1 then error('Codex executable not found', 0) end
  local repo = repos.validate(repos.selected(buf, row))
  id = vim.fn.sha256(tostring(uv.hrtime()) .. tostring({}) .. vim.fn.getpid()):sub(1, 24)
  local snapshot = state() .. '/' .. id .. '.md'
  if vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), snapshot) ~= 0 then error('Cannot save TODO context', 0) end
  uv.fs_chmod(snapshot, 384)
  local record = { id = id, repo = repo, cwd = repo, started = os.time(),
    prompt = task.prompt(parsed, vim.api.nvim_buf_get_name(buf), row, snapshot) .. '\nLaunch marker: todo-agent-task:' .. id }
  origins[id] = buf
  launch(record, false, split)
  vim.api.nvim_buf_set_text(buf, row - 1, 0, row - 1, #line, { task.link(parsed, id, true) })
end

function M.bind(id)
  local parsed = task.parse(vim.api.nvim_get_current_line())
  local key = vim.b.todo_agent_id or (parsed and parsed.id)
  if not key then error('Task has no session', 0) end
  bind(load(key), id)
end

function M.cleanup()
  local parsed = task.parse(vim.api.nvim_get_current_line())
  if not parsed or not parsed.id then error('Task has no session', 0) end
  local record = load(parsed.id)
  if live[record.id] then error('Task is running', 0) end
  local clean, reason = worktree.cleanup(record)
  if not clean then error(reason, 0) end
end

function M.attach(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if vim.b[buf].todo_agents or not config.mappings then return end
  vim.b[buf].todo_agents = true
  local fallback = vim.fn.maparg('gx', 'n', false, true)
  vim.keymap.set('n', 'gx', function()
    local line = vim.api.nvim_get_current_line()
    if task.parse(line) or task.id(line, vim.api.nvim_win_get_cursor(0)[2]) then return ui.call(M.open) end
    if type(fallback.callback) == 'function' then return fallback.callback() end
    if fallback.rhs and fallback.rhs ~= '' then
      return vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(fallback.rhs, true, false, true), 'm', false)
    end
    vim.ui.open(vim.fn.expand('<cfile>'))
  end, { buffer = buf, desc = 'Open task or link' })
end

function M.plan(path)
  if not path or path == '' then path = repos.root(vim.fn.getcwd()) .. '/TODO.md' end
  vim.cmd.edit(vim.fn.fnameescape(path))
  vim.bo.filetype = 'markdown'
  M.attach()
end

function M.setup(opts)
  config = vim.tbl_deep_extend('force', { command = { 'codex' }, mappings = true }, opts or {})
  local function detect(buf)
    if vim.b[buf].todo_agents or vim.bo[buf].buftype ~= '' then return end
    local ft = vim.bo[buf].filetype
    if ft == '' or ft == 'text' or ft == 'markdown' then
      if task.contains(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) then M.attach(buf) end
    end
  end
  vim.api.nvim_create_autocmd({ 'BufReadPost', 'FileType', 'TextChanged', 'TextChangedI' }, {
    group = vim.api.nvim_create_augroup('TodoAgentsBuffers', { clear = true }), callback = function(args) detect(args.buf) end,
  })
  detect(vim.api.nvim_get_current_buf())
end

vim.api.nvim_create_autocmd('VimLeavePre', {
  group = vim.api.nvim_create_augroup('TodoAgentsLifecycle', { clear = true }), callback = function()
    local sessions = vim.tbl_values(live)
    for _, session in ipairs(sessions) do pcall(vim.fn.jobstop, session.job) end
    for _, session in ipairs(sessions) do
      if vim.fn.jobwait({ session.job }, 1000)[1] ~= -1 then ui.call(worktree.cleanup, session.record) end
    end
  end,
})

return M
