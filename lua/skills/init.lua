local M = {}

local state = { roots = {}, found = {} }

local function home(path)
  return (path:gsub("^~", os.getenv("HOME") or "~"))
end

local function slurp(path)
  local handle = io.open(path, "r")
  if not handle then return nil end
  local text = handle:read("*a")
  handle:close()
  return text
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

function M.discover()
  state.found = {}
  local seen = {}
  for _, root in ipairs(state.roots) do
    local dir = home(root)
    local handle = io.popen(string.format("find %q -maxdepth 3 -name SKILL.md 2>/dev/null", dir))
    if handle then
      for path in handle:lines() do
        local name, description = declared(slurp(path))
        if name and not seen[name] then
          seen[name] = true
          state.found[#state.found + 1] = {
            name = name,
            description = description,
            path = path,
            dir = path:gsub("/SKILL%.md$", ""),
          }
        end
      end
      handle:close()
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
  local lines = { "# Skills", "",
    "Capabilities available as scripts. Read SKILL.md in the folder for how to",
    "use one, then run its scripts with run_command using the full path.", "" }
  for _, skill in ipairs(state.found) do
    lines[#lines + 1] = string.format("- %s: %s\n  %s", skill.name, skill.description, skill.dir)
  end
  return table.concat(lines, "\n")
end

function M.setup(opts)
  opts = opts or {}
  state.roots = opts.roots or {
    "~/.agents/skills",
    ".uji/skills",
    ".agents/skills",
  }
  M.discover()

  uji.agent.context("skills", announce, { priority = 20 })

  uji.command("skills", function()
    M.discover()
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
