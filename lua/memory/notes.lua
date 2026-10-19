local M = {}

local INDEX = "MEMORY.md"
local TOPIC = "notes"
local LINES = 200
local BYTES = 25 * 1024

local function trimmed(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function directory()
  local info = uji.session.info()
  return info.directory ~= "" and info.directory or uji.os.cwd()
end

local function project()
  local at = directory()
  while at do
    if uji.fs.stat(uji.fs.join(at, ".git")) then
      return at
    end
    at = uji.fs.parent(at)
  end
  return directory()
end

local function slug(name)
  local cleaned = tostring(name or ""):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  return cleaned ~= "" and cleaned or nil
end

function M.folder()
  local data = uji.data.dir()
  if not data then
    return nil
  end
  local parts = {}
  for part in (project():gsub("^[/\\]+", "")):gmatch("[^/\\]+") do
    parts[#parts + 1] = (part:gsub(":", ""))
  end
  return uji.fs.join(data, "memory", table.concat(parts, "/"))
end

function M.path()
  local folder = M.folder()
  return folder and uji.fs.join(folder, INDEX)
end

function M.topics()
  local folder = M.folder()
  if not folder then
    return {}
  end
  local found = {}
  for _, entry in ipairs(uji.fs.list(folder) or {}) do
    if entry.type == "file" and entry.name ~= INDEX and entry.name:match("%.md$") then
      local path = uji.fs.join(folder, entry.name)
      local text = uji.fs.read(path)
      found[#found + 1] = { scope = "notes", path = path, text = type(text) == "string" and text or nil }
    end
  end
  return found
end

function M.read()
  local path = M.path()
  local text = path and uji.fs.read(path)
  if type(text) ~= "string" then
    return nil
  end
  text = trimmed(text)
  if text == "" then
    return nil
  end
  local cut = #text > BYTES
  if cut then
    text = text:sub(1, BYTES)
  end
  local kept = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if #kept == LINES then
      cut = true
      break
    end
    kept[#kept + 1] = line
  end
  return { path = path, text = table.concat(kept, "\n"), cut = cut }
end

function M.section()
  local notes = M.read()
  if not notes then
    return nil
  end
  return table.concat({
    "# Notes",
    "",
    string.format(
      "What you have learned while working here. The index is %s, and each line of it names a file beside it that you read with `read_file` when one of them matters. Add to them with the `remember` tool. Keep one line per note: uji reads the first %d lines of the index.",
      notes.path,
      LINES
    ),
    "",
    notes.text,
  }, "\n")
end

function M.add(text, topic)
  local note = trimmed(type(text) == "string" and text or "")
  if note == "" then
    return nil, "a note needs some text"
  end
  local folder = M.folder()
  if not folder then
    return nil, "uji has no data folder to keep its notes in"
  end
  local name = slug(topic) or TOPIC
  local path = uji.fs.join(folder, name .. ".md")
  local before = uji.fs.read(path) or ""
  local lead = (before == "" or before:sub(-1) == "\n") and "" or "\n"
  local written, err = uji.fs.write(path, before .. lead .. "- " .. note .. "\n")
  if not written then
    return nil, err or ("cannot write " .. path)
  end
  local index = M.path()
  local kept = uji.fs.read(index) or ""
  if not kept:find("](" .. name .. ".md)", 1, true) then
    local summary = note:gsub("%s+", " ")
    if #summary > 100 then
      summary = summary:sub(1, 100) .. "…"
    end
    local endline = (kept == "" or kept:sub(-1) == "\n") and "" or "\n"
    kept = kept .. endline .. "- [" .. name .. "](" .. name .. ".md) — " .. summary .. "\n"
    local ok, problem = uji.fs.write(index, kept)
    if not ok then
      return path, "cannot write the index: " .. tostring(problem)
    end
  end
  local _, count = kept:gsub("\n", "")
  if count > LINES or #kept > BYTES then
    return path, string.format("%s is over %d lines; shorten the index so uji keeps reading it", index, LINES)
  end
  return path
end

return M
