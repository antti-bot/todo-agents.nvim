local M = {}
function M.call(fn, ...)
  local ok, result = pcall(fn, ...)
  if not ok then
    local message = tostring(result):gsub('^.-:%d+: ', '')
    vim.api.nvim_echo({ { message, 'ErrorMsg' } }, true, { err = true })
  end
  return ok, result
end
return M
