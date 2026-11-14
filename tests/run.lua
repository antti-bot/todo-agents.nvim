local plugin = vim.fn.getcwd()
vim.opt.rtp:prepend(plugin)

local agent = require('todo_agents')
local worktree = require('todo_agents.worktree')

local function assert_equal(actual, expected)
  assert(vim.deep_equal(actual, expected), vim.inspect(actual) .. ' != ' .. vim.inspect(expected))
end

local function git(path, arguments)
  local command = { 'git', '-C', path }
  local result = vim.system(vim.list_extend(command, arguments), { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end

local function launches()
  if vim.fn.filereadable(vim.env.TODO_TEST_LAUNCHES) == 0 then
    return {}
  end
  return vim.tbl_map(vim.json.decode, vim.fn.readfile(vim.env.TODO_TEST_LAUNCHES))
end

local function press_gx()
  assert(vim.fn.maparg('gx', 'n', false, true).callback() ~= false, 'gx failed')
end

local function create_repository(path)
  vim.fn.mkdir(path, 'p')
  git(path, { 'init', '-b', 'main' })
  git(path, { 'config', 'user.name', 'Test' })
  git(path, { 'config', 'user.email', 'test@example.invalid' })
  vim.fn.writefile({ 'main' }, path .. '/file.txt')
  git(path, { 'add', '.' })
  git(path, { 'commit', '-m', 'Main' })
end

local function create_fixture()
  local root = vim.env.XDG_STATE_HOME .. '/repos with spaces'
  local fixture = {
    root = root,
    api_repository = root .. '/api',
    web_repository = root .. '/web',
    todo_file = root .. '/todo.md',
    original_lines = {
      '#### ./api/',
      '- [ ] Fix [login]; $(touch should-not-exist)',
      '',
      '# ./web/',
      '- [ ] Search',
    },
    fallback_calls = 0,
  }
  create_repository(fixture.api_repository)
  create_repository(fixture.web_repository)

  -- Starting a task must use main, even with a dirty feature branch checked out.
  git(fixture.api_repository, { 'checkout', '-b', 'feature' })
  vim.fn.writefile({ 'feature' }, fixture.api_repository .. '/file.txt')
  git(fixture.api_repository, { 'commit', '-am', 'Feature' })
  vim.fn.writefile({ 'unsaved checkout change' }, fixture.api_repository .. '/file.txt')

  vim.fn.writefile(fixture.original_lines, fixture.todo_file)
  vim.keymap.set('n', 'gx', function()
    fixture.fallback_calls = fixture.fallback_calls + 1
  end)
  agent.setup({ command = { 'python3', plugin .. '/tests/fake_codex.py', 'literal; $(touch should-not-exist)' } })
  vim.cmd.edit(vim.fn.fnameescape(fixture.todo_file))
  fixture.buffer = vim.api.nvim_get_current_buf()
  return fixture
end

local function test_buffer_setup(fixture)
  assert_equal(vim.fn.maparg('gx', 'n', false, true).buffer, 1)
  assert_equal(vim.fn.exists(':Todo'), 0)
  assert_equal(vim.fn.exists(':TodoAgent'), 0)
  assert_equal(worktree.resolve_task_repository(fixture.buffer, 2, false), fixture.api_repository)
  assert_equal(worktree.resolve_task_repository(fixture.buffer, 5, false), fixture.web_repository)
end

local function test_start_task(fixture)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  local window_count = #vim.api.nvim_list_wins()
  press_gx()
  assert_equal(vim.api.nvim_get_current_buf(), fixture.buffer)
  assert_equal(#vim.api.nvim_list_wins(), window_count)
  assert(vim.wait(5000, function() return #launches() == 1 end, 50))

  local started = launches()[1]
  local linked_line = vim.api.nvim_get_current_line()
  local uri = assert(linked_line:match('%((herdr://[^)]+)%)$'))
  assert_equal(vim.uri_decode(uri:sub(9)), started.cwd)
  assert(uri:find('%%20') and uri:find('%%28'))
  assert_equal(started.argv, { 'literal; $(touch should-not-exist)' })
  assert_equal(vim.fn.readfile(fixture.todo_file), fixture.original_lines)
  assert_equal(vim.fn.readfile(started.cwd .. '/file.txt'), { 'main' })
  assert_equal(git(started.cwd, { 'rev-parse', 'HEAD' }), git(fixture.api_repository, { 'rev-parse', 'main' }))
  assert_equal(vim.fn.filereadable(started.cwd .. '/should-not-exist'), 0)
  assert(git(started.cwd, { 'branch', '--show-current' }):match('^todo%-agent/'))

  local opened = worktree.open(started.cwd)
  return { launch = started, uri = uri, workspace_id = opened.workspace.workspace_id }
end

local function test_review_navigation(fixture, task)
  local started = task.launch
  assert(vim.wait(5000, function()
    local panes = worktree.herdr({ 'pane', 'list', '--workspace', task.workspace_id }).panes
    return panes[1].agent == 'codex'
  end, 50))
  local review = worktree.herdr({ 'tab', 'create', '--workspace', task.workspace_id, '--label', 'Changes', '--focus' })
  assert_equal(review.root_pane.cwd, started.cwd)
  vim.fn.writefile({ 'agent edit' }, started.cwd .. '/file.txt')
  local diff = git(started.cwd, { 'diff', 'main', '--', 'file.txt' })
  assert(diff:find('+agent edit', 1, true), 'Review diff is missing the agent edit')

  -- Checked tasks still navigate to their existing agent.
  vim.api.nvim_buf_set_text(fixture.buffer, 1, 3, 1, 4, { 'x' })
  press_gx()
  local panes = worktree.herdr({ 'pane', 'list', '--workspace', task.workspace_id }).panes
  local agent_pane
  for _, pane in ipairs(panes) do
    if pane.pane_id == started.pane then
      agent_pane = pane
      break
    end
  end
  assert(agent_pane, 'The task agent pane is missing from its workspace')
  assert_equal(agent_pane.focused, true)
  assert_equal(#launches(), 1)
end

local function test_relocated_link_and_fallback(fixture, task)
  -- Moving the link under another repository must retain its original destination.
  vim.api.nvim_buf_set_lines(fixture.buffer, 0, -1, false, {
    '# ./web/',
    '[Existing task](' .. task.uri .. ')',
    'https://example.com',
  })
  vim.api.nvim_win_set_cursor(0, { 2, 4 })
  press_gx()
  assert_equal(#launches(), 1)
  vim.api.nvim_win_set_cursor(0, { 3, 3 })
  press_gx()
  assert_equal(fixture.fallback_calls, 1)
end

local function test_ignored_tasks(fixture, task)
  local original_echo = vim.api.nvim_echo
  local error_count = 0
  vim.api.nvim_echo = function()
    error_count = error_count + 1
  end
  for _, content in ipairs({
    { fixture.api_repository, '# Missing folder', '- [ ] Ignore' },
    { './missing/', '- [ ] Ignore' },
    { fixture.root, '- [ ] Not a repo' },
    { fixture.api_repository, '- [x] Done' },
    { fixture.api_repository, '```', '- [ ] Example' },
    { fixture.api_repository, '~~~', '[Example](' .. task.uri .. ')' },
  }) do
    vim.api.nvim_buf_set_lines(fixture.buffer, 0, -1, false, content)
    vim.api.nvim_win_set_cursor(0, { #content, 0 })
    press_gx()
    assert_equal(vim.api.nvim_buf_get_lines(fixture.buffer, 0, -1, false), content)
  end
  vim.api.nvim_echo = original_echo
  assert_equal(error_count, 0)
  assert_equal(#launches(), 1)
end

local function test_failed_creation(fixture)
  vim.api.nvim_buf_set_lines(fixture.buffer, 0, -1, false, {
    fixture.web_repository,
    '- [ ] Keep this task',
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  local original_worktrees = git(fixture.web_repository, { 'worktree', 'list', '--porcelain' })
  git(fixture.web_repository, { 'branch', '-m', 'main', 'trunk' })
  assert_equal(pcall(agent.open), false)
  git(fixture.web_repository, { 'branch', '-m', 'trunk', 'main' })
  assert_equal(git(fixture.web_repository, { 'worktree', 'list', '--porcelain' }), original_worktrees)

  vim.bo[fixture.buffer].modifiable = false
  assert_equal(pcall(agent.open), false)
  vim.bo[fixture.buffer].modifiable = true

  local original_socket = vim.env.HERDR_SOCKET_PATH
  vim.env.HERDR_SOCKET_PATH = vim.env.XDG_STATE_HOME .. '/missing.sock'
  assert_equal(pcall(agent.open), false)
  vim.env.HERDR_SOCKET_PATH = original_socket
  assert_equal(vim.api.nvim_get_current_line(), '- [ ] Keep this task')
  assert_equal(#launches(), 1)
end

local function test_outside_herdr(fixture)
  vim.api.nvim_buf_set_lines(fixture.buffer, 0, -1, false, {
    fixture.web_repository,
    '- [ ] Outside Herdr',
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.env.HERDR_ENV = nil
  assert_equal(pcall(agent.open), false)
  vim.env.HERDR_ENV = '1'
  assert_equal(vim.api.nvim_get_current_line(), '- [ ] Outside Herdr')
  assert_equal(#launches(), 1)
end

local function test_second_repository(fixture, task)
  vim.api.nvim_buf_set_lines(fixture.buffer, 0, -1, false, {
    fixture.web_repository,
    '- [ ] Second task',
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  press_gx()
  assert(vim.wait(5000, function() return #launches() == 2 end, 50))
  local second = launches()[2]
  assert(second.cwd ~= task.launch.cwd and second.pane ~= task.launch.pane)
  assert_equal(git(second.cwd, { 'rev-parse', 'HEAD' }), git(fixture.web_repository, { 'rev-parse', 'main' }))
  assert_equal(vim.fn.isdirectory(vim.fn.stdpath('state') .. '/todo-agents'), 0)
end

local function test()
  local fixture = create_fixture()
  test_buffer_setup(fixture)
  local task = test_start_task(fixture)
  test_review_navigation(fixture, task)
  test_relocated_link_and_fallback(fixture, task)
  test_ignored_tasks(fixture, task)
  test_failed_creation(fixture)
  test_outside_herdr(fixture)
  test_second_repository(fixture, task)

  -- The next Neovim process verifies that the first task survives this one exiting.
  vim.fn.writefile({ task.uri, task.launch.cwd, task.launch.pane, task.workspace_id },
    vim.env.XDG_STATE_HOME .. '/reopen-task')
  print('Herdr worktrees, agent navigation, review tabs, repo scope, and quoting passed')
end

local ok, err = xpcall(test, debug.traceback)
if not ok then
  io.stderr:write(err .. '\n')
  vim.cmd('cquit 1')
else
  vim.cmd('qa!')
end
