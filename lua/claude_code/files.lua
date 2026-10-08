local M = {}

local function replaced(text, old, new, all)
  local parts, at = {}, 1
  repeat
    local first, last = text:find(old, at, true)
    if not first then
      break
    end
    parts[#parts + 1] = text:sub(at, first - 1)
    parts[#parts + 1] = new
    at = last + 1
  until not all
  parts[#parts + 1] = text:sub(at)
  return table.concat(parts)
end

local function lines(count)
  return count .. (count == 1 and " line" or " lines")
end

local function counted(content)
  local _, newlines = content:gsub("\n", "")
  return (content ~= "" and content:sub(-1) ~= "\n") and newlines + 1 or newlines
end

local function relative(args)
  local path = type(args.file_path) == "string" and args.file_path or nil
  local directory = uji.session.info().directory
  if not path or directory == "" or path:sub(1, #directory) ~= directory then
    return path
  end
  local rest = path:sub(#directory + 2)
  return rest ~= "" and uji.fs.join(directory, rest) == path and rest or path
end

local function edited(args)
  local text = type(args.file_path) == "string" and uji.fs.read(args.file_path)
  if not text or type(args.old_string) ~= "string" or type(args.new_string) ~= "string" then
    return nil
  end
  return uji.diff(text, replaced(text, args.old_string, args.new_string, args.replace_all == true), args.file_path)
end

local function written(args)
  if type(args.file_path) ~= "string" or type(args.content) ~= "string" then
    return nil
  end
  return uji.diff(uji.fs.read(args.file_path) or "", args.content, args.file_path)
end

function M.register()
  uji.tool.display("Edit", { label = "Update", subject = relative, preview = edited })
  uji.tool.display("MultiEdit", { label = "Update", subject = relative })
  uji.tool.display("Write", { label = "Write", subject = relative, preview = written })
  uji.tool.display("Read", { label = "Read", subject = relative })
  uji.tool.display("Bash", {
    label = "Bash",
    subject = function(args)
      return type(args.command) == "string" and args.command or nil
    end,
  })
end

function M.shown(raw)
  if type(raw) ~= "table" then
    return {}
  end
  local original, path = raw.originalFile, raw.filePath
  if raw.type == "create" and type(raw.content) == "string" then
    return { summary = "Wrote " .. lines(counted(raw.content)) }
  elseif raw.type == "update" and type(original) == "string" and type(raw.content) == "string" then
    return { diff = uji.diff(original, raw.content, path), summary = "Wrote " .. lines(counted(raw.content)) }
  elseif type(original) == "string" and type(raw.oldString) == "string" and type(raw.newString) == "string" then
    return { diff = uji.diff(original, replaced(original, raw.oldString, raw.newString, raw.replaceAll == true), path) }
  elseif raw.type == "text" and type(raw.file) == "table" and type(raw.file.numLines) == "number" then
    return { summary = "Read " .. lines(raw.file.numLines) }
  end
  return {}
end

return M
