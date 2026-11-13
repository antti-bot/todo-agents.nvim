local M = {}
local uv = vim.uv or vim.loop

local function git(path, args)
  local argv = { 'git', '-C', path }
  vim.list_extend(argv, args)
  local result = vim.system(argv, { text = true }):wait(10000)
  if result.code ~= 0 then error(vim.trim(result.stderr), 0) end
  return vim.trim(result.stdout)
end

function M.base(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  return path ~= '' and vim.fs.dirname(path) or vim.fn.getcwd()
end

function M.root(path)
  local ok, root = pcall(git, path, { 'rev-parse', '--show-toplevel' })
  return ok and (uv.fs_realpath(root) or root) or path
end

function M.absolute(path, base)
  if path:sub(1, 2) == '~/' then path = vim.fn.expand('~') .. path:sub(2) end
  if path:sub(1, 1) ~= '/' then path = base .. '/' .. path end
  return vim.fs.normalize(path)
end

function M.folder(line, base)
  local path = vim.trim(line):gsub('^#+%s+', '')
  if path == '' then return end
  local explicit = path:match('^%.%./') or path:match('^%./') or path:match('^~/')
    or path:match('^/') or path:match('/$')
  local stat = uv.fs_stat(M.absolute(path, base))
  if explicit or (stat and stat.type == 'directory') then return path end
end

function M.selected(buf, row)
  local base = M.base(buf)
  local path, fence = base, nil
  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, row, false)) do
    local marker = line:match('^%s*(```+)') or line:match('^%s*(~~~+)')
    if marker then
      if not fence then fence = marker:sub(1, 1)
      elseif fence == marker:sub(1, 1) then fence = nil end
    elseif not fence and i < row and not line:match('^%s') then
      local folder = M.folder(line, base)
      if folder then path = M.absolute(folder, base) end
    end
  end
  if fence then error('Task is inside a code block', 0) end
  return path
end

function M.validate(path)
  local root = git(path, { 'rev-parse', '--show-toplevel' })
  root = uv.fs_realpath(root) or root
  git(root, { 'rev-parse', '--verify', 'HEAD' })
  return root
end

return M
