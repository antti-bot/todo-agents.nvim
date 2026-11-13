if vim.g.loaded_todo_agents then return end
vim.g.loaded_todo_agents = true
local function run(fn)
  return function(args)
    local ok, err = pcall(fn, args)
    if not ok then vim.notify('todo-agents: ' .. tostring(err), vim.log.levels.ERROR) end
  end
end
vim.api.nvim_create_user_command('TodoAgent', run(function(args)
  require('todo_agents').start(args.args ~= '' and args.args or nil)
end), { nargs = '?', complete = function() return { 'codex', 'claude' } end })
vim.api.nvim_create_user_command('TodoAgentOpen', run(function() require('todo_agents').open() end), {})
vim.api.nvim_create_user_command('TodoAgentToggle', run(function() require('todo_agents').toggle() end), {})
vim.api.nvim_create_user_command('TodoAgentBind', run(function(args) require('todo_agents').bind(args.args) end), { nargs = 1 })

vim.api.nvim_create_user_command('TodoAgentCleanup', run(function() require('todo_agents').cleanup() end), {})
