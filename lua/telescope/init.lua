local picker = require("telescope.picker")

local M = {}

local function editor()
  return os.getenv("UJI_EDITOR") or os.getenv("VISUAL") or os.getenv("EDITOR")
end

local function open(path)
  local cmd = editor()
  if not cmd or cmd == "" then
    uji.notify("$EDITOR is not set")
    return
  end
  uji.ui.exec({ cmd = { "sh", "-c", cmd .. ' "$1"', "sh", path } })
end

local function attach(path)
  local current = uji.input.get()
  local sep = (current == "" or current:sub(-1) == " ") and "" or " "
  uji.input.set(current .. sep .. "@" .. path .. " ")
end

local FIND = "rg --files --hidden --glob '!.git' 2>/dev/null"
  .. " || find . -type f -not -path '*/.git/*'"

function M.files()
  return uji.async.job({ cmd = FIND })
end

function M.grep(pattern)
  local escaped = pattern:gsub("'", "'\\''")
  return uji.async.job({
    cmd = "rg --line-number --no-heading --smart-case '" .. escaped .. "' | head -500",
  })
end

function M.branches()
  return uji.async.job({ cmd = "git branch --all --format='%(refname:short)'" })
end

function M.setup(opts)
  opts = opts or {}

  uji.command("find", function()
    uji.async.run(function()
      local choice = picker.await("Open file", M.files())
      if choice then open(choice) end
    end)
  end)

  uji.command("attach", function()
    uji.async.run(function()
      local choice = picker.await("Attach file", M.files())
      if choice then attach(choice) end
    end)
  end)

  uji.command("grep", function(args)
    if args == "" then
      uji.notify("usage: /grep <pattern>")
      return
    end
    uji.async.run(function()
      local hits = M.grep(args)
      local choice = picker.await("Grep: " .. args, hits)
      if choice then open(choice:match("^([^:]+):") or choice) end
    end)
  end)

  uji.command("branch", function()
    uji.async.run(function()
      local choice = picker.await("Git branches", M.branches())
      if choice then
        uji.session.submit("Summarise what changed on branch " .. choice)
      end
    end)
  end)

  uji.command("history", function()
    local items = {}
    for _, message in ipairs(uji.session.messages()) do
      if message.type == "user" then
        items[#items + 1] = message.text:gsub("\n", " ")
      end
    end
    uji.async.run(function()
      local choice = picker.await("Session history", items)
      if choice then uji.input.set(choice) end
    end)
  end)

  if opts.keys ~= false then
    uji.keymap.set("normal", "<C-p>", { command = "find" })
    uji.keymap.set("normal", "<C-a>", { command = "attach" })
    uji.keymap.set("normal", "<C-g>", { command = "branch" })
    uji.keymap.set("normal", "<C-r>", { command = "history" })
  end
end

return M
