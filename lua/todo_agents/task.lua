local M = {}

function M.parse(line)
  local prefix, check, body = line:match('^(%s*[-*+]%s+)%[([ xX])%]%s+(.+)$')
  if not prefix then
    prefix, check, body = line:match('^(%s*%d+[.)]%s+)%[([ xX])%]%s+(.+)$')
  end
  if not prefix then return nil end
  local label, provider, id = body:match('^%[(.*)%]%(todo%-agent://([%w_-]+)/([%w_-]+)%)%s*$')
  return { prefix = prefix, check = check, text = label or body, provider = provider, id = id }
end

function M.link(task, provider, id)
  local text = task.text:gsub('\\', '\\\\'):gsub('%[', '\\['):gsub('%]', '\\]')
  return task.prefix .. '[' .. task.check .. '] [' .. text .. '](todo-agent://' .. provider .. '/' .. id .. ')'
end

function M.prompt(task, path, row, snapshot)
  return table.concat({
    'Work on this TODO item:', task.text, '',
    'Source: ' .. path .. ':' .. row,
    'Read the complete TODO buffer snapshot for context: ' .. snapshot,
    'The snapshot includes unsaved edits at launch time. Treat surrounding tasks as context,',
    'and work only on the selected task. Do not mark it complete automatically.',
  }, '\n')
end

return M
