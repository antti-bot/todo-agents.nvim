local M = {}
local uv = vim.uv or vim.loop

local function run(argv)
  local result = vim.system(argv, { text = true }):wait(30000)
  if result.code ~= 0 then
    local message = vim.trim(result.stderr ~= '' and result.stderr or result.stdout or 'Command failed')
    local ok, response = pcall(vim.json.decode, message)
    error(ok and response.error and response.error.message or message, 0)
  end
  return vim.trim(result.stdout or '')
end

function M.herdr(args)
  local argv = { vim.env.HERDR_BIN_PATH or 'herdr' }
  vim.list_extend(argv, args)
  local output = run(argv)
  if output ~= '' then return vim.json.decode(output).result end
end

local function git(path, args)
  local argv = { 'git', '-C', path }
  return run(vim.list_extend(argv, args))
end

local function absolute(path, base)
  if path:sub(1, 2) == '~/' then path = vim.fn.expand('~') .. path:sub(2) end
  if path:sub(1, 1) ~= '/' then path = base .. '/' .. path end
  return vim.fs.normalize(path)
end

local function folder(line, base)
  local path, heading = vim.trim(line):gsub('^#+%s+', '')
  if path == '' then return end
  local explicit = path:match('^%.%./') or path:match('^%./') or path:match('^~/')
    or path:match('^/') or path:match('/$')
  local stat = uv.fs_stat(absolute(path, base))
  if heading > 0 or explicit or (stat and stat.type == 'directory') then return path end
end

function M.selected(buf, row, linked)
  local name = vim.api.nvim_buf_get_name(buf)
  local base = name ~= '' and vim.fs.dirname(name) or vim.fn.getcwd()
  local path, fence = base, nil
  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, row, false)) do
    local marker = line:match('^%s*(```+)') or line:match('^%s*(~~~+)')
    if marker then
      if not fence then fence = marker:sub(1, 1) elseif fence == marker:sub(1, 1) then fence = nil end
    elseif not fence and i < row and not line:match('^%s') then
      local heading = folder(line, base)
      if heading then path = absolute(heading, base) end
    end
  end
  if fence then error('Task is inside a code block', 0) end
  return linked and path or git(path, { 'rev-parse', '--show-toplevel' })
end

function M.create(repo, label)
  local id = vim.fn.sha256(tostring(uv.hrtime()) .. vim.fn.getpid()):sub(1, 12)
  return M.herdr({ 'worktree', 'create', '--cwd', repo, '--branch', 'todo-agent/' .. id,
    '--base', 'main', '--label', label, '--no-focus' })
end

function M.open(path)
  -- Herdr requires the primary checkout as the source, even for an existing worktree.
  local repo = git(path, { 'worktree', 'list', '--porcelain', '-z' }):match('^worktree ([^%z]+)')
  return M.herdr({ 'worktree', 'open', '--cwd', repo, '--path', path, '--no-focus' })
end

return M
