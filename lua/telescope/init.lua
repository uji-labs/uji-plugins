local M = {}

local function collect(cmd, on_done)
  local lines = {}
  uji.job.start({
    cmd = cmd,
    on_stdout = function(line) lines[#lines + 1] = line end,
    on_exit = function() on_done(lines) end,
  })
end

local picker = require("telescope.picker")

local function pick(title, items, empty, on_choice)
  if #items == 0 then
    uji.notify(empty)
    return
  end
  picker.open(title, items, on_choice)
end

local function attach(path)
  local current = uji.input.get()
  local sep = (current == "" or current:sub(-1) == " ") and "" or " "
  uji.input.set(current .. sep .. "@" .. path .. " ")
end

function M.setup(opts)
  opts = opts or {}

  uji.command("find", function()
    collect("rg --files --hidden --glob '!.git' 2>/dev/null || find . -type f -not -path '*/.git/*'", function(files)
      pick("Find files", files, "no files found", attach)
    end)
  end)

  uji.command("grep", function(args)
    if args == "" then
      uji.notify("usage: /grep <pattern>")
      return
    end
    local escaped = args:gsub("'", "'\\''")
    collect("rg --line-number --no-heading --smart-case '" .. escaped .. "' | head -500", function(hits)
      pick("Grep: " .. args, hits, "no matches", function(hit)
        attach(hit:match("^([^:]+):") or hit)
      end)
    end)
  end)

  uji.command("branch", function()
    collect("git branch --all --format='%(refname:short)'", function(branches)
      pick("Git branches", branches, "not a git repo", function(branch)
        uji.session.submit("Summarise what changed on branch " .. branch)
      end)
    end)
  end)

  uji.command("history", function()
    local items = {}
    for _, m in ipairs(uji.session.messages()) do
      if m.type == "user" then items[#items + 1] = m.text:gsub("\n", " ") end
    end
    pick("Session history", items, "no messages yet", function(text)
      uji.input.set(text)
    end)
  end)

  if opts.keys ~= false then
    uji.keymap.set("normal", "<C-p>", { command = "find" })
    uji.keymap.set("normal", "<C-g>", { command = "branch" })
    uji.keymap.set("normal", "<C-r>", { command = "history" })
  end
end

return M
