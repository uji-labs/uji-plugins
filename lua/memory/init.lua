local ito = require("ito")
local Notes = require("memory.notes")

local M = {}

local function items()
  local found = {}
  local path = Notes.path()
  if path then
    found[#found + 1] = { scope = "notes", path = path, text = uji.fs.read(path) }
  end
  for _, topic in ipairs(Notes.topics()) do
    found[#found + 1] = topic
  end
  return found
end

local function quoted(path)
  if uji.os.platform == "windows" then
    return '"' .. path .. '"'
  end
  return "'" .. (path:gsub("'", "'\\''")) .. "'"
end

local function editor()
  return uji.os.env("UJI_EDITOR") or uji.os.env("VISUAL") or uji.os.env("EDITOR") or "vi"
end

local function edit()
  local chosen = uji.ui.pick({
    title = "Memory",
    items = items(),
    label = function(item)
      return (item.text and "" or "(empty) ") .. item.path
    end,
    preview = function(item)
      return ito.text.lines(item.text or "uji writes it when you pick it")
    end,
  })
  if not chosen then
    return
  end
  if not uji.fs.stat(chosen.path) then
    uji.fs.write(chosen.path, "")
  end
  uji.ui.exec(editor() .. " " .. quoted(chosen.path))
end

local function remember(args)
  local path, warning = Notes.add(args.note, args.topic)
  if not path then
    return "error: " .. warning
  end
  local kept = "Kept it in " .. path .. ". uji puts the index of your notes in the system prompt from the next turn on."
  return warning and (kept .. " " .. warning) or kept
end

function M.setup()
  uji.context.add("memory", Notes.section)
  uji.command.add("memory", {
    desc = "show and edit the notes uji keeps",
    handler = edit,
  })
  uji.tool.add("remember", {
    description = "Keep a note for yourself about this project. uji puts the index of these notes in the system prompt of "
      .. "every turn and you read the note files themselves with `read_file` when one matters. Use it when the person "
      .. "corrects you, or tells you something you would otherwise have to be told again. One note per call, a sentence "
      .. "or two. Do not keep what you can read from the repo, and do not keep anything the instruction files already say.",
    parameters = {
      type = "object",
      properties = {
        note = {
          type = "string",
          description = "The note to keep.",
        },
        topic = {
          type = "string",
          description = "A short file to keep it in, such as `feedback` or `commands`. Reuse one the index already names "
            .. "when the note belongs with it. Defaults to `notes`.",
        },
      },
      required = { "note" },
      additionalProperties = false,
    },
    subject = "memory",
    policy = "allow",
    display = { label = "Remember" },
    run = remember,
  })
end

return M
