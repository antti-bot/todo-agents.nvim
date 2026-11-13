local M = {}
local worktree = require('todo_agents.worktree')
local config = { command = { 'codex' }, mappings = true }

local function parse(line)
  local prefix, check, text = line:match('^(%s*[-*+]%s+)%[([ xX])%]%s+(.+)$')
  if not prefix then prefix, check, text = line:match('^(%s*%d+[.)]%s+)%[([ xX])%]%s+(.+)$') end
  return prefix, check, text
end

local function uri(line, col)
  local first, last, link = line:find('(herdr://[^%s)]+)')
  if not first then return end
  local label = line:sub(1, first - 1):match('.*()%[')
  if not col or (col + 1 >= (label or first) and col + 1 <= last) then return link end
end

local function call(fn, ...)
  local ok, result = pcall(fn, ...)
  if not ok then vim.api.nvim_echo({ { tostring(result), 'ErrorMsg' } }, true, { err = true }) end
  return ok, result
end

local function focus(result)
  local panes = worktree.herdr({ 'pane', 'list', '--workspace', result.workspace.workspace_id }).panes
  for _, pane in ipairs(panes) do
    if pane.agent and pane.agent ~= vim.NIL then
      return worktree.herdr({ 'agent', 'focus', pane.pane_id })
    end
  end
  worktree.herdr({ 'workspace', 'focus', result.workspace.workspace_id })
end

function M.open()
  local buf, row = vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_get_current_line()
  local prefix, check, text = parse(line)
  local link = uri(line)
  if not prefix and not link then return end
  local valid, repo = pcall(worktree.selected, buf, row, link)
  if not valid or (not link and check:lower() == 'x') then return end
  if vim.env.HERDR_ENV ~= '1' then error('Open this TODO in Neovim inside Herdr', 0) end
  if link then
    return focus(worktree.open(vim.uri_decode(link:sub(9))))
  end
  if not vim.bo[buf].modifiable then error('TODO buffer is not modifiable', 0) end
  local result = worktree.create(repo, text)
  local target = 'herdr://' .. vim.uri_encode(result.worktree.path):gsub('%(', '%%28'):gsub('%)', '%%29')
  local label = text:gsub('\\', '\\\\'):gsub('%[', '\\['):gsub('%]', '\\]')
  vim.api.nvim_buf_set_text(buf, row - 1, 0, row - 1, #line, { prefix .. '[ ] [' .. label .. '](' .. target .. ')' })
  local argv = vim.tbl_map(vim.fn.shellescape, config.command)
  worktree.herdr({ 'pane', 'run', result.root_pane.pane_id, table.concat(argv, ' ') })
  worktree.herdr({ 'workspace', 'focus', result.workspace.workspace_id })
end

local function attach(buf)
  if vim.b[buf].todo_agents or not config.mappings then return end
  vim.b[buf].todo_agents = true
  local fallback = vim.fn.maparg('gx', 'n', false, true)
  vim.keymap.set('n', 'gx', function()
    local line = vim.api.nvim_get_current_line()
    if parse(line) or uri(line, vim.api.nvim_win_get_cursor(0)[2]) then return call(M.open) end
    if type(fallback.callback) == 'function' then return fallback.callback() end
    if fallback.rhs and fallback.rhs ~= '' then
      return vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(fallback.rhs, true, false, true), 'm', false)
    end
    vim.ui.open(vim.fn.expand('<cfile>'))
  end, { buffer = buf, desc = 'Open task in Herdr' })
end

function M.setup(opts)
  config = vim.tbl_deep_extend('force', { command = { 'codex' }, mappings = true }, opts or {})
  local function detect(buf)
    if vim.b[buf].todo_agents or vim.bo[buf].buftype ~= '' then return end
    local ft = vim.bo[buf].filetype
    if ft == '' or ft == 'text' or ft == 'markdown' then attach(buf) end
  end
  vim.api.nvim_create_autocmd({ 'BufEnter', 'FileType' }, {
    group = vim.api.nvim_create_augroup('TodoAgentsBuffers', { clear = true }), callback = function(args) detect(args.buf) end,
  })
  detect(vim.api.nvim_get_current_buf())
end

return M
