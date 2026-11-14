local M = {}
local worktree = require('todo_agents.worktree')

local default_config = { command = { 'codex' }, mappings = true }
local config = vim.deepcopy(default_config)
local link_scheme = 'herdr://'

local function parse_task(line)
  local prefix, checkbox, text = line:match('^(%s*[-*+]%s+)%[([ xX])%]%s+(.+)$')
  if not prefix then
    prefix, checkbox, text = line:match('^(%s*%d+[.)]%s+)%[([ xX])%]%s+(.+)$')
  end
  return prefix, checkbox, text
end

local function find_worktree_link(line, cursor_column)
  local first, last, link = line:find('(herdr://[^%s)]+)')
  if not first then
    return
  end

  -- Include the Markdown label when checking whether the cursor is on a link.
  local label_start = line:sub(1, first - 1):match('.*()%[')
  local link_start = label_start or first
  -- Neovim cursor columns are zero-based; Lua string positions are one-based.
  if not cursor_column or (cursor_column + 1 >= link_start and cursor_column + 1 <= last) then
    return link
  end
end

local function open_with_error_reporting()
  local ok, result = pcall(M.open)
  if not ok then
    vim.api.nvim_echo({ { tostring(result), 'ErrorMsg' } }, true, { err = true })
  end
  return ok, result
end

local function focus_workspace_agent(result)
  local workspace_id = result.workspace.workspace_id
  local panes = worktree.herdr({ 'pane', 'list', '--workspace', workspace_id }).panes
  for _, pane in ipairs(panes) do
    if pane.agent and pane.agent ~= vim.NIL then
      return worktree.herdr({ 'agent', 'focus', pane.pane_id })
    end
  end
  worktree.herdr({ 'workspace', 'focus', workspace_id })
end

local function task_link(prefix, text, path)
  local encoded_path = vim.uri_encode(path):gsub('%(', '%%28'):gsub('%)', '%%29')
  local label = text:gsub('\\', '\\\\'):gsub('%[', '\\['):gsub('%]', '\\]')
  return prefix .. '[ ] [' .. label .. '](' .. link_scheme .. encoded_path .. ')'
end

local function start_task(buffer, row, line, prefix, text, repository)
  if not vim.bo[buffer].modifiable then
    error('TODO buffer is not modifiable', 0)
  end

  local result = worktree.create(repository, text)
  local linked_task = task_link(prefix, text, result.worktree.path)
  vim.api.nvim_buf_set_text(buffer, row - 1, 0, row - 1, #line, { linked_task })

  local escaped_arguments = vim.tbl_map(vim.fn.shellescape, config.command)
  local command = table.concat(escaped_arguments, ' ')
  worktree.herdr({ 'pane', 'run', result.root_pane.pane_id, command })
  worktree.herdr({ 'workspace', 'focus', result.workspace.workspace_id })
end

function M.open()
  local buffer = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_get_current_line()
  local prefix, checkbox, text = parse_task(line)
  local link = find_worktree_link(line)
  if not prefix and not link then
    return
  end

  -- Invalid repositories and fenced examples are intentionally ignored.
  local valid, repository = pcall(worktree.resolve_task_repository, buffer, row, link ~= nil)
  if not valid or (not link and checkbox:lower() == 'x') then
    return
  end
  if vim.env.HERDR_ENV ~= '1' then
    error('Open this TODO in Neovim inside Herdr', 0)
  end

  if link then
    local path = vim.uri_decode(link:sub(#link_scheme + 1))
    return focus_workspace_agent(worktree.open(path))
  end
  start_task(buffer, row, line, prefix, text, repository)
end

local function open_fallback_link(fallback)
  if type(fallback.callback) == 'function' then
    return fallback.callback()
  end
  if fallback.rhs and fallback.rhs ~= '' then
    local keys = vim.api.nvim_replace_termcodes(fallback.rhs, true, false, true)
    return vim.api.nvim_feedkeys(keys, 'm', false)
  end
  vim.ui.open(vim.fn.expand('<cfile>'))
end

local function attach_mapping(buffer)
  if vim.b[buffer].todo_agents or not config.mappings then
    return
  end
  vim.b[buffer].todo_agents = true
  local fallback = vim.fn.maparg('gx', 'n', false, true)
  vim.keymap.set('n', 'gx', function()
    local line = vim.api.nvim_get_current_line()
    local cursor_column = vim.api.nvim_win_get_cursor(0)[2]
    if parse_task(line) or find_worktree_link(line, cursor_column) then
      return open_with_error_reporting()
    end
    return open_fallback_link(fallback)
  end, { buffer = buffer, desc = 'Open task in Herdr' })
end

local function attach_supported_buffer(buffer)
  if vim.b[buffer].todo_agents or vim.bo[buffer].buftype ~= '' then
    return
  end
  local filetype = vim.bo[buffer].filetype
  if filetype == '' or filetype == 'text' or filetype == 'markdown' then
    attach_mapping(buffer)
  end
end

function M.setup(options)
  config = vim.tbl_deep_extend('force', vim.deepcopy(default_config), options or {})
  vim.api.nvim_create_autocmd({ 'BufEnter', 'FileType' }, {
    group = vim.api.nvim_create_augroup('TodoAgentsBuffers', { clear = true }),
    callback = function(event)
      attach_supported_buffer(event.buf)
    end,
  })
  attach_supported_buffer(vim.api.nvim_get_current_buf())
end

return M
