local M = {}

function M.parse(line)
  local prefix, check, body = line:match('^(%s*[-*+]%s+)%[([ xX])%]%s+(.+)$')
  if not prefix then prefix, check, body = line:match('^(%s*%d+[.)]%s+)%[([ xX])%]%s+(.+)$') end
  if not prefix then return nil end
  local label, id = body:match('^%[(.*)%]%(codex://([%w_-]+)%)%s*$')
  local pending = false
  if not id then
    label, id = body:match('^%[(.*)%]%(codex://task/([%w_-]+)%)%s*$')
    pending = id ~= nil
  end
  return { prefix = prefix, check = check, text = label or body, id = id, pending = pending }
end

function M.id(line, col)
  local first, last, uri = line:find('(codex://[%w_/-]+)')
  if not first then return end
  local label = line:sub(1, first - 1):match('.*()%[')
  if col and (col + 1 < (label or first) or col + 1 > last) then return end
  return uri:match('^codex://([%w_-]+)$') or uri:match('^codex://task/([%w_-]+)$')
end

function M.link(task, id, pending)
  local text = task.text:gsub('\\', '\\\\'):gsub('%[', '\\['):gsub('%]', '\\]')
  return task.prefix .. '[' .. task.check .. '] [' .. text .. '](codex://' .. (pending and 'task/' or '') .. id .. ')'
end

function M.contains(lines)
  local fence
  for _, line in ipairs(lines) do
    local marker = line:match('^%s*(```+)') or line:match('^%s*(~~~+)')
    if marker then
      if not fence then fence = marker:sub(1, 1) elseif fence == marker:sub(1, 1) then fence = nil end
    elseif not fence and (M.parse(line) or M.id(line)) then return true end
  end
  return false
end

function M.prompt(task, path, row, snapshot)
  return table.concat({ 'Task: ' .. task.text, 'Source: ' .. (path ~= '' and path or '[unnamed buffer]') .. ':' .. row,
    'Read the TODO buffer snapshot for context: ' .. snapshot,
    'It includes unsaved edits. Work only on this task; leave its checkbox unchanged.' }, '\n')
end

return M
