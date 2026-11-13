if vim.g.loaded_todo_agents then return end
vim.g.loaded_todo_agents = true
local function command(name, fn, opts)
  vim.api.nvim_create_user_command(name, function(args) require('todo_agents.ui').call(fn, args) end, opts or {})
end
command('Todo', function(args) require('todo_agents').plan(args.args) end, { nargs = '?', complete = 'file', bar = true })
command('TodoAgent', function(args) require('todo_agents').open(args.smods.vertical) end, { bar = true })
command('TodoAgentBind', function(args) require('todo_agents').bind(args.args) end, { nargs = 1 })
command('TodoAgentCleanup', function() require('todo_agents').cleanup() end)
