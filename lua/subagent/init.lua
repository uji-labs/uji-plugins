local fs = require("uji.sys.fs")

local M = {}

local DEFAULTS = {
  policy = "allow",
  scope = "user",
  confirm_project = true,
  max_tasks = 8,
  concurrency = 4,
  output = 50 * 1024,
}

local FLAGS = { ["config-dir"] = true, ["data-dir"] = true, db = true }

local state = { opts = DEFAULTS }

local function merged(base, over)
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, v in pairs(over or {}) do out[k] = v end
  return out
end

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function frontmatter(source)
  local head, body = source:match("^%-%-%-%s*\n(.-)\n%-%-%-[^\n]*\n?(.*)$")
  if not head then
    return {}, source
  end
  local fields = {}
  for line in head:gmatch("[^\n]+") do
    local key, value = line:match("^([%w_%-]+):%s*(.-)%s*$")
    if key then
      fields[key] = value:match('^"(.*)"$') or value:match("^'(.*)'$") or value
    end
  end
  return fields, body
end

local function names(value)
  local list = {}
  for name in (value or ""):gsub("^%[", ""):gsub("%]$", ""):gmatch("[^,%s]+") do
    list[#list + 1] = name
  end
  return #list > 0 and list or nil
end

local function load(dir, source, into)
  for _, entry in ipairs(fs.list(dir) or {}) do
    local file = entry.name:match("^(.+)%.md$")
    local text = file and fs.read(dir .. "/" .. entry.name)
    if text then
      local fields, body = frontmatter(text)
      local name = fields.name or file
      if fields.description then
        into[name] = {
          name = name,
          description = fields.description,
          tools = names(fields.tools),
          model = fields.model,
          effort = fields.effort,
          prompt = trim(body),
          source = source,
          path = dir .. "/" .. entry.name,
        }
      end
    end
  end
end

local function project_dir(from)
  local dir = from
  while dir and dir ~= "" do
    local candidate = dir .. "/.uji/agents"
    local stat = fs.stat(candidate)
    if stat and stat.type == "dir" then
      return candidate
    end
    local parent = dir:match("^(.*)/[^/]*$")
    if parent == dir then
      break
    end
    dir = parent
  end
end

function M.agents(scope)
  local found = {}
  if scope ~= "project" then
    for _, root in ipairs(uji.pack.list()) do
      load(root .. "/agents", "user", found)
    end
  end
  if scope ~= "user" then
    local dir = project_dir(uji.session.info().directory)
    if dir then
      load(dir, "project", found)
    end
  end
  return found
end

local function sorted(agents)
  local list = {}
  for _, agent in pairs(agents) do list[#list + 1] = agent end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

local function listed(agents)
  local lines = {}
  for _, agent in ipairs(sorted(agents)) do
    lines[#lines + 1] = "- " .. agent.name .. ": " .. agent.description
  end
  return table.concat(lines, "\n")
end

local function inherited()
  local out = {}
  local argv = uji.os.argv
  local index = 2
  while index <= #argv do
    local arg = argv[index]
    local flag = arg:match("^%-%-([%w%-]+)=")
    if flag and FLAGS[flag] then
      out[#out + 1] = arg
    elseif arg:sub(1, 2) == "--" and FLAGS[arg:sub(3)] and argv[index + 1] then
      out[#out + 1] = arg
      out[#out + 1] = argv[index + 1]
      index = index + 1
    end
    index = index + 1
  end
  return out
end

local function command(agent, task)
  local cmd = {
    uji.os.executable, "run", "--json",
    "--parent", uji.session.info().id,
    "--title", agent.name .. ": " .. task:match("^%s*([^\n]*)"),
  }
  for _, arg in ipairs(inherited()) do cmd[#cmd + 1] = arg end
  if agent.model then
    cmd[#cmd + 1] = "--model"
    cmd[#cmd + 1] = agent.model
  end
  if agent.effort then
    cmd[#cmd + 1] = "--effort"
    cmd[#cmd + 1] = agent.effort
  end
  if agent.tools then
    cmd[#cmd + 1] = "--tools"
    cmd[#cmd + 1] = table.concat(agent.tools, ",")
  end
  if agent.prompt ~= "" then
    cmd[#cmd + 1] = "--append-prompt"
    cmd[#cmd + 1] = agent.prompt
  end
  cmd[#cmd + 1] = "Task: " .. task
  return cmd
end

local function spawn(agent, task, cwd, progress, stops)
  local finished = uji.promise()
  local output, errors = nil, {}
  local job = uji.job.start({
    cmd = command(agent, task),
    cwd = cwd or uji.session.info().directory,
    on_stdout = function(line)
      local ok, event = pcall(uji.json.decode, line)
      if not ok or type(event) ~= "table" then return end
      if event.type == "progress" then
        progress(agent.name .. ": " .. event.tool .. " " .. event.line)
      elseif event.type == "message" and event.message.type == "assistant" then
        for _, call in ipairs(event.message.tool_calls or {}) do
          progress(agent.name .. ": " .. call.name)
        end
      elseif event.type == "done" then
        output = event.text or ("error: " .. tostring(event.error))
      end
    end,
    on_stderr = function(line)
      errors[#errors + 1] = line
    end,
    on_exit = function(code, reason)
      local failed = "error: " .. agent.name .. " stopped (" .. (reason or ("exit code " .. code)) .. ")"
      if #errors > 0 then
        failed = failed .. ": " .. table.concat(errors, "\n")
      end
      finished:resolve(output or failed)
    end,
  })
  job.close()
  stops[#stops + 1] = job.stop
  return finished:await()
end

local function clipped(text)
  if #text <= state.opts.output then
    return text
  end
  return text:sub(1, state.opts.output) .. "\n[cut at " .. state.opts.output .. " of " .. #text .. " bytes]"
end

local function failed(text)
  return text:sub(1, 6) == "error:"
end

local function parallel(items, run, stops)
  local results, next_item = {}, 1
  local waits = {}
  for slot = 1, math.min(state.opts.concurrency, #items) do
    local done = uji.promise()
    waits[slot] = done
    local worker = uji.task.spawn(function()
      while next_item <= #items do
        local index = next_item
        next_item = next_item + 1
        results[index] = run(items[index])
      end
      done:resolve()
    end)
    stops[#stops + 1] = function() worker:cancel() end
  end
  for _, done in ipairs(waits) do done:await() end
  return results
end

local function resolve(agents, items)
  for _, item in ipairs(items) do
    item.found = agents[item.agent]
    if not item.found then
      local available = {}
      for _, agent in ipairs(sorted(agents)) do available[#available + 1] = agent.name end
      return "error: there is no agent `" .. tostring(item.agent) .. "`. The agents are: "
        .. (#available > 0 and table.concat(available, ", ") or "none")
    end
  end
end

local function approved(items)
  if not state.opts.confirm_project then return true end
  local from = {}
  for _, item in ipairs(items) do
    if item.found.source == "project" then from[#from + 1] = item.found.path end
  end
  if #from == 0 then return true end
  local choice = uji.ui.select({
    title = "Run agents from this project? " .. table.concat(from, ", "),
    items = { "Run them", "Cancel" },
  })
  return choice == "Run them"
end

local function execute(args, ctx, stops)
  local scope = args.scope or state.opts.scope
  local agents = M.agents(scope)
  local mode, items
  if type(args.chain) == "table" and #args.chain > 0 then
    mode, items = "chain", args.chain
  elseif type(args.tasks) == "table" and #args.tasks > 0 then
    mode, items = "parallel", args.tasks
  elseif type(args.agent) == "string" and type(args.task) == "string" then
    mode, items = "single", { { agent = args.agent, task = args.task, cwd = args.cwd } }
  else
    return "error: give `agent` and `task`, or `tasks`, or `chain`"
  end
  if mode == "parallel" and #items > state.opts.max_tasks then
    return "error: at most " .. state.opts.max_tasks .. " tasks run at the same time"
  end
  local missing = resolve(agents, items)
  if missing then return missing end
  if not approved(items) then return "error: you did not approve the project's agents" end
  local function run(item, task)
    return spawn(item.found, task or item.task, item.cwd, ctx.progress, stops)
  end
  if mode == "single" then
    return run(items[1])
  end
  if mode == "chain" then
    local previous = ""
    for index, item in ipairs(items) do
      local task = item.task:gsub("{previous}", function() return previous end)
      previous = run(item, task)
      if failed(previous) then
        return "error: step " .. index .. " (" .. item.agent .. ") failed: " .. previous:sub(8)
      end
    end
    return previous
  end
  local results = parallel(items, run, stops)
  local parts = {}
  for index, item in ipairs(items) do
    parts[index] = "## " .. index .. ". " .. item.agent .. "\n\n" .. clipped(results[index] or "error: not run")
  end
  return table.concat(parts, "\n\n")
end

local function pick()
  local agents = sorted(M.agents(state.opts.scope))
  if #agents == 0 then
    uji.notify("no agents found; add one to agents/ in your config directory")
    return
  end
  local items, chosen = {}, {}
  for index, agent in ipairs(agents) do
    items[index] = agent.name .. " - " .. agent.description
    chosen[items[index]] = agent.name
  end
  local choice = uji.ui.select({ title = "Agents", items = items })
  if choice then
    uji.input.set("/agent " .. chosen[choice] .. " ")
  end
end

local function delegate(args)
  local name, task = args:match("^(%S+)%s+(.-)%s*$")
  if not name then
    return pick()
  end
  if not M.agents(state.opts.scope)[name] then
    uji.notify("there is no agent " .. name)
    return
  end
  uji.session.submit(string.format(
    "Run the `%s` agent with the subagent tool on this task, then tell me what it found.\n\n%s",
    name, task
  ))
end

local TASK = {
  type = "object",
  properties = {
    agent = { type = "string", description = "The agent to run." },
    task = { type = "string", description = "What the agent should do." },
    cwd = { type = "string", description = "The directory it works in." },
  },
  required = { "agent", "task" },
}

local function nested()
  for _, arg in ipairs(uji.os.argv) do
    if arg == "--parent" or arg:match("^%-%-parent=") then return true end
  end
  return false
end

function M.setup(opts)
  state.opts = merged(DEFAULTS, opts)
  if nested() then return end

  uji.context.add("subagents", function()
    local agents = M.agents(state.opts.scope)
    if next(agents) == nil then return nil end
    return "Agents you can start with the subagent tool:\n" .. listed(agents)
  end, { priority = 30 })

  uji.tool.add("subagent", {
    description = "Hand tasks to agents that each work in a separate uji process with a context of their own, "
      .. "and get back their final answers. Give `agent` and `task` for one task, `tasks` for several that "
      .. "run at the same time, or `chain` for steps that run in order, where `{previous}` in a step's task "
      .. "is replaced by the answer of the step before. An agent sees only its task, so include what it needs.",
    parameters = {
      type = "object",
      properties = {
        agent = { type = "string", description = "The agent to run, for one task." },
        task = { type = "string", description = "The task, for one task." },
        cwd = { type = "string", description = "The directory one task works in." },
        tasks = { type = "array", items = TASK, description = "Tasks that run at the same time." },
        chain = { type = "array", items = TASK, description = "Tasks that run in order." },
        scope = {
          type = "string",
          enum = { "user", "project", "both" },
          description = "Where agents come from: your config and packs, the project's .uji/agents, or both.",
        },
      },
    },
    subject = function(args)
      if type(args) ~= "table" then return "subagent" end
      local list = args.chain or args.tasks
      if type(list) ~= "table" then return tostring(args.agent) end
      local agents = {}
      for index, item in ipairs(list) do agents[index] = tostring(item.agent) end
      return table.concat(agents, args.chain and " > " or ", ")
    end,
    policy = state.opts.policy,
    display = { verb = "Ran", question = "Would you like to run these agents?" },
    run = function(args, ctx)
      local stops = {}
      local worker = uji.task.spawn(function()
        local ok, result = pcall(execute, args or {}, ctx, stops)
        ctx.done(ok and result or ("error: " .. uji.message(result)))
      end)
      return function()
        worker:cancel()
        for _, stop in ipairs(stops) do stop() end
      end
    end,
  })

  uji.command.add("agent", {
    desc = "run an agent on a task: /agent <name> <task>",
    handler = delegate,
  })
end

return M
