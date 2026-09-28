local M = {}

local WRITE_TOOLS = { "edit_file", "write_file" }

local state = { active = false, asking = false, left = false, allow = {} }

local READ_ONLY = {
  cat = true,
  cd = true,
  diff = true,
  du = true,
  fd = true,
  file = true,
  find = true,
  grep = true,
  head = true,
  ls = true,
  pwd = true,
  rg = true,
  sort = true,
  stat = true,
  tail = true,
  tree = true,
  ["true"] = true,
  uniq = true,
  wc = true,
  which = true,
}

local READ_ONLY_GIT = {
  blame = true,
  branch = true,
  diff = true,
  grep = true,
  log = true,
  ["ls-files"] = true,
  show = true,
  status = true,
}

local function read_only_step(step)
  local program, sub = step:match("^%s*(%S+)%s*(%S*)")
  if program == "git" then
    return READ_ONLY_GIT[sub] == true
  end
  if program == "sed" then
    return sub == "-n"
  end
  return READ_ONLY[program] == true
end

local function read_only(cmd)
  if type(cmd) ~= "string" then
    return false
  end
  local quiet = cmd:gsub("%d*>%s*/dev/null", ""):gsub("%d*>&%d", "")
  if quiet:find("[>`]") or quiet:find("%$%(") or quiet:find("%-delete") or quiet:find("%-exec") then
    return false
  end
  for step in quiet:gsub("[;&|]+", "\n"):gmatch("[^\n]+") do
    if step:find("%S") and not read_only_step(step) then
      return false
    end
  end
  return true
end

local function nominated(cmd)
  if type(cmd) ~= "string" then
    return false
  end
  for _, prefix in ipairs(state.allow) do
    if cmd == prefix or string.sub(cmd, 1, #prefix + 1) == prefix .. " " then
      return true
    end
  end
  return false
end

local REMINDER = [[Plan mode is on. Do not change anything yet.

edit_file and write_file are unavailable this turn. Investigate with read_file
and read-only commands such as rg, ls, find and git log; those run straight
away. Any other command needs the user's approval, so keep them rare.

When you understand the task, reply with a numbered plan: which files you would
change, and what you would change in each. No code yet. The user approves the
plan before anything runs.]]

local OFF = "Plan mode is off. edit_file and write_file are available again."

local ASK = "Run this while planning?"

local ACCEPT = "Accept and execute"
local KEEP = "Keep planning"
local CANCEL = "Leave plan mode"

function M.active()
  return state.active
end

function M.decide(tool, args)
  if not state.active then
    return nil
  end
  local cmd = args and args.command
  if tool == "run_command" and not read_only(cmd) and not nominated(cmd) then
    return { ask = ASK }
  end
  return nil
end

function M.enter()
  state.active = true
  state.asking = false
  state.left = false
  uji.tool.disable(WRITE_TOOLS)
  uji.emit("status_changed", {})
end

function M.leave()
  state.active = false
  state.asking = false
  state.left = true
  uji.tool.enable(WRITE_TOOLS)
  uji.emit("status_changed", {})
end

local function last_plan()
  local messages = uji.session.messages()
  for i = #messages, 1, -1 do
    if messages[i].type == "assistant" and messages[i].text ~= "" then
      return messages[i].text
    end
  end
  return nil
end

function M.approve()
  M.leave()
  uji.session.submit("Approved. Execute the plan you just described.")
end

local function ask_to_accept()
  if not state.active or state.asking or not last_plan() then
    return
  end
  state.asking = true
  uji.ui.select({
    title = "Plan ready",
    items = { ACCEPT, KEEP, CANCEL },
  }, function(choice)
    state.asking = false
    if choice == ACCEPT then
      M.approve()
    elseif choice == CANCEL then
      M.leave()
      uji.notify("plan mode off")
    end
  end)
end

function M.setup(opts)
  opts = opts or {}
  state.allow = opts.allow or {}

  uji.context.add("plan", function()
    if state.active then return { text = REMINDER, at = "turn" } end
    if not state.left then return nil end
    state.left = false
    return { text = OFF, at = "turn" }
  end, { priority = 10 })

  uji.status.add("plan", function()
    if not state.active then return nil end
    return { text = "plan", color = "yellow" }
  end, { priority = 5 })

  uji.on("before_tool", function(event)
    return M.decide(event.name, event.arguments)
  end, { name = "planmode", priority = opts.priority or 10 })

  uji.on("message_submitted", function()
    state.asking = false
  end, { name = "planmode" })

  if opts.confirm ~= false then
    uji.on("turn_finished", ask_to_accept, { name = "planmode" })
  end

  uji.command.add("plan", function(args)
    if state.active then
      M.leave()
      uji.notify("plan mode off")
      return
    end
    M.enter()
    if args ~= "" then
      uji.session.submit(args)
    else
      uji.notify("plan mode on, describe what you want planned")
    end
  end)

  uji.command.add("approve", function()
    if not state.active then
      uji.notify("not in plan mode")
      return
    end
    if not last_plan() then
      uji.notify("no plan to approve yet")
      return
    end
    M.approve()
  end)

  if opts.keys ~= false then
    uji.keymap.add("normal", "<C-b>", { command = "plan" })
  end
end

return M
