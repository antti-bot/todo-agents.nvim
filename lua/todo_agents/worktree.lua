local M = {}
local uv = vim.uv or vim.loop
local command_timeout_ms = 30000

local function run_command(arguments)
  local result = vim.system(arguments, { text = true }):wait(command_timeout_ms)
  if result.code ~= 0 then
    local message = vim.trim(result.stderr ~= '' and result.stderr or result.stdout or 'Command failed')
    local decoded, response = pcall(vim.json.decode, message)
    if decoded and response.error and response.error.message then
      message = response.error.message
    end
    error(message, 0)
  end
  return vim.trim(result.stdout or '')
end

function M.herdr(arguments)
  local command = { vim.env.HERDR_BIN_PATH or 'herdr' }
  vim.list_extend(command, arguments)
  local output = run_command(command)
  if output ~= '' then
    return vim.json.decode(output).result
  end
end

local function git(path, arguments)
  local command = { 'git', '-C', path }
  return run_command(vim.list_extend(command, arguments))
end

local function absolute_path(path, base_directory)
  if path:sub(1, 2) == '~/' then
    path = vim.fn.expand('~') .. path:sub(2)
  end
  if path:sub(1, 1) ~= '/' then
    path = base_directory .. '/' .. path
  end
  return vim.fs.normalize(path)
end

local function folder_from_line(line, base_directory)
  local path, heading_count = vim.trim(line):gsub('^#+%s+', '')
  if path == '' then
    return
  end

  local explicit_path = path:match('^%.%./')
    or path:match('^%./')
    or path:match('^~/')
    or path:match('^/')
    or path:match('/$')
  local stat = uv.fs_stat(absolute_path(path, base_directory))
  if heading_count > 0 or explicit_path or (stat and stat.type == 'directory') then
    return path
  end
end

-- Validate the task location and resolve the repository for a new task.
-- Existing links supply their own destination and return no repository.
function M.resolve_task_repository(buffer, row, has_link)
  local filename = vim.api.nvim_buf_get_name(buffer)
  local base_directory = filename ~= '' and vim.fs.dirname(filename) or vim.fn.getcwd()
  local selected_path = base_directory
  local fence_character = nil
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, row, false)

  for line_number, line in ipairs(lines) do
    local fence_marker = line:match('^%s*(```+)') or line:match('^%s*(~~~+)')
    if fence_marker then
      local character = fence_marker:sub(1, 1)
      if not fence_character then
        fence_character = character
      elseif fence_character == character then
        fence_character = nil
      end
    elseif not fence_character and line_number < row and not line:match('^%s') then
      local folder = folder_from_line(line, base_directory)
      if folder then
        selected_path = absolute_path(folder, base_directory)
      end
    end
  end

  if fence_character then
    error('Task is inside a code block', 0)
  end
  -- Existing links retain their own worktree, regardless of the current heading.
  if has_link then
    return
  end
  return git(selected_path, { 'rev-parse', '--show-toplevel' })
end

function M.create(repository, label)
  local unique_id = vim.fn.sha256(tostring(uv.hrtime()) .. vim.fn.getpid()):sub(1, 12)
  return M.herdr({
    'worktree', 'create',
    '--cwd', repository,
    '--branch', 'todo-agent/' .. unique_id,
    '--base', 'main',
    '--label', label,
    '--no-focus',
  })
end

function M.open(path)
  -- Herdr requires the primary checkout as the source, even for an existing worktree.
  local worktrees = git(path, { 'worktree', 'list', '--porcelain', '-z' })
  local repository = worktrees:match('^worktree ([^%z]+)')
  return M.herdr({ 'worktree', 'open', '--cwd', repository, '--path', path, '--no-focus' })
end

return M
