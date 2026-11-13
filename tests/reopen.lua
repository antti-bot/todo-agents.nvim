local plugin = vim.fn.getcwd()
vim.opt.rtp:prepend(plugin)
local agent = require('todo_agents')
local herdr = require('todo_agents.worktree').herdr
local function test()
  local saved = vim.fn.readfile(vim.env.XDG_STATE_HOME .. '/reopen-task')
  local uri, path, pane_id, workspace = unpack(saved)
  assert(vim.fn.isdirectory(path) == 1, 'Neovim exit removed the worktree')
  local panes = herdr({ 'pane', 'list', '--workspace', workspace }).panes
  local alive = false
  for _, pane in ipairs(panes) do
    if pane.pane_id == pane_id then alive = pane.agent == 'codex' end
  end
  assert(alive, 'Neovim exit stopped the agent')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '[Task](' .. uri .. ')' })
  agent.setup()
  agent.open()
  local launch_count = #vim.fn.readfile(vim.env.TODO_TEST_LAUNCHES)
  assert(launch_count == 2, 'Reopening started another agent')
  assert(vim.fn.readfile(path .. '/file.txt')[1] == 'agent edit')
  -- Workspace IDs can change: the saved path still reopens the checkout.
  herdr({ 'workspace', 'close', workspace })
  agent.open()
  local reopened = require('todo_agents.worktree').open(path)
  assert(reopened.workspace.workspace_id ~= workspace)
  assert(vim.fn.readfile(path .. '/file.txt')[1] == 'agent edit')
  assert(#vim.fn.readfile(vim.env.TODO_TEST_LAUNCHES) == 2)
  print('Neovim restart preserves agents; closed workspaces reopen without losing edits')
end
local ok, err = xpcall(test, debug.traceback)
if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit 1') else vim.cmd('qa!') end
