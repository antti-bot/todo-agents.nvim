local M = {}
local uv = vim.uv or vim.loop

local function git(root, args)
  local argv = { 'git', '-C', root }
  vim.list_extend(argv, args)
  local result = vim.system(argv, { text = true }):wait(10000)
  if result.code ~= 0 then error(vim.trim(result.stderr or result.stdout or 'Git command failed'), 0) end
  return vim.trim(result.stdout or '')
end

function M.prepare(record, state)
  if not record.worktree then
    record.repo = require('todo_agents.repos').validate(record.cwd)
    record.branch = 'todo-agent/' .. record.id
    record.worktree = state .. '/worktrees/' .. record.id
    vim.fn.mkdir(state .. '/worktrees', 'p', 448)
    git(record.repo, { 'worktree', 'add', '-b', record.branch, record.worktree, 'HEAD' })
  elseif not uv.fs_stat(record.worktree) then
    git(record.repo, { 'show-ref', '--verify', 'refs/heads/' .. record.branch })
    git(record.repo, { 'worktree', 'add', record.worktree, record.branch })
  elseif git(record.worktree, { 'symbolic-ref', '--short', 'HEAD' }) ~= record.branch then
    error('Worktree is on another branch: ' .. record.worktree, 0)
  end
  record.cwd = record.worktree
end

function M.cleanup(record)
  if not record.worktree or not uv.fs_stat(record.worktree) then return true end
  local attached, branch = pcall(git, record.worktree, { 'symbolic-ref', '--short', 'HEAD' })
  if not attached or branch ~= record.branch then return false, 'HEAD changed: ' .. record.worktree end
  if git(record.worktree, { 'status', '--porcelain', '--untracked-files=all', '--ignored' }) ~= '' then
    return false, 'Local changes: ' .. record.worktree
  end
  git(record.repo, { 'worktree', 'remove', record.worktree })
  return true
end

return M
