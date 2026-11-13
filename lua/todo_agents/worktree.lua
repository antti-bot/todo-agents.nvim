local M = {}
local uv = vim.uv or vim.loop

local function git(root, args)
  local argv = { 'git', '-C', root }
  vim.list_extend(argv, args)
  local result = vim.system(argv, { text = true }):wait(10000)
  if result.code ~= 0 then error('Git: ' .. vim.trim(result.stderr or result.stdout or 'command failed')) end
  return vim.trim(result.stdout or '')
end

function M.prepare(record, state)
  if record.isolated == false then return end
  if not record.worktree then
    record.repo = git(record.cwd, { 'rev-parse', '--show-toplevel' })
    git(record.repo, { 'rev-parse', '--verify', 'HEAD' })
    record.branch = 'todo-agent/' .. record.id
    record.worktree = state .. '/worktrees/' .. record.id
    record.isolated = true
    vim.fn.mkdir(state .. '/worktrees', 'p', 448)
    git(record.repo, { 'worktree', 'add', '-b', record.branch, record.worktree, 'HEAD' })
  elseif not uv.fs_stat(record.worktree) then
    -- Branches survive cleanup, retaining commits and the exact resume point.
    git(record.repo, { 'worktree', 'add', record.worktree, record.branch })
  else
    local branch = git(record.worktree, { 'symbolic-ref', '--short', 'HEAD' })
    if branch ~= record.branch then error('Task worktree is on another branch: ' .. branch) end
  end
  record.cwd = record.worktree
end

function M.cleanup(record)
  if not record.worktree or not uv.fs_stat(record.worktree) then return true end
  local attached, branch = pcall(git, record.worktree, { 'symbolic-ref', '--short', 'HEAD' })
  if not attached or branch ~= record.branch then
    return false, 'Keeping task worktree with changed or detached HEAD: ' .. record.worktree
  end
  -- Include ignored files too; a build output or local secret must not be discarded.
  local status = git(record.worktree, { 'status', '--porcelain', '--untracked-files=all', '--ignored' })
  if status ~= '' then
    return false, 'Keeping task worktree with local files or changes: ' .. record.worktree
  end
  git(record.repo, { 'worktree', 'remove', record.worktree })
  return true
end

return M
