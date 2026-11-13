local plugin = vim.fn.getcwd()
vim.opt.rtp:prepend(plugin)
local agent = require('todo_agents')
vim.cmd.cd(vim.fn.fnameescape(vim.fn.stdpath('state') .. '/project with spaces'))
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '- [ ] Test shutdown cleanup' })
agent.setup({ mappings = false, command = { 'python3', plugin .. '/tests/fake_codex.py' } })
agent.open()
local id = vim.b.todo_agent_id
local path = vim.fn.stdpath('state') .. '/todo-agents/worktrees/' .. id
assert((vim.uv or vim.loop).fs_stat(path))
vim.fn.writefile({ path }, vim.env.XDG_STATE_HOME .. '/shutdown-worktree')
vim.cmd('qa!')
