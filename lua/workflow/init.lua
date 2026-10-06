-- Workflows: a short Lua script that orchestrates agents. agent() starts one
-- with the subagent plugin and waits for its answer, parallel() and pipeline()
-- run many at once, phase() names the stage the next agents belong to. The
-- running tool shows every agent as a row, and /workflows inspects runs.
--
--   require("subagent").setup({})
--   require("workflow").setup({})

local subagent = require("subagent")

local M = {}

local DEFAULTS = {
  policy = "ask",
  scope = "user",
  concurrency = 4,
  max_agents = 25,
  output = 50 * 1024,
}

local HISTORY = 20
local PREVIEW = 400
local META = "^%s*meta%s*=%s*(%b{})"

local state = { opts = DEFAULTS, runs = {}, order = {}, counter = 0 }

local function merged(base, over)
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, v in pairs(over or {}) do out[k] = v end
  return out
end

local function first_line(text)
  return (tostring(text):match("^%s*([^\n]*)"))
end

local function clipped(text, limit)
  if #text <= limit then return text end
  return text:sub(1, limit) .. "\n[cut at " .. limit .. " of " .. #text .. " bytes]"
end

local function strip_comments(script)
  local out = script
  while true do
    local rest = out:match("^%s*%-%-%[(=*)%[")
    if rest then
      local close = out:find("]" .. rest .. "]", 1, true)
      if not close then return out end
      out = out:sub(close + #rest + 2)
    else
      local line = out:match("^%s*%-%-[^\n]*\n?()")
      if not line then return out end
      out = out:sub(line)
    end
  end
end

local function without_strings(text)
  local out, at = {}, 1
  while at <= #text do
    local char = text:sub(at, at)
    local level = text:match("^%[(=*)%[", at)
    if level then
      local close = text:find("]" .. level .. "]", at, true)
      at = close and close + #level + 2 or #text + 1
    elseif char == '"' or char == "'" then
      at = at + 1
      while at <= #text and text:sub(at, at) ~= char do
        at = at + (text:sub(at, at) == "\\" and 2 or 1)
      end
      at = at + 1
    else
      out[#out + 1] = char
      at = at + 1
    end
  end
  return table.concat(out)
end

-- Reads the `meta = { ... }` table a script starts with, without running it.
function M.meta(script)
  local literal = strip_comments(script):match(META)
  if not literal then
    return nil, "a workflow starts with `meta = { name = ..., description = ..., phases = { ... } }`"
  end
  if without_strings(literal):find("%f[%w_]function%f[^%w_]") then
    return nil, "meta must be a plain table with no functions"
  end
  local chunk, err = load("return " .. literal, "=meta", "t", {})
  if not chunk then return nil, "meta: " .. err end
  local ok, meta = pcall(chunk)
  if not ok or type(meta) ~= "table" then
    return nil, "meta must be a plain table with no function calls"
  end
  if type(meta.name) ~= "string" or meta.name == "" then
    return nil, "meta.name must be a non-empty string"
  end
  return meta
end

local function saved(scope)
  local found = {}
  for _, file in ipairs(uji.config.files("workflows", { project = scope ~= "user" })) do
    local name = file.name:match("^(.+)%.lua$")
    if name and (file.project or scope ~= "project") then
      local meta = M.meta(file.text)
      found[name] = { name = name, script = file.text, meta = meta, project = file.project, path = file.path }
    end
  end
  return found
end

M.saved = saved

local function sorted_names(map)
  local names = {}
  for name in pairs(map) do names[#names + 1] = name end
  table.sort(names)
  return names
end

-- A counting semaphore, so at most `size` agents run at once.
local function semaphore(size)
  local free, waiting = size, {}
  return {
    take = function()
      if free > 0 then
        free = free - 1
        return
      end
      local turn = uji.promise()
      waiting[#waiting + 1] = turn
      turn:await()
    end,
    give = function()
      local turn = table.remove(waiting, 1)
      if turn then turn:resolve() else free = free + 1 end
    end,
  }
end

local function encoded(value)
  if type(value) == "string" then return value end
  if value == nil then return "(no result)" end
  local ok, text = pcall(uji.json.encode, value)
  return ok and text or tostring(value)
end

local function new_id()
  state.counter = state.counter + 1
  return string.format("wf_%x%03d", os.time() % 0xfffff, state.counter)
end

local function keep(run)
  state.runs[run.id] = run
  table.insert(state.order, 1, run.id)
  local dropped = table.remove(state.order, HISTORY + 1)
  if dropped then state.runs[dropped] = nil end
end

local function line(run)
  local phase = run.phase and (" · " .. run.phase) or ""
  if run.phase and run.meta.phases then
    for index, name in ipairs(run.meta.phases) do
      if name == run.phase then
        phase = string.format(" · %s (%d/%d)", name, index, #run.meta.phases)
      end
    end
  end
  return string.format("%s%s · %d agents · %s", run.meta.name, phase, #run.agents, subagent.tokens(run.tokens))
end

local function report(run)
  local lines = { string.format("workflow %s (%s) %s", run.id, run.meta.name, run.status) }
  for _, entry in ipairs(run.agents) do
    lines[#lines + 1] = string.format("- %s: %s%s", entry.label, entry.status, entry.cached and " (cached)" or "")
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "result:"
  lines[#lines + 1] = clipped(run.result or run.error or "", state.opts.output)
  return table.concat(lines, "\n")
end

-- The functions a script sees. Everything else in its environment is plain
-- Lua with no files, processes or modules.
local function environment(run, ctx, stops)
  local gate = semaphore(state.opts.concurrency)
  local agents = subagent.agents(state.opts.scope)

  local function agent(prompt, opts)
    if type(prompt) ~= "string" or prompt == "" then
      error("agent() needs a prompt", 2)
    end
    opts = opts or {}
    if not run.live then
      error("the workflow was stopped", 0)
    end
    local key = uji.json.encode({ prompt, opts.agent, opts.model, opts.tools, opts.cwd })
    local label = opts.label or first_line(prompt)
    local group = opts.phase or run.phase
    local entry = { label = label, phase = group, status = "queued" }
    if run.memo[key] then
      entry.status, entry.cached, entry.answer = "done", true, run.memo[key]
      run.agents[#run.agents + 1] = entry
      subagent.row(ctx, label, { group = group, status = "done", detail = "cached" })
      return run.memo[key]
    end
    if #run.agents >= state.opts.max_agents then
      error("this workflow reached its limit of " .. state.opts.max_agents .. " agents", 2)
    end
    local definition = subagent.GENERAL
    if opts.agent then
      definition = agents[opts.agent]
      if not definition then error("there is no agent `" .. tostring(opts.agent) .. "`", 2) end
    end
    if opts.model or opts.tools or opts.effort then
      definition = merged(definition, { model = opts.model, effort = opts.effort, tools = opts.tools })
    end
    run.agents[#run.agents + 1] = entry
    local row = subagent.row(ctx, label, { group = group, status = "queued" })
    gate.take()
    if not run.live then
      gate.give()
      row:fail("stopped")
      error("the workflow was stopped", 0)
    end
    entry.status = "running"
    local ok, text, info = pcall(subagent.run, definition, prompt, { cwd = opts.cwd, row = row, stops = stops })
    gate.give()
    if not ok then
      entry.status = "failed"
      row:fail(first_line(text))
      return nil, tostring(text)
    end
    run.tokens = run.tokens + info.tokens
    entry.session, entry.tokens, entry.seconds = info.session, info.tokens, info.seconds
    ctx.progress(line(run))
    if info.failed then
      entry.status, entry.answer = "failed", text
      return nil, text:sub(8)
    end
    entry.status, entry.answer = "done", text
    run.memo[key] = text
    return text
  end

  local function wait_all(jobs)
    local results, errors, waits = {}, {}, {}
    for index, job in ipairs(jobs) do
      local done = uji.promise()
      waits[index] = done
      local worker = uji.task.spawn(function()
        local ok, value = pcall(job)
        if ok then results[index] = value else errors[index] = value end
        done:resolve()
      end)
      stops[#stops + 1] = function() worker:cancel() end
    end
    for _, done in ipairs(waits) do done:await() end
    return results, errors
  end

  local function parallel(fns)
    if type(fns) ~= "table" then error("parallel() needs a list of functions", 2) end
    local results, errors = wait_all(fns)
    return results, next(errors) and errors or nil
  end

  local function pipeline(items, ...)
    if type(items) ~= "table" then error("pipeline() needs a list of items", 2) end
    local stages = { ... }
    local jobs = {}
    for index, item in ipairs(items) do
      jobs[index] = function()
        local value = item
        for _, stage in ipairs(stages) do
          if value == nil then return nil end
          value = stage(value, index)
        end
        return value
      end
    end
    local results, errors = wait_all(jobs)
    return results, next(errors) and errors or nil
  end

  local function phase(name)
    run.phase = tostring(name)
    ctx.progress(line(run))
  end

  local function log(...)
    local parts = {}
    for index = 1, select("#", ...) do parts[index] = tostring((select(index, ...))) end
    run.log[#run.log + 1] = table.concat(parts, " ")
    ctx.progress(line(run) .. " · " .. first_line(run.log[#run.log]))
  end

  return {
    agent = agent, parallel = parallel, pipeline = pipeline, phase = phase, log = log,
    args = run.args, meta = run.meta,
    json = { encode = uji.json.encode, decode = uji.json.decode },
    string = string, table = table, math = math,
    pairs = pairs, ipairs = ipairs, next = next, select = select, type = type,
    tostring = tostring, tonumber = tonumber, error = error, assert = assert, pcall = pcall,
    unpack = table.unpack or unpack, print = log,
  }
end

local function source(args)
  if type(args.script) == "string" and args.script:find("%S") then
    return args.script
  end
  if type(args.name) == "string" then
    local found = saved(state.opts.scope)[args.name]
    if not found then
      local names = sorted_names(saved(state.opts.scope))
      return nil, "there is no saved workflow `" .. args.name .. "`. The saved ones are: "
        .. (#names > 0 and table.concat(names, ", ") or "none")
    end
    return found.script
  end
  return nil, "give `script`, or `name` for a saved workflow"
end

local function start(args, ctx, stops, holder)
  local script, missing = source(args)
  if not script then return "error: " .. missing end
  local meta, problem = M.meta(script)
  if not meta then return "error: " .. problem end
  local previous = args.resume and state.runs[args.resume]
  if args.resume and not previous then
    return "error: there is no run `" .. tostring(args.resume) .. "` to resume in this uji"
  end
  local run = {
    id = new_id(), meta = meta, script = script, args = args.args, status = "running", live = true,
    agents = {}, log = {}, tokens = 0, started = uji.os.clock(),
    memo = previous and merged(previous.memo, {}) or {},
  }
  run.stop = function()
    run.live = false
    for _, stop in ipairs(stops) do pcall(stop) end
  end
  keep(run)
  holder.run = run
  ctx.progress(line(run))
  local chunk, err = load(script, "=" .. meta.name, "t", environment(run, ctx, stops))
  if not chunk then
    run.status, run.error = "failed", err
    return "error: the script does not compile: " .. err
  end
  local ok, value = pcall(chunk)
  run.seconds = math.floor(uji.os.clock() - run.started)
  run.live = false
  if not ok then
    run.status, run.error = "failed", tostring(value)
    return "error: " .. report(run)
  end
  run.status, run.result = "completed", encoded(value)
  return report(run)
end

-- The runs of this uji, newest first. Each has `id`, `meta`, `status`
-- (running, completed, failed or stopped), `agents`, `tokens`, `phase`,
-- `log`, and `result` or `error` once it ends.
function M.runs()
  local out = {}
  for index, id in ipairs(state.order) do out[index] = state.runs[id] end
  return out
end

-- /workflows -------------------------------------------------------------

local function elapsed(run)
  local seconds = run.seconds or math.floor(uji.os.clock() - run.started)
  return seconds < 60 and (seconds .. "s") or string.format("%dm%02ds", math.floor(seconds / 60), seconds % 60)
end

local function summary(run)
  return string.format("%s  %s · %s · %d agents · %s · %s", run.id, run.meta.name, run.status, #run.agents,
    subagent.tokens(run.tokens), elapsed(run))
end

function M.details(run)
  local out = {
    "# " .. run.meta.name,
    "",
    (run.meta.description or ""),
    "",
    string.format("**%s** · %d agents · %s · %s", run.status, #run.agents, subagent.tokens(run.tokens), elapsed(run)),
    "",
  }
  local phase
  for _, entry in ipairs(run.agents) do
    if entry.phase ~= phase then
      phase = entry.phase
      if out[#out] ~= "" then out[#out + 1] = "" end
      out[#out + 1] = "## " .. (phase or "Agents")
      out[#out + 1] = ""
    end
    local facts = { entry.status }
    if entry.cached then facts[#facts + 1] = "cached" end
    if entry.seconds then facts[#facts + 1] = entry.seconds .. "s" end
    if entry.tokens and entry.tokens > 0 then facts[#facts + 1] = subagent.tokens(entry.tokens) end
    out[#out + 1] = string.format("- **%s** · %s", entry.label, table.concat(facts, " · "))
    if entry.answer then
      out[#out + 1] = "  > " .. clipped(entry.answer, PREVIEW):gsub("\n", "\n  > ")
    end
  end
  if #run.log > 0 then
    out[#out + 1] = ""
    out[#out + 1] = "## Log"
    out[#out + 1] = ""
    for _, entry in ipairs(run.log) do out[#out + 1] = "- " .. entry end
  end
  if run.result or run.error then
    out[#out + 1] = ""
    out[#out + 1] = run.error and "## Error" or "## Result"
    out[#out + 1] = ""
    out[#out + 1] = "```"
    out[#out + 1] = clipped(run.result or run.error, PREVIEW * 4)
    out[#out + 1] = "```"
  end
  return table.concat(out, "\n")
end

local function show(run)
  local ito = require("ito")
  uji.ui.overlay(function()
    return ito.ScrollView(uji.ui.Markdown(M.details(run))):padding({ horizontal = 1 })
      :border(ito.theme().borders.rounded):title(run.id .. " · scroll for more")
  end)
end

local function sessions(run)
  local items, chosen = {}, {}
  for _, entry in ipairs(run.agents) do
    if entry.session then
      local item = entry.label .. " · " .. entry.status
      items[#items + 1] = item
      chosen[item] = entry.session
    end
  end
  if #items == 0 then
    uji.notify("no agent of " .. run.id .. " left a session")
    return
  end
  local choice = uji.ui.select({ title = "Open an agent's session", items = items })
  if choice then subagent.open(chosen[choice]) end
end

local function inspect(run)
  local actions = { "Show details", "Open an agent's session", "Copy the script into the input" }
  if run.status == "running" then table.insert(actions, 1, "Stop") end
  local choice = uji.ui.select({ title = summary(run), items = actions })
  if choice == "Stop" then
    run.stop()
    run.status = "stopped"
    for _, entry in ipairs(run.agents) do
      if entry.status == "queued" or entry.status == "running" then entry.status = "stopped" end
    end
    uji.notify("stopped " .. run.id)
  elseif choice == "Show details" then
    show(run)
  elseif choice == "Open an agent's session" then
    sessions(run)
  elseif choice == "Copy the script into the input" then
    uji.input.set(run.script)
  end
end

local function browse()
  if #state.order == 0 then
    uji.notify("no workflows have run yet")
    return
  end
  local items, chosen = {}, {}
  for index, id in ipairs(state.order) do
    local run = state.runs[id]
    items[index] = summary(run)
    chosen[items[index]] = run
  end
  local choice = uji.ui.select({ title = "Workflows", items = items })
  if choice then inspect(chosen[choice]) end
end

local function launch(text)
  local name, rest = text:match("^(%S+)%s*(.-)%s*$")
  local found = saved(state.opts.scope)
  if not name then
    local names = sorted_names(found)
    if #names == 0 then
      uji.notify("no saved workflows; add one to workflows/ in your config directory")
      return
    end
    local items = {}
    for index, saved_name in ipairs(names) do
      local meta = found[saved_name].meta
      items[index] = saved_name .. (meta and meta.description and (" - " .. meta.description) or "")
    end
    local choice = uji.ui.select({ title = "Saved workflows", items = items })
    if choice then uji.input.set("/workflow " .. choice:match("^(%S+)") .. " ") end
    return
  end
  if not found[name] then
    uji.notify("there is no saved workflow " .. name)
    return
  end
  uji.session.submit(string.format(
    "Run the saved workflow `%s` with the workflow tool%s, then tell me what it found.",
    name, rest ~= "" and (" and these args: " .. rest) or ""
  ))
end

-- setup --------------------------------------------------------------------

local DESCRIPTION = table.concat({
  "Run a workflow: a short Lua script that orchestrates agents, each a separate uji process with a context of its",
  "own. Use it when a task splits into many independent pieces of work, such as reviewing each changed file,",
  "or needs stages, such as find then verify. For one or two agents, use the subagent tool instead.",
  "",
  "The script starts with `meta = { name = \"...\", description = \"...\", phases = { \"...\" } }`, a plain table.",
  "Then it may call:",
  "- agent(prompt, opts) -> answer, or nil and an error. opts: label, phase, agent (a named agent), model,",
  "  effort, tools (a list), cwd. The agent sees only its prompt, so include everything it needs.",
  "- parallel({ function() ... end, ... }) -> results in order, and errors by index when any failed.",
  "- pipeline(items, stage1, stage2, ...) -> each item runs through the stages as soon as it clears the last",
  "  one, all items at once. A stage gets (value, index); a nil value skips the later stages.",
  "- phase(name) sets the phase of the agents that follow. log(...) notes a line in the run.",
  "- args is the `args` you pass. json.encode and json.decode are there; files, processes and modules are not.",
  "The script's return value is the result, as JSON unless it is a string. At most %d agents run in a",
  "workflow, %d at once. `resume` with an earlier run's id reuses the answers of agent() calls that did not change.",
  "",
  "Example:",
  "meta = { name = \"review\", description = \"review each file, then verify\", phases = { \"Review\", \"Verify\" } }",
  "phase(\"Review\")",
  "local found = pipeline(args.files, function(file)",
  "  return agent(\"Review \" .. file .. \" for bugs. List each as one line.\", { label = file })",
  "end)",
  "phase(\"Verify\")",
  "return parallel({ function() return agent(\"Check these findings:\\n\" .. table.concat(found, \"\\n\")) end })",
}, "\n")

local function nested()
  for _, arg in ipairs(uji.os.argv) do
    if arg == "--parent" or arg:match("^%-%-parent=") then return true end
  end
  return false
end

function M.setup(opts)
  state.opts = merged(DEFAULTS, opts)
  if nested() then return end

  uji.context.add("workflows", function()
    local names = sorted_names(saved(state.opts.scope))
    if #names == 0 then return nil end
    local lines = { "Saved workflows you can run with the workflow tool's `name`:" }
    for _, name in ipairs(names) do
      local meta = saved(state.opts.scope)[name].meta
      lines[#lines + 1] = "- " .. name .. (meta and meta.description and (": " .. meta.description) or "")
    end
    return table.concat(lines, "\n")
  end, { priority = 31 })

  uji.tool.add("workflow", {
    description = string.format(DESCRIPTION, state.opts.max_agents, state.opts.concurrency),
    parameters = {
      type = "object",
      properties = {
        script = { type = "string", description = "The workflow script, in Lua." },
        name = { type = "string", description = "A saved workflow to run instead of a script." },
        args = { description = "A value the script reads as `args`." },
        resume = { type = "string", description = "The id of an earlier run whose agent answers to reuse." },
      },
    },
    subject = function(args)
      local script = type(args) == "table" and source(args)
      local meta = script and M.meta(script)
      return meta and (meta.name .. (meta.description and (": " .. meta.description) or "")) or "workflow"
    end,
    policy = state.opts.policy,
    display = {
      verb = "Ran workflow",
      question = "Would you like to run this workflow? Its agents run without asking.",
      body = function(args)
        local script, missing = source(args or {})
        return script or missing
      end,
    },
    run = function(args, ctx)
      local stops, holder = {}, {}
      local worker = uji.task.spawn(function()
        local ok, result = pcall(start, args or {}, ctx, stops, holder)
        ctx.done(ok and result or ("error: " .. uji.message(result)))
      end)
      return function()
        worker:cancel()
        for _, stop in ipairs(stops) do pcall(stop) end
        local run = holder.run
        if run and run.status == "running" then
          run.live, run.status = false, "stopped"
        end
      end
    end,
  })

  uji.command.add("workflows", {
    desc = "list workflow runs, see their agents, open their sessions, stop one",
    handler = function()
      uji.task.spawn(browse)
    end,
  })

  uji.command.add("workflow", {
    desc = "run a saved workflow: /workflow <name> [args]",
    handler = launch,
  })
end

return M
