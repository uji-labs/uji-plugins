local M = {}

local function themes(current)
  local names = {}
  for _, module in ipairs(uji.modules("uji.themes")) do
    local name = module:match("[^.]+$")
    if name == current then
      table.insert(names, 1, name)
    else
      names[#names + 1] = name
    end
  end
  return names
end

local function exists(name)
  for _, module in ipairs(uji.modules("uji.themes")) do
    if module == "uji.themes." .. name then
      return true
    end
  end
  return false
end

local function use(name)
  uji.ui.configure({ theme = name })
  uji.ui.save_theme(name)
end

local function preview(name)
  uji.ui.configure({ theme = name })
  return { "enter keeps it, esc goes back" }
end

local function pick()
  local before = uji.ui.theme()
  uji.ui.pick({ title = "Themes", items = themes(before), preview = preview }, function(name)
    if name then
      use(name)
    else
      uji.ui.configure({ theme = before })
    end
  end)
end

function M.setup(opts)
  opts = opts or {}
  uji.command.add("theme", {
    desc = "pick a theme",
    handler = function(args)
      if args == "" then
        pick()
      elseif exists(args) then
        use(args)
      else
        uji.notify("no theme named " .. args)
      end
    end,
  })
  if opts.keys then
    uji.keymap.add("normal", opts.keys, { command = "theme" })
  end
end

return M
