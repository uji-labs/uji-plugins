-- Auto mode: a decision model answers the approval questions uji would
-- otherwise put to you.
--
-- Only calls the tool policy would *ask* about are asked about. A before_tool
-- answer replaces the policy outright, so this hook evaluates the policy itself
-- first and stays out of the way when a rule already allows or denies the call:
-- a deny rule for `rm -rf` keeps refusing whatever the judge thinks.
--
-- uji.model.decide gives a probability that the call is safe to run unattended.
-- At the threshold or above the call runs; below it uji asks as usual, with the
-- number in the question. The judge never refuses on its own, so the worst a
-- wrong answer costs is a question. Any failure (no key, a non-2xx, a timeout)
-- leaves the decision to the policy, as if the plugin were absent.
--
-- `backend` names the judge: "jev" (the default) is TypeSafe's Jev, a decision
-- model whose numbers are calibrated; "session" is the model uji is already
-- talking to, asked over chat, whose number is its own estimate.
--
-- A shell command the judge won't run, from uji's run_command or Claude Code's
-- Bash, comes to you broken down: shfmt puts each statement and each && || |
-- step on its own line, every line is scored in one more request, and the
-- question shows each line's score. In a terminal whose COLORTERM says it has
-- 24-bit colour the score's colour runs from red at 0% through yellow to green
-- at 100%; elsewhere it is green at the threshold or above, yellow from 50% up
-- to it, red below 50%. Without shfmt the command keeps the lines it was
-- written with.
--
--   require("automode-jev").setup({ threshold = 0.8, backend = "session" })
--
-- The key is uji's to hold: TYPESAFE_API_KEY, or the one /login saved for the
-- jev provider.
--
-- tool.compiled() and tool.subject() are uji internals (lua/uji/core/tool.lua):
-- the public API can set a policy but not evaluate one. Agent:verdict in
-- lua/uji/core/agent/init.lua is what this mirrors; recheck it when uji moves,
-- and drop the internals once uji.tool grows a way to evaluate the policy.

local ito = require("ito")
local tool = require("uji.core.tool")

local M = {}

local DEFAULTS = {
  backend = "jev",
  threshold = 0.8,
  enabled = true,
  timeout = 10,
  shfmt = "shfmt",
}

-- Write_file's content and long commands would otherwise blow up the state.
local MAX_ARGUMENTS = 8000
local MAX_REQUEST = 2000

-- The breakdown: one question per line, so a long script costs a long wait,
-- and that request gets at least LINES_TIMEOUT seconds. Lines past MAX_LINES
-- show unscored. SHELLS are the tools that run one: uji's own, and Claude
-- Code's through the claude_code plugin.
local SHELLS = { run_command = true, Bash = true }
local MAX_LINES = 40
local LINES_TIMEOUT = 30
-- Breakdowns whose question never showed, as under `uji run`, are dropped
-- past this many.
local MAX_PENDING = 8

local CRITERIA = "Answer yes only when it is read-only, or a routine change inside the working directory "
  .. "that is easy to undo and that the user's request calls for, such as editing project files, "
  .. "building or running tests. Answer no when it deletes or overwrites anything outside the "
  .. "working directory, is hard to undo, pushes, deploys or publishes anything, changes system "
  .. "or user configuration, reads or sends secrets or credentials, downloads and runs code, "
  .. "or does something the user did not ask for."

local QUESTION = "Is this tool call safe to run without asking the user first? " .. CRITERIA
local LINE_QUESTION = "Is line %d of the command safe to run without asking the user first? "
  .. "Judge that line by itself and read the other lines only for context. "
  .. CRITERIA

local SHADES = {
  safe = ito.TextStyle({ foreground = ito.Color.green, bold = true }),
  unsure = ito.TextStyle({ foreground = ito.Color.yellow, bold = true }),
  unsafe = ito.TextStyle({ foreground = ito.Color.red, bold = true }),
}

-- Nothing in uji probes the terminal, so this goes by what it says of itself.
local TRUECOLOR = os.getenv("COLORTERM") == "truecolor" or os.getenv("COLORTERM") == "24bit"
-- The gradient's channels, high and low, soft enough to read on a dark
-- background: red is (HIGH, LOW, LOW), yellow (HIGH, HIGH, LOW), green
-- (LOW, HIGH, LOW).
local HIGH, LOW = 0xf2, 0x49

-- Lines that only open or close a block do nothing on their own.
local BARE = {
  ["then"] = true,
  ["do"] = true,
  ["done"] = true,
  ["else"] = true,
  ["fi"] = true,
  ["esac"] = true,
  [";;"] = true,
  ["{"] = true,
  ["}"] = true,
  ["("] = true,
  [")"] = true,
}

local opts = DEFAULTS
local state = { enabled = true, safe = DEFAULTS.threshold, request = nil, warned = false, pending = {} }

local function merged(base, over)
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, v in pairs(over or {}) do out[k] = v end
  return out
end

local function percent(probability)
  return math.floor(probability * 100 + 0.5) .. "%"
end

-- Red to yellow over the first half, yellow to green over the second.
local function hued(probability)
  local p = math.max(0, math.min(1, probability))
  local red = p <= 0.5 and HIGH or math.floor(HIGH - (HIGH - LOW) * (p - 0.5) * 2 + 0.5)
  local green = p >= 0.5 and HIGH or math.floor(LOW + (HIGH - LOW) * p * 2 + 0.5)
  return ito.TextStyle({ foreground = ito.rgb(red * 0x10000 + green * 0x100 + LOW), bold = true })
end

local function shade(probability)
  if TRUECOLOR then
    return hued(probability)
  elseif probability >= state.safe then
    return SHADES.safe
  elseif probability >= 0.5 then
    return SHADES.unsure
  end
  return SHADES.unsafe
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

-- Ends the state with the user's request, which is what the judge weighs the
-- call against. uji joins the parts as paragraphs.
local function framed(parts)
  if state.request then
    parts[#parts + 1] = "The user's latest request: " .. clip(state.request, MAX_REQUEST)
  end
  return parts
end

local function describe(name, args, directory)
  return framed({
    "A coding agent working in " .. directory .. " wants to call the tool `" .. name .. "`.",
    "Arguments: " .. clip(uji.json.encode(args), MAX_ARGUMENTS),
  })
end

-- Who answers: "session" is the model uji is talking to, anything else names a
-- provider uji knows, such as the jev provider.
local function decider()
  if opts.backend == "session" then
    return nil
  end
  return opts.backend
end

-- What to call whoever answers, in uji's own name for it.
local function judge_name()
  local id = decider()
  if not id then
    return "the model in use"
  end
  local provider = uji.provider.get(id)
  return provider and provider.name or id
end

-- Asks every question about one state and gives the probabilities by question
-- id, and who answered. uji leaves out a probability that is not one, so a
-- question without one is asked instead.
local function asked(text, questions, timeout)
  local found, failure = uji.model.decide({
    provider = decider(),
    model = opts.model,
    state = text,
    questions = questions,
    timeout = timeout,
  })
  if not found then
    return nil, failure and failure.message or "the decision failed"
  end
  return found
end

-- The label the question puts on the number: a judge whose numbers are
-- calibrated, or the model in use and its own estimate.
local function judge(found)
  if found.calibrated then
    return judge_name()
  end
  return "the model in use"
end

local function classify(text)
  local found, err = asked(text, { safe = QUESTION }, opts.timeout)
  if not found then
    return nil, err
  end
  if not found.probabilities.safe then
    return nil, "the answer had no probability"
  end
  return found.probabilities.safe, found
end

-- Runs argv with input on stdin and gives the lines it prints, or nil when it
-- fails, as it does when the program isn't there.
local function run(argv, input)
  local done = uji.promise()
  local lines = {}
  local job = uji.job.start({
    cmd = argv,
    timeout = opts.timeout,
    on_stdout = function(line)
      lines[#lines + 1] = line
    end,
    on_exit = function(code)
      done:resolve(code == 0)
    end,
  })
  job.send(input)
  job.close()
  if not done:await() then
    return nil
  end
  return lines
end

-- shfmt keeps `a && b | c; d` on one line, so break it first at the offsets
-- shfmt's own parser reports: a statement's ; becomes a newline, and each
-- && || | gets one after it. Command substitutions stay whole on their line.
local function broken(command)
  local tree = run({ opts.shfmt, "--to-json" }, command)
  local ok, ast = pcall(uji.json.decode, tree and table.concat(tree, "\n") or "")
  if not ok or type(ast) ~= "table" then
    return command
  end
  local cuts = {}
  local function walk(node)
    if type(node) ~= "table" or node.Type == "CmdSubst" or node.Type == "ProcSubst" then
      return
    end
    if node.Type == "BinaryCmd" and type(node.Y) == "table" and type(node.Y.Pos) == "table" then
      cuts[#cuts + 1] = { at = node.Y.Pos.Offset, width = 0 }
    end
    -- Semicolon is also where a background statement's & sits.
    if type(node.Semicolon) == "table" and not node.Background and not node.Coprocess then
      cuts[#cuts + 1] = { at = node.Semicolon.Offset, width = 1 }
    end
    for _, child in pairs(node) do
      walk(child)
    end
  end
  walk(ast)
  -- From the end, so the offsets still ahead stay right.
  table.sort(cuts, function(a, b)
    return a.at > b.at
  end)
  for _, cut in ipairs(cuts) do
    local at = cut.at + 1
    if cut.width == 0 or (command:sub(at, at) == ";" and not command:sub(at + 1, at + 1):match("[;&]")) then
      command = command:sub(1, at - 1) .. "\n" .. command:sub(at + cut.width)
    end
  end
  return command
end

-- The command as shfmt lays it out, one step a line with -bn putting the
-- operator first, or its own lines when shfmt can't parse it or isn't there.
local function formatted(command)
  local style = { opts.shfmt, "-bn", "-i", "2" }
  local lines = run(style, broken(command)) or run(style, command)
  while lines and #lines > 0 and lines[#lines] == "" do
    lines[#lines] = nil
  end
  if lines and #lines > 0 then
    return lines
  end
  lines = {}
  for line in (command .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  return lines
end

local function scored(line)
  local bare = (line:gsub("%s*\\$", "")):match("^%s*(.-)%s*$")
  return bare ~= "" and not BARE[bare] and bare:sub(1, 1) ~= "#"
end

-- Scores each line in one more request, keyed by its number as a string.
local function judged(lines, directory)
  local listing, questions, count = {}, {}, 0
  for index, line in ipairs(lines) do
    listing[index] = index .. ": " .. line
    if count < MAX_LINES and scored(line) then
      count = count + 1
      questions[tostring(index)] = string.format(LINE_QUESTION, index)
    end
  end
  if count == 0 then
    return {}
  end
  local text = framed({
    "A coding agent working in "
      .. directory
      .. " wants to run this shell command, formatted with one step on each numbered line:",
    clip(table.concat(listing, "\n"), MAX_ARGUMENTS),
  })
  local found, err = asked(text, questions, math.max(opts.timeout, LINES_TIMEOUT))
  if not found then
    return nil, err
  end
  return found.probabilities
end

-- The approval body with the command in it swapped for its lines, each after
-- its score. uji's body is the tool's subject, which for both SHELLS is the
-- command alone; for a tool without one it lists the arguments as `key: value`
-- lines, and the command's label goes too.
local function painted(body, entry)
  local from, to = body:find(entry.command, 1, true)
  local before = body:sub(1, from - 1):gsub("command: $", "")
  local spans = {}
  if before ~= "" then
    spans[1] = { before }
  end
  for index, line in ipairs(entry.lines) do
    local score = entry.scores[tostring(index)]
    spans[#spans + 1] = score and { string.format("%4s ", percent(score)), shade(score) } or { "     " }
    spans[#spans + 1] = { " " .. line .. (index < #entry.lines and "\n" or "") }
  end
  if to < #body then
    spans[#spans + 1] = { body:sub(to + 1) }
  end
  return spans
end

-- A command that stays one line keeps the score it already got. When the line
-- scores fail, the lines still show, unscored.
local function explain(title, command, directory, safe)
  local lines = formatted(command)
  local scores = { ["1"] = safe }
  if #lines > 1 then
    local err
    scores, err = judged(lines, directory)
    if not scores then
      warn(err)
      scores = {}
    end
  end
  if #state.pending >= MAX_PENDING then
    table.remove(state.pending, 1)
  end
  state.pending[#state.pending + 1] = { title = title, command = command, lines = lines, scores = scores }
end

-- uji asks its approval questions through uji.ui.confirm, the command in the
-- body. A question from before_tool with a breakdown waiting gets the
-- breakdown in the command's place.
local confirm

local function confirming(request, ...)
  if type(request) == "table" and type(request.body) == "string" then
    for index, entry in ipairs(state.pending) do
      if request.title == entry.title and request.body:find(entry.command, 1, true) then
        table.remove(state.pending, index)
        request.body = painted(request.body, entry)
        break
      end
    end
  end
  return confirm(request, ...)
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
  local safe, found = classify(describe(call.name, call.arguments, directory))
  if not safe then
    warn(found)
    return nil
  end
  state.warned = false
  if safe >= state.safe then
    return { allow = true }
  end
  local title = string.format(
    "%s (%s: %s safe, auto needs %s)",
    question(call.name),
    judge(found),
    percent(safe),
    percent(state.safe)
  )
  if SHELLS[call.name] and type(call.arguments.command) == "string" then
    explain(title, call.arguments.command, directory, safe)
  end
  return { ask = title }
end

-- "0.8", "80" and "80%" all mean 80%. A bare number up to 1 is a probability,
-- so "1" is 100% (only calls the judge is certain about run unasked).
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
    uji.notify("auto mode on, runs calls rated " .. percent(state.safe) .. " safe or more by " .. judge_name())
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
    error("automode-jev: threshold must be a probability (0..1) or a percentage, not " .. tostring(opts.threshold))
  end
  state = { enabled = opts.enabled ~= false, safe = safe, request = nil, warned = false, pending = {} }

  -- Once, so a second setup doesn't wrap the wrapper.
  if not confirm then
    confirm = uji.ui.confirm
    uji.ui.confirm = confirming
  end

  uji.on("message_submitted", function(message)
    state.request = message.text
  end, { name = "automode-jev-request" })
  uji.on("before_tool", before_tool, { name = "automode-jev" })

  uji.command.add("auto", {
    desc = "auto mode: the judge approves routine tool calls. /auto [on|off|status|<threshold>]",
    handler = command,
  })
end

return M
