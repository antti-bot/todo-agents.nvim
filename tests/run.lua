vim.opt.rtp:prepend(vim.fn.getcwd())
vim.cmd('runtime plugin/todo_agents.lua')
local task = require('todo_agents.task')
local agent = require('todo_agents')
local function eq(a, b) assert(vim.deep_equal(a, b), vim.inspect(a) .. ' != ' .. vim.inspect(b)) end
local function line(text)
  vim.cmd('enew!')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { text, 'Context: keep this unsaved text.' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
end
local function record(id)
  return vim.json.decode(table.concat(vim.fn.readfile(vim.fn.stdpath('state') .. '/todo-agents/' .. id .. '.json'), '\n'))
end
local function test()
  local launches = {}
  local termopen = vim.fn.termopen
  vim.fn.termopen = function(argv, opts)
    launches[#launches + 1] = vim.deepcopy(argv)
    return termopen(argv, opts)
  end
  for _, text in ipairs({ '- [ ] task', '  * [x] task', '+ [X] task', '12. [ ] task', '2) [ ] task' }) do
    assert(task.parse(text))
  end
  eq(task.parse('plain text'), nil)
  eq(task.parse('- [a] task'), nil)
  eq(task.link(task.parse('- [ ] Fix [login]'), 'codex', 'abc'), '- [ ] [Fix \\[login\\]](todo-agent://codex/abc)')
  line('- [ ] task')
  agent.toggle(); eq(vim.api.nvim_get_current_line(), '- [x] task')
  agent.toggle(); eq(vim.api.nvim_get_current_line(), '- [ ] task')
  agent.setup({ mappings = false, commands = { claude = { '/bin/sh', '-c', 'sleep 30', '--' },
    codex = { '/bin/sh', '-c', 'sleep 30', '--' } } })
  agent.start('claude')
  local terminal = vim.api.nvim_get_current_buf()
  local id = vim.b.todo_agent_id
  local meta = record(id)
  eq(meta.session_id, id)
  eq(launches[1][5], '--session-id')
  eq(launches[1][6], id)
  eq(launches[1][7], meta.prompt)
  assert(meta.prompt:find('task', 1, true))
  local snapshot = vim.fn.stdpath('state') .. '/todo-agents/' .. id .. '.md'
  eq(vim.fn.readfile(snapshot)[2], 'Context: keep this unsaved text.')
  vim.cmd('wincmd p')
  local todo = vim.api.nvim_get_current_buf()
  local linked = vim.api.nvim_get_current_line()
  eq(task.parse(linked).id, id)
  agent.toggle(); assert(vim.api.nvim_get_current_line():match('^%- %[x%]'))
  agent.open(); eq(vim.api.nvim_get_current_buf(), terminal)
  vim.fn.jobstop(vim.b.terminal_job_id)
  vim.wait(200, function() return false end)
  vim.api.nvim_set_current_buf(todo)
  agent.open(); assert(vim.b.terminal_job_id)
  eq(launches[2][5], '--resume')
  eq(launches[2][6], id)
  vim.fn.jobstop(vim.b.terminal_job_id)
  vim.wait(200, function() return false end)
  line('- [ ] another task')
  agent.start('codex')
  id = vim.b.todo_agent_id
  local transcript = vim.env.CODEX_HOME .. '/sessions/2026/11/13'
  vim.fn.mkdir(transcript, 'p')
  vim.fn.writefile({ vim.json.encode({ type = 'session_meta', payload = { id = 'test-session-uuid' } }),
    vim.json.encode({ type = 'event_msg', payload = { message = 'todo-agent-task:' .. id } }) }, transcript .. '/test.jsonl')
  assert(vim.wait(3500, function() return record(id).session_id == 'test-session-uuid' end, 100))
  agent.bind('manual-session-id'); eq(record(id).session_id, 'manual-session-id')
  vim.fn.jobstop(vim.b.terminal_job_id)
  vim.wait(200, function() return false end)
  line('- [ ] untouched')
  agent.setup({ commands = { codex = { '/does/not/exist' } } })
  local ok = pcall(agent.start, 'codex')
  eq(ok, false); eq(vim.api.nvim_get_current_line(), '- [ ] untouched')
  line('- [x] completed')
  eq(pcall(agent.start, 'claude'), false)
  print('All todo-agents tests passed')
end
local ok, err = xpcall(test, debug.traceback)
if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit 1') else vim.cmd('qa!') end
