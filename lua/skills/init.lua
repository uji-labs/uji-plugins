local M = {}

local state = { roots = {}, found = {}, commands = {}, pending = nil }

local ESCAPES = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&apos;" }
local FILE = "SKILL.md"
local DEPTHS = { "/" .. FILE, "/*/" .. FILE, "/*/*/" .. FILE }

local function escape(text)
  return (tostring(text):gsub("[&<>\"']", ESCAPES))
end

local function declared(text)
  if not text then return nil end
  local block = text:match("^%-%-%-%s*\n(.-)\n%-%-%-")
  if not block then return nil end
  local name = block:match("name:%s*([^\n]+)")
  local description = block:match("description:%s*([^\n]+)")
  if not name or not description then return nil end
  return (name:gsub("%s+$", "")), (description:gsub("%s+$", ""))
end

local function body(text)
  local stripped = text:gsub("^%-%-%-%s*\n.-\n%-%-%-[^\n]*\n?", "")
  return (stripped:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.discover()
  state.found = {}
  local seen = {}
  for _, root in ipairs(state.roots) do
    for _, depth in ipairs(DEPTHS) do
      for _, path in ipairs(uji.fs.glob(root .. depth) or {}) do
        local name, description = declared(uji.fs.read(path))
        if name and not seen[name] then
          seen[name] = true
          state.found[#state.found + 1] = {
            name = name,
            description = description,
            path = path,
            dir = path:sub(1, -#FILE - 2),
          }
        end
      end
    end
  end
  table.sort(state.found, function(a, b) return a.name < b.name end)
  return state.found
end

function M.list()
  return state.found
end

local function announce()
  if #state.found == 0 then return nil end
  local lines = {
    "The following skills provide specialized instructions for specific tasks.",
    "Use the read_file tool to load a skill's file when the task matches its description.",
    "When a skill file references a relative path, resolve it against the skill directory "
      .. "(the folder holding SKILL.md) and use that absolute path in tool calls.",
    "",
    "<available_skills>",
  }
  for _, skill in ipairs(state.found) do
    lines[#lines + 1] = "  <skill>"
    lines[#lines + 1] = "    <name>" .. escape(skill.name) .. "</name>"
    lines[#lines + 1] = "    <description>" .. escape(skill.description) .. "</description>"
    lines[#lines + 1] = "    <location>" .. escape(skill.path) .. "</location>"
    lines[#lines + 1] = "  </skill>"
  end
  lines[#lines + 1] = "</available_skills>"
  return table.concat(lines, "\n")
end

local function invoked()
  local skill = state.pending
  state.pending = nil
  local text = skill and uji.fs.read(skill.path)
  if not text then return nil end
  return {
    at = "turn",
    text = string.format(
      '<skill name="%s" location="%s">\nReferences are relative to %s.\n\n%s\n</skill>',
      escape(skill.name), escape(skill.path), skill.dir, body(text)
    ),
  }
end

local function register()
  for _, name in ipairs(state.commands) do
    uji.command.remove(name)
  end
  state.commands = {}
  for _, skill in ipairs(state.found) do
    local name = "skill:" .. skill.name
    state.commands[#state.commands + 1] = name
    uji.command.add(name, {
      desc = skill.description,
      handler = function(args)
        state.pending = skill
        uji.session.submit(args ~= "" and args or ("Use the " .. skill.name .. " skill."))
      end,
    })
  end
end

function M.setup(opts)
  opts = opts or {}
  state.roots = opts.roots or {
    "~/.agents/skills",
    ".uji/skills",
    ".agents/skills",
  }
  M.discover()
  register()

  uji.context.add("skills", announce, { priority = 20 })
  uji.context.add("skill", invoked, { priority = 21 })

  uji.command.add("skills", function()
    M.discover()
    register()
    if #state.found == 0 then
      uji.notify("no skills found")
      return
    end
    local items = {}
    for _, skill in ipairs(state.found) do
      items[#items + 1] = skill.name .. " - " .. skill.description
    end
    uji.ui.select({ title = "Skills", items = items }, function() end)
  end)
end

return M
