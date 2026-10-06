-- The stream-json protocol the claude command speaks on stdin and stdout.
-- Pure functions: build argv and frames, and pick apart what claude prints.

local UNSET = { "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SSE_PORT" }
local DISALLOWED = "AskUserQuestion,EnterPlanMode,ExitPlanMode"
local TOOL_USE = { tool_use = true, server_tool_use = true, mcp_tool_use = true }

local M = {}

-- A claude started from inside another claude session must not see its
-- parent's environment, so the launcher strips it.
local function launcher(command)
  local out = { "env" }
  for _, name in ipairs(UNSET) do
    out[#out + 1] = "-u"
    out[#out + 1] = name
  end
  for _, part in ipairs(command or { "claude" }) do
    out[#out + 1] = part
  end
  return out
end

local function push(out, ...)
  for _, part in ipairs({ ... }) do
    out[#out + 1] = part
  end
end

function M.argv(opts)
  local out = launcher(opts.command)
  push(out, "--output-format", "stream-json", "--verbose", "--input-format", "stream-json")
  push(out, "--permission-prompt-tool", "stdio", "--include-partial-messages")
  push(out, "--setting-sources=user,project,local")
  push(out, "--permission-mode", opts.permission_mode or "default")
  push(out, "--disallowed-tools", DISALLOWED)
  if opts.model and opts.model ~= "" then
    push(out, "--model", opts.model)
  end
  if opts.effort and opts.effort ~= "off" then
    push(out, "--effort", opts.effort)
  end
  if opts.fresh then
    push(out, "--session-id=" .. opts.session)
  else
    push(out, "--resume=" .. opts.session)
  end
  return out
end

function M.oneshot(opts)
  local out = launcher(opts.command)
  push(out, "-p", "--output-format", "json", "--tools", "", "--no-session-persistence", "--setting-sources", "")
  push(out, "--system-prompt", opts.system or "")
  if opts.model and opts.model ~= "" then
    push(out, "--model", opts.model)
  end
  return out
end

function M.user(text, images)
  local content = { { type = "text", text = text } }
  for _, image in ipairs(images or {}) do
    content[#content + 1] = {
      type = "image",
      source = { type = "base64", media_type = image.media_type, data = image.data },
    }
  end
  return {
    type = "user",
    message = { role = "user", content = uji.json.array(content) },
    session_id = "",
  }
end

function M.interrupt(id)
  return { type = "control_request", request_id = id, request = { subtype = "interrupt" } }
end

local function answer(request, response)
  response.toolUseID = request.request.tool_use_id
  return {
    type = "control_response",
    response = { subtype = "success", request_id = request.request_id, response = response },
  }
end

function M.allow(request, input)
  return answer(request, { behavior = "allow", updatedInput = input })
end

function M.deny(request, message)
  return answer(request, { behavior = "deny", message = message })
end

function M.usage(raw)
  if type(raw) ~= "table" then
    return nil
  end
  return {
    input = raw.input_tokens or 0,
    output = raw.output_tokens or 0,
    cache_read = raw.cache_read_input_tokens or 0,
    cache_write = raw.cache_creation_input_tokens or 0,
  }
end

function M.blocks(frame)
  local message = type(frame.message) == "table" and frame.message or {}
  local content = message.content
  if type(content) == "string" then
    return { { type = "text", text = content } }
  end
  return type(content) == "table" and content or {}
end

-- Adds the content blocks of one assistant frame to a uji assistant message.
function M.absorb(message, frame)
  for _, block in ipairs(M.blocks(frame)) do
    if block.type == "text" then
      message.text = message.text .. (block.text or "")
    elseif block.type == "thinking" and (block.thinking or "") ~= "" then
      message.reasoning = (message.reasoning or "") .. block.thinking
    elseif TOOL_USE[block.type] then
      message.tool_calls[#message.tool_calls + 1] = {
        id = block.id,
        name = block.name,
        arguments = uji.json.encode(block.input or {}),
      }
    end
  end
end

local function flatten(content)
  if type(content) == "string" then
    return content
  end
  local parts = {}
  for _, part in ipairs(type(content) == "table" and content or {}) do
    if part.type == "text" then
      parts[#parts + 1] = part.text or ""
    elseif part.type == "image" then
      parts[#parts + 1] = "[image]"
    end
  end
  return table.concat(parts, "\n")
end

function M.results(frame)
  local out = {}
  for _, block in ipairs(M.blocks(frame)) do
    if block.type and block.type:find("tool_result", 1, true) then
      out[#out + 1] = { id = block.tool_use_id, content = flatten(block.content), failed = block.is_error == true }
    end
  end
  return out
end

function M.failure(frame)
  local errors = {}
  for _, problem in ipairs(type(frame.errors) == "table" and frame.errors or {}) do
    errors[#errors + 1] = tostring(problem)
  end
  if #errors > 0 then
    return table.concat(errors, "\n")
  end
  if type(frame.result) == "string" and frame.result ~= "" then
    return frame.result
  end
  return tostring(frame.subtype or "failed")
end

function M.failed(frame)
  return frame.is_error == true or (frame.subtype ~= nil and frame.subtype ~= "success")
end

return M
