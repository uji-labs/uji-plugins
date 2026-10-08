-- One claude process per uji session. It stays up between turns; a turn
-- writes a user frame and reads frames until the result.
--
-- The uji session id doubles as the Claude Code session id: the first turn
-- passes --session-id, later ones --resume, so resuming a uji session resumes
-- the Claude Code one with no bookkeeping.

local wire = require("claude_code.wire")

local STDERR_TAIL = 4000
local INTERRUPT_TIMEOUT = 3
local MISSING = "No conversation found"
local TAKEN = "is already in use"

local live = {}

local function projects()
  local custom = os.getenv("CLAUDE_CONFIG_DIR")
  if custom and custom ~= "" then
    return uji.fs.join(custom, "projects")
  end
  return uji.fs.join("~", ".claude", "projects")
end

-- Claude Code keeps one transcript per session under projects/<dir>/<id>.jsonl.
local function remembered(id)
  local found = uji.fs.glob(uji.fs.join(projects(), "*", id .. ".jsonl"))
  return found ~= nil and #found > 0
end

local Process = uji.class()

function Process:init(session, opts)
  self.session = session
  self.key = opts.key
  self.inbox = {}
  self.stderr = ""
  self.interrupts = 0
  self.alive = true
  self.job = uji.job.start({
    cmd = wire.argv({
      command = opts.command,
      permission_mode = opts.permission_mode,
      model = opts.model,
      effort = opts.effort,
      session = session.id,
      fresh = opts.fresh,
    }),
    cwd = session.directory,
    on_stdout = function(line)
      local ok, frame = pcall(uji.json.decode, line, { nulls = false })
      if ok and type(frame) == "table" then
        self:receive(frame)
      end
    end,
    on_stderr = function(line)
      self.stderr = (self.stderr .. line .. "\n"):sub(-STDERR_TAIL)
    end,
    on_exit = function(code)
      self:exited(code)
    end,
  })
end

function Process:push(item)
  self.inbox[#self.inbox + 1] = item
  local waiting = self.waiting
  if waiting then
    self.waiting = nil
    waiting:resolve()
  end
end

function Process:next()
  while #self.inbox == 0 do
    self.waiting = uji.promise()
    self.waiting:await()
  end
  return table.remove(self.inbox, 1)
end

function Process:begin()
  self.inbox = {}
  self.waiting = nil
end

function Process:write(frame)
  if self.alive then
    self.job.send(uji.json.encode(frame))
  end
end

function Process:receive(frame)
  if frame.type == "control_response" then
    return
  end
  if self.discarding then
    if frame.type == "result" then
      self.discarding = false
    end
    return
  end
  self:push(frame)
end

function Process:exited(code)
  self.alive = false
  if live[self.session.id] == self then
    live[self.session.id] = nil
  end
  if not self.closed then
    self:push({
      type = "exit",
      code = code,
      stderr = self.stderr:match("^%s*(.-)%s*$"),
      missing = self.stderr:find(MISSING, 1, true) ~= nil,
      taken = self.stderr:find(TAKEN, 1, true) ~= nil,
    })
  end
end

function Process:close()
  self.closed = true
  self.discarding = false
  if live[self.session.id] == self then
    live[self.session.id] = nil
  end
  if self.alive then
    self.job.stop()
  end
end

-- Asks claude to stop the turn, drops what it still prints up to the result,
-- and kills it when it has not answered in time.
function Process:interrupt()
  if not self.alive then
    return
  end
  self.interrupts = self.interrupts + 1
  local round = self.interrupts
  self.discarding = true
  self:write(wire.interrupt("uji-" .. round))
  uji.defer(INTERRUPT_TIMEOUT, function()
    if self.discarding and self.interrupts == round then
      self:close()
    end
  end)
end

local M = { remembered = remembered }

function M.acquire(session, opts)
  local current = live[session.id]
  if current and current.alive and current.key == opts.key and not opts.fresh then
    return current
  end
  if current then
    current:close()
  end
  if opts.fresh == nil then
    opts.fresh = not remembered(session.id)
  end
  local started = Process(session, opts)
  live[session.id] = started
  return started
end

uji.on("before_quit", function()
  for _, running in pairs(live) do
    running:close()
  end
end)

return M
