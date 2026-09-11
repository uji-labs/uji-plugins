local M = {}

local READ_ONLY = {
  read_file = true,
  list_dir = true,
  grep = true,
}

local DENY = "Plan mode is on: no edits or commands yet. "
  .. "Investigate with read_file/list_dir/grep, then reply with a numbered plan. "
  .. "The user will approve it before you touch anything."

local state = { active = false }

local function banner()
  uji.emit("status_changed", {})
end

function M.active()
  return state.active
end

function M.decide(tool)
  if not state.active then
    return nil
  end
  if READ_ONLY[tool] then
    return { allow = true }
  end
  return { deny = DENY }
end

function M.enter()
  state.active = true
  banner()
end

function M.leave()
  state.active = false
  banner()
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

function M.setup(opts)
  opts = opts or {}

  uji.agent.context("plan", function()
    if not state.active then return nil end
    return [[# Plan mode

Plan mode is active. File edits and shell commands are blocked and will be
denied if you attempt them. You can still read: use read_file, list_dir and
grep freely.

Investigate the task, then reply with a short numbered plan naming the files
you would change and what you would change in them. Do not write code yet.
The user will approve the plan before anything runs.]]
  end, { priority = 10 })

  uji.status.add("plan", function()
    if not state.active then return nil end
    return { text = " PLAN ", color = "black", bg = "yellow", bold = true }
  end, { priority = 5 })

  uji.on("tool_call", function(event)
    return M.decide(event.name)
  end, { priority = opts.priority or 10 })

  uji.command("plan", function(args)
    if state.active then
      M.leave()
      uji.notify("plan mode off")
      return
    end
    M.enter()
    if args ~= "" then
      uji.session.submit("Plan only, do not edit anything yet: " .. args)
    else
      uji.notify("plan mode on — describe what you want planned")
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
    M.leave()
    uji.session.submit("Approved. Execute the plan you just described.")
  end)

  if opts.keys ~= false then
    uji.keymap.set("normal", "<C-b>", { command = "plan" })
  end
end

return M
