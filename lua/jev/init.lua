-- Auto mode: Jev, TypeSafe's decision model, answers the approval questions
-- uji would otherwise put to you.
--
-- Only calls the tool policy would *ask* about go to Jev. A before_tool answer
-- replaces the policy outright, so this hook evaluates the policy itself first
-- and stays out of the way when a rule already allows or denies the call: a
-- deny rule for `rm -rf` keeps refusing whatever Jev thinks.
--
-- Jev returns a calibrated probability that the call is safe to run
-- unattended. At the threshold or above the call runs; below it uji asks as
-- usual, with Jev's number in the question. Jev never refuses on its own, so
-- the worst a wrong answer costs is a question. Any failure (no key, a non-2xx,
-- a timeout) leaves the decision to the policy, as if the plugin were absent.
--
--   require("jev").setup({ key_file = "~/.config/typesafe/api_key", threshold = 0.8 })
--
-- The key is `key`, then TYPESAFE_API_KEY (the variable TypeSafe's SDK reads),
-- then the contents of `key_file`.
--
-- tool.compiled() and tool.subject() are uji internals (lua/uji/core/tool.lua):
-- the public API can set a policy but not evaluate one. Agent:verdict in
-- lua/uji/core/agent/init.lua is what this mirrors; recheck it when uji moves,
-- and drop the internals once uji.tool grows a way to evaluate the policy.

local tool = require("uji.core.tool")

local M = {}

local DEFAULTS = {
  url = "https://api.typesafe.ai/v1/systemone",
  model = "jev-latest",
  threshold = 0.8,
  enabled = true,
  timeout = 10,
}

-- Write_file's content and long commands would otherwise blow up the state.
local MAX_ARGUMENTS = 8000
local MAX_REQUEST = 2000

local QUESTION = "Is this tool call safe to run without asking the user first? "
  .. "Answer yes only when it is read-only, or a routine change inside the working directory "
  .. "that is easy to undo and that the user's request calls for, such as editing project files, "
  .. "building or running tests. Answer no when it deletes or overwrites anything outside the "
  .. "working directory, is hard to undo, pushes, deploys or publishes anything, changes system "
  .. "or user configuration, reads or sends secrets or credentials, downloads and runs code, "
  .. "or does something the user did not ask for."

local opts = DEFAULTS
local state = { enabled = true, safe = DEFAULTS.threshold, request = nil, key = nil, warned = false }

local function merged(base, over)
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, v in pairs(over or {}) do out[k] = v end
  return out
end

local function percent(probability)
  return math.floor(probability * 100 + 0.5) .. "%"
end

local function clip(text, limit)
  if #text <= limit then
    return text
  end
  return text:sub(1, limit) .. " [... " .. (#text - limit) .. " more characters]"
end

local function resolved(directory, subject)
  if subject:sub(1, 1) == "/" then
    return subject
  end
  if subject:sub(1, 2) == "~/" then
    return uji.fs.join(os.getenv("HOME") or "~", subject:sub(3))
  end
  return uji.fs.join(directory, subject)
end

local function key()
  if state.key then
    return state.key
  end
  if opts.key and opts.key ~= "" then
    state.key = opts.key
    return state.key
  end
  local env = os.getenv("TYPESAFE_API_KEY")
  if env and env ~= "" then
    state.key = env
    return env
  end
  if not opts.key_file then
    return nil
  end
  -- Read lazily: a secrets manager may write the file after uji has started.
  local file = io.open(resolved(".", opts.key_file), "r")
  if not file then
    return nil
  end
  local text = file:read("*a"):gsub("%s+$", "")
  file:close()
  if text ~= "" then
    state.key = text
  end
  return state.key
end

-- Once per run of failures, so an outage doesn't bury the screen in notices.
local function warn(message)
  if not state.warned then
    state.warned = true
    uji.notify("auto mode: " .. message .. "; asking instead")
  end
end

local function verdict(name, args, directory)
  local entry = tool.described(name)
  local ok, subject = pcall(tool.subject, entry, name, args)
  if not ok then
    return "ask"
  end
  local subjects = { subject }
  if entry and entry.path and type(subject) == "string" then
    subjects[2] = resolved(directory, subject)
  end
  local policy = tool.compiled()
  local evaluated, action = pcall(policy.evaluate, policy, name, subjects, entry and entry.policy)
  return evaluated and action or "ask"
end

local function question(name)
  local entry = tool.described(name)
  return entry and entry.display.question or ("Would you like to run `" .. name .. "`?")
end

local function describe(name, args, directory)
  local parts = {
    "A coding agent working in " .. directory .. " wants to call the tool `" .. name .. "`.",
    "Arguments: " .. clip(uji.json.encode(args), MAX_ARGUMENTS),
  }
  if state.request then
    parts[#parts + 1] = "The user's latest request: " .. clip(state.request, MAX_REQUEST)
  end
  return table.concat(parts, "\n\n")
end

local function classify(api_key, text)
  local done = uji.promise()
  uji.http.request({
    url = opts.url,
    method = "POST",
    headers = {
      Authorization = "Bearer " .. api_key,
      ["Content-Type"] = "application/json",
    },
    body = uji.json.encode({
      model = opts.model,
      state = text,
      questions = { safe = { type = "noul", instructions = QUESTION } },
    }),
    timeout = opts.timeout,
  }, function(response, err)
    done:resolve(response, err)
  end)
  local response, err = done:await()
  if not response then
    return nil, "Jev request failed: " .. tostring(err)
  end
  if response.status ~= 200 then
    return nil, "Jev answered HTTP " .. response.status
  end
  local ok, body = pcall(uji.json.decode, response.body)
  local safe = ok and type(body) == "table" and type(body.answers) == "table" and body.answers.safe
  if type(safe) ~= "table" or type(safe.noul) ~= "number" then
    return nil, "Jev's answer had no probability"
  end
  return safe.noul
end

local function before_tool(call)
  if not state.enabled then
    return nil
  end
  -- Empty until a session starts, as under `uji run`.
  local directory = uji.session.info().directory
  if not directory or directory == "" then
    directory = os.getenv("PWD") or "."
  end
  if verdict(call.name, call.arguments, directory) ~= "ask" then
    return nil
  end
  local api_key = key()
  if not api_key then
    warn("no Jev key; set TYPESAFE_API_KEY or key_file")
    return nil
  end
  local safe, err = classify(api_key, describe(call.name, call.arguments, directory))
  if not safe then
    warn(err)
    return nil
  end
  state.warned = false
  if safe >= state.safe then
    return { allow = true }
  end
  return { ask = string.format("%s (Jev: %s safe, auto needs %s)", question(call.name), percent(safe), percent(state.safe)) }
end

-- "0.8", "80" and "80%" all mean 80%. A bare number up to 1 is a probability,
-- so "1" is 100% (only calls Jev is certain about run unasked).
function M.threshold(text)
  local digits, sign = tostring(text):match("^([%d%.]+)(%%?)$")
  local value = tonumber(digits)
  if not value then
    return nil
  end
  if sign == "%" or value > 1 then
    value = value / 100
  end
  if value > 1 then
    return nil
  end
  return value
end

local function report()
  if state.enabled then
    uji.notify("auto mode on, runs calls Jev rates " .. percent(state.safe) .. " safe or more")
  else
    uji.notify("auto mode off, threshold " .. percent(state.safe))
  end
end

local function command(args)
  local arg = (args or ""):match("^%s*(.-)%s*$")
  if arg == "" then
    state.enabled = not state.enabled
  elseif arg == "on" or arg == "off" then
    state.enabled = arg == "on"
  elseif arg ~= "status" then
    local value = M.threshold(arg)
    if not value then
      uji.notify("auto: expected on, off, status or a threshold such as 0.8 or 80%")
      return
    end
    state.safe = value
  end
  report()
end

function M.setup(options)
  opts = merged(DEFAULTS, options)
  local safe = M.threshold(opts.threshold)
  if not safe then
    error("jev: threshold must be a probability (0..1) or a percentage, not " .. tostring(opts.threshold))
  end
  state = { enabled = opts.enabled ~= false, safe = safe, request = nil, key = nil, warned = false }

  uji.on("message_submitted", function(message)
    state.request = message.text
  end, { name = "jev-request" })
  uji.on("before_tool", before_tool, { name = "jev-auto" })

  uji.command.add("auto", {
    desc = "auto mode: Jev approves routine tool calls. /auto [on|off|status|<threshold>]",
    handler = command,
  })
end

return M
