local plugin = vim.fn.getcwd()
vim.opt.rtp:prepend(plugin)
local agent = require('todo_agents')
local saved = vim.fn.readfile(vim.env.XDG_STATE_HOME .. '/reopen-session')
local session, task = saved[1], saved[2]
local path = vim.fn.stdpath('state') .. '/todo-agents/worktrees/' .. task
assert(not (vim.uv or vim.loop).fs_stat(path))
local termopen = vim.fn.termopen
vim.fn.termopen = function(argv, opts)
  assert(argv[3] == 'resume' and argv[4] == session)
  assert(opts.cwd == path)
  return termopen(argv, opts)
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '[Session](codex://' .. session .. ')' })
agent.setup({ command = { 'python3', plugin .. '/tests/fake_codex.py' } })
agent.open()
assert((vim.uv or vim.loop).fs_stat(path))
vim.fn.jobstop(vim.b.terminal_job_id)
assert(vim.wait(3000, function() return not (vim.uv or vim.loop).fs_stat(path) end, 20))
print('Restart and resume test passed')
vim.cmd('qa!')
