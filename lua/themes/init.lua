local M = {}

local function names()
  local found = {}
  for index, module in ipairs(uji.modules("uji.themes")) do
    found[index] = module:match("[^.]+$")
  end
  return found
end

local function exists(wanted)
  for _, name in ipairs(names()) do
    if name == wanted then
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
  uji.ui.pick({ title = "Themes", items = names(), current = before, preview = preview }, function(name)
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
