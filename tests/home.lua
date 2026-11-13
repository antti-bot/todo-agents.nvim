-- Keep home-directory worktrees inside the temporary test sandbox.
local expand = vim.fn.expand
vim.fn.expand = function(path, ...)
  if path == '~/.todo-agents/worktrees' then
    return vim.env.XDG_STATE_HOME .. '/home/.todo-agents/worktrees'
  end
  return expand(path, ...)
end
