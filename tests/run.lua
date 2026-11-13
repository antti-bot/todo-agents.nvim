local plugin = vim.fn.getcwd()
vim.opt.rtp:prepend(plugin)
local agent = require('todo_agents')
local worktree = require('todo_agents.worktree')
local function eq(a, b) assert(vim.deep_equal(a, b), vim.inspect(a) .. ' != ' .. vim.inspect(b)) end
local function git(path, args)
  local argv = { 'git', '-C', path }
  local result = vim.system(vim.list_extend(argv, args), { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
local function launches()
  if vim.fn.filereadable(vim.env.TODO_TEST_LAUNCHES) == 0 then return {} end
  return vim.tbl_map(vim.json.decode, vim.fn.readfile(vim.env.TODO_TEST_LAUNCHES))
end
local function key()
  assert(vim.fn.maparg('gx', 'n', false, true).callback() ~= false, 'gx failed')
end
local function test()
  local root = vim.env.XDG_STATE_HOME .. '/repos with spaces'
  local repos = { root .. '/api', root .. '/web' }
  for _, path in ipairs(repos) do
    vim.fn.mkdir(path, 'p')
    git(path, { 'init', '-b', 'main' })
    git(path, { 'config', 'user.name', 'Test' })
    git(path, { 'config', 'user.email', 'test@example.invalid' })
    vim.fn.writefile({ 'main' }, path .. '/file.txt')
    git(path, { 'add', '.' }); git(path, { 'commit', '-m', 'Main' })
  end
  git(repos[1], { 'checkout', '-b', 'feature' })
  vim.fn.writefile({ 'feature' }, repos[1] .. '/file.txt')
  git(repos[1], { 'commit', '-am', 'Feature' })
  vim.fn.writefile({ 'unsaved checkout change' }, repos[1] .. '/file.txt')
  local lines = { '#### ./api/', '- [ ] Fix [login]; $(touch should-not-exist)', '', '# ./web/', '- [ ] Search' }
  local file = root .. '/todo.md'
  vim.fn.writefile(lines, file)
  local fallback = 0
  vim.keymap.set('n', 'gx', function() fallback = fallback + 1 end)
  agent.setup({ command = { 'python3', plugin .. '/tests/fake_codex.py', 'literal; $(touch should-not-exist)' } })
  vim.cmd.edit(vim.fn.fnameescape(file))
  local todo = vim.api.nvim_get_current_buf()
  eq(vim.fn.maparg('gx', 'n', false, true).buffer, 1)
  eq(vim.fn.exists(':Todo'), 0)
  eq(vim.fn.exists(':TodoAgent'), 0)
  eq(worktree.selected(todo, 2), repos[1])
  eq(worktree.selected(todo, 5), repos[2])
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  local windows = #vim.api.nvim_list_wins()
  key()
  eq(vim.api.nvim_get_current_buf(), todo)
  eq(#vim.api.nvim_list_wins(), windows)
  assert(vim.wait(5000, function() return #launches() == 1 end, 50))
  local started = launches()[1]
  local linked = vim.api.nvim_get_current_line()
  local uri = assert(linked:match('%((herdr://[^)]+)%)$'))
  eq(vim.uri_decode(uri:sub(9)), started.cwd)
  assert(uri:find('%%20') and uri:find('%%28'))
  eq(started.argv, { 'literal; $(touch should-not-exist)' })
  eq(vim.fn.readfile(file), lines)
  eq(vim.fn.readfile(started.cwd .. '/file.txt'), { 'main' })
  eq(git(started.cwd, { 'rev-parse', 'HEAD' }), git(repos[1], { 'rev-parse', 'main' }))
  eq(vim.fn.filereadable(started.cwd .. '/should-not-exist'), 0)
  assert(git(started.cwd, { 'branch', '--show-current' }):match('^todo%-agent/'))
  local opened = worktree.open(started.cwd)
  local workspace = opened.workspace.workspace_id
  assert(vim.wait(5000, function()
    local panes = worktree.herdr({ 'pane', 'list', '--workspace', workspace }).panes
    return panes[1].agent == 'codex'
  end, 50))
  local review = worktree.herdr({ 'tab', 'create', '--workspace', workspace, '--label', 'Changes', '--focus' })
  eq(review.root_pane.cwd, started.cwd)
  vim.fn.writefile({ 'agent edit' }, started.cwd .. '/file.txt')
  eq(git(started.cwd, { 'diff', 'main', '--', 'file.txt' }):find('+agent edit', 1, true) ~= nil, true)
  vim.api.nvim_buf_set_text(todo, 1, 3, 1, 4, { 'x' })
  key()
  local panes = worktree.herdr({ 'pane', 'list', '--workspace', workspace }).panes
  for _, pane in ipairs(panes) do
    if pane.pane_id == started.pane then eq(pane.focused, true) end
  end
  eq(#launches(), 1)
  -- Move the link below another repo: it still opens the original worktree.
  vim.api.nvim_buf_set_lines(todo, 0, -1, false, { '# ./web/', '[Existing task](' .. uri .. ')', 'https://example.com' })
  vim.api.nvim_win_set_cursor(0, { 2, 4 }); key()
  eq(#launches(), 1)
  vim.api.nvim_win_set_cursor(0, { 3, 3 }); key(); eq(fallback, 1)
  -- Invalid headings, checked tasks, and fenced examples have no side effects or errors.
  local echo, errors = vim.api.nvim_echo, 0
  vim.api.nvim_echo = function() errors = errors + 1 end
  for _, content in ipairs({
    { repos[1], '# Missing folder', '- [ ] Ignore' },
    { './missing/', '- [ ] Ignore' },
    { root, '- [ ] Not a repo' },
    { repos[1], '- [x] Done' },
    { repos[1], '```', '- [ ] Example' },
    { repos[1], '~~~', '[Example](' .. uri .. ')' },
  }) do
    vim.api.nvim_buf_set_lines(todo, 0, -1, false, content)
    vim.api.nvim_win_set_cursor(0, { #content, 0 }); key()
    eq(vim.api.nvim_buf_get_lines(todo, 0, -1, false), content)
  end
  eq(errors, 0)
  eq(#launches(), 1)
  vim.api.nvim_echo = echo
  -- Missing main, read-only buffers, and server errors leave tasks untouched.
  vim.api.nvim_buf_set_lines(todo, 0, -1, false, { repos[2], '- [ ] Keep this task' })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  local before = git(repos[2], { 'worktree', 'list', '--porcelain' })
  git(repos[2], { 'branch', '-m', 'main', 'trunk' })
  eq(pcall(agent.open), false)
  git(repos[2], { 'branch', '-m', 'trunk', 'main' })
  eq(git(repos[2], { 'worktree', 'list', '--porcelain' }), before)
  vim.bo[todo].modifiable = false
  eq(pcall(agent.open), false)
  vim.bo[todo].modifiable = true
  local socket = vim.env.HERDR_SOCKET_PATH
  vim.env.HERDR_SOCKET_PATH = vim.env.XDG_STATE_HOME .. '/missing.sock'
  eq(pcall(agent.open), false)
  vim.env.HERDR_SOCKET_PATH = socket
  eq(vim.api.nvim_get_current_line(), '- [ ] Keep this task')
  eq(#launches(), 1)
  -- Outside Herdr, fail without starting a session or modifying the TODO.
  vim.api.nvim_buf_set_lines(todo, 0, -1, false, { repos[2], '- [ ] Outside Herdr' })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.env.HERDR_ENV = nil
  eq(pcall(agent.open), false)
  eq(vim.api.nvim_get_current_line(), '- [ ] Outside Herdr')
  vim.env.HERDR_ENV = '1'
  -- A second task belongs to its own repo and workspace.
  key()
  assert(vim.wait(5000, function() return #launches() == 2 end, 50))
  local second = launches()[2]
  assert(second.cwd ~= started.cwd and second.pane ~= started.pane)
  eq(git(second.cwd, { 'rev-parse', 'HEAD' }), git(repos[2], { 'rev-parse', 'main' }))
  eq(vim.fn.isdirectory(vim.fn.stdpath('state') .. '/todo-agents'), 0)
  vim.fn.writefile({ uri, started.cwd, started.pane, workspace }, vim.env.XDG_STATE_HOME .. '/reopen-task')
  print('Herdr worktrees, agent navigation, review tabs, repo scope, and quoting passed')
end
local ok, err = xpcall(test, debug.traceback)
if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit 1') else vim.cmd('qa!') end
