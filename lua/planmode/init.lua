local M = {}

local WRITE_TOOLS = { "edit_file", "write_file" }

local state = { active = false, asking = false, allow = {} }

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

edit_file and write_file are unavailable this turn. Investigate with read_file,
list_dir and grep. You can run commands, but the user approves each one, so
keep them few.

When you understand the task, reply with a numbered plan: which files you would
change, and what you would change in each. No code yet. The user approves the
plan before anything runs.]]

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
  if tool == "run_command" and not nominated(args and args.command) then
    return { ask = ASK }
  end
  return nil
end

function M.enter()
  state.active = true
  state.asking = false
  uji.tool.disable(WRITE_TOOLS)
  uji.emit("status_changed", {})
end

function M.leave()
  state.active = false
  state.asking = false
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

  uji.agent.context("plan", function()
    if not state.active then return nil end
    return { text = REMINDER, at = "turn" }
  end, { priority = 10 })

  uji.status.add("plan", function()
    if not state.active then return nil end
    return { text = "plan", color = "yellow" }
  end, { priority = 5 })

  uji.on("tool_call", function(event)
    return M.decide(event.name, event.arguments)
  end, { priority = opts.priority or 10 })

  uji.on("message_submitted", function()
    state.asking = false
  end)

  if opts.confirm ~= false then
    uji.on("turn_finished", ask_to_accept)
  end

  uji.command("plan", function(args)
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

  uji.command("approve", function()
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
    uji.keymap.set("normal", "<C-b>", { command = "plan" })
  end
end

return M
