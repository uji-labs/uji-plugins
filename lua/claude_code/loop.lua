-- The agent loop for a Claude Code turn. Claude Code runs the model and its
-- own tools; this loop sends the prompt, mirrors what comes back into the
-- uji session, and answers permission requests through uji's approval.

local files = require("claude_code.files")
local process = require("claude_code.process")
local wire = require("claude_code.wire")

local KIND = { text_delta = "text", thinking_delta = "reasoning" }

return function(opts, measured)
  local Loop = uji.class()

  function Loop:init(agent, turn)
    self.agent = agent
    self.prompt = turn.prompt or { text = "" }
    self.model = turn.model
    self.effort = turn.effort
    self.calls = {}
    self.denied = {}
  end

  function Loop:interrupt()
    if self.process then
      self.process:interrupt()
    end
  end

  -- Assistant frames arrive one content block at a time, sharing a message
  -- id. They gather in self.pending until the message is known to be whole.
  function Loop:flush()
    local message = self.pending
    self.pending = nil
    if not message then
      return
    end
    if message.usage then
      self.agent:usage(message.usage)
      message.usage = nil
    end
    message.id = nil
    self.agent:assistant_step(message)
    for _, call in ipairs(message.tool_calls) do
      self.calls[call.id] = call
      uji.emit("tool_started", { name = call.name })
    end
    if message.tool_calls[1] then
      self.agent:tool_running(message.tool_calls[1])
    end
  end

  function Loop:assistant(frame)
    local message = type(frame.message) == "table" and frame.message or {}
    local id = message.id
    if self.pending and self.pending.id ~= id then
      self:flush()
    end
    self.pending = self.pending or { type = "assistant", id = id, text = "", tool_calls = {} }
    wire.absorb(self.pending, frame)
    self.pending.usage = wire.usage(message.usage) or self.pending.usage
  end

  function Loop:streamed(frame)
    local streamed = type(frame.event) == "table" and frame.event or {}
    local delta = type(streamed.delta) == "table" and streamed.delta or {}
    if streamed.type == "content_block_delta" and KIND[delta.type] then
      local text = delta.text or delta.thinking or ""
      if text ~= "" then
        self.agent:delta(KIND[delta.type], text)
      end
    elseif streamed.type == "message_delta" and self.pending and self.pending.usage then
      local usage = type(streamed.usage) == "table" and streamed.usage or {}
      self.pending.usage.output = usage.output_tokens or self.pending.usage.output
    elseif streamed.type == "message_stop" and self.pending and #self.pending.tool_calls > 0 then
      self:flush()
    end
  end

  function Loop:results(frame)
    self:flush()
    for _, result in ipairs(wire.results(frame)) do
      local call = self.calls[result.id]
      if call then
        local content = result.content
        if self.denied[result.id] then
          content = "denied: " .. self.denied[result.id]
        elseif result.failed then
          content = "error: " .. content
        end
        local shown = files.shown(result.raw)
        self.agent:tool_result(call, {
          text = self.agent:after_tool(call.name, content),
          diff = shown.diff,
          summary = shown.summary,
        })
      end
    end
  end

  function Loop:permit(frame)
    local request = type(frame.request) == "table" and frame.request or {}
    if request.subtype ~= "can_use_tool" then
      return
    end
    self:flush()
    local input = type(request.input) == "table" and request.input or {}
    local subject = input.command or input.file_path
    local decision = self.agent:approve(tostring(request.tool_name), input, subject)
    if decision.deny then
      if request.tool_use_id then
        self.denied[request.tool_use_id] = decision.deny
      end
      return self.process:write(wire.deny(frame, decision.deny))
    end
    self.process:write(wire.allow(frame, decision.arguments))
  end

  function Loop:finished(frame)
    if wire.failed(frame) then
      self:flush()
      return self.agent:failed("claude code: " .. wire.failure(frame))
    end
    local window = self.model and wire.window(frame, self.model)
    if window then
      measured(self.model, window)
    end
    local last = self.pending
    if last and #last.tool_calls == 0 then
      self.pending = nil
      if last.usage then
        self.agent:usage(last.usage)
      end
      last.id, last.usage = nil, nil
      return self.agent:done(last)
    end
    self:flush()
    local text = type(frame.result) == "string" and frame.result or ""
    self.agent:done({ type = "assistant", text = text, tool_calls = {} })
  end

  function Loop:exited(frame)
    self:flush()
    -- The guess about whether Claude Code knows this session was wrong:
    -- try once the other way round.
    if not self.restarted and (frame.missing or frame.taken) then
      self.restarted = true
      return self:start(frame.missing)
    end
    local reason = "claude code: stopped unexpectedly (exit " .. tostring(frame.code) .. ")"
    return self.agent:failed(frame.stderr ~= "" and reason .. "\n" .. frame.stderr or reason)
  end

  function Loop:start(fresh)
    local running = process.acquire(self.agent.session, {
      command = opts.command,
      permission_mode = opts.permission_mode,
      model = self.model,
      effort = self.effort,
      key = tostring(self.model) .. "|" .. tostring(self.effort),
      fresh = fresh,
    })
    self.process = running
    running:begin()
    running:write(wire.user(self.prompt.text, self.prompt.images))
    while true do
      local frame = running:next()
      if frame.parent_tool_use_id then
        frame = {}
      end
      if frame.type == "stream_event" then
        self:streamed(frame)
      elseif frame.type == "assistant" then
        self:assistant(frame)
      elseif frame.type == "user" then
        self:results(frame)
      elseif frame.type == "control_request" then
        self:permit(frame)
      elseif frame.type == "result" then
        return self:finished(frame)
      elseif frame.type == "exit" then
        return self:exited(frame)
      end
    end
  end

  function Loop:run()
    return self:start()
  end

  return Loop
end
