-- Claude Code as a uji provider. Picking it makes uji a front end for the
-- claude command: its sign-in, tools, CLAUDE.md and MCP servers, with uji's
-- transcript, approval, interrupt and resume.
--
--   require("claude_code").setup({})

local wire = require("claude_code.wire")

local M = {}

local EFFORTS = { "off", "low", "medium", "high", "xhigh", "max" }
local MODELS = { "claude-fable-5-1", "claude-opus-5-5", "claude-sonnet-5", "claude-haiku-4-5-20251001" }

local function prompt(messages)
  local parts = {}
  for _, message in ipairs(messages or {}) do
    if type(message.text) == "string" and message.text ~= "" then
      parts[#parts + 1] = message.text
    end
  end
  return table.concat(parts, "\n\n")
end

local function result(output)
  local ok, decoded = pcall(uji.json.decode, output, { nulls = false })
  if not ok or type(decoded) ~= "table" then
    return nil
  end
  if decoded.type == "result" then
    return decoded
  end
  for index = #decoded, 1, -1 do
    if type(decoded[index]) == "table" and decoded[index].type == "result" then
      return decoded[index]
    end
  end
end

-- The api answers the tool-less calls uji still makes itself, such as the
-- session title, with a one-shot `claude -p`.
local Api = uji.class()

function Api:init(spec)
  self.spec = spec
end

function Api.efforts()
  return EFFORTS
end

function Api:stream(request)
  local out, problems, finished = {}, {}, uji.promise()
  local job = uji.job.start({
    cmd = wire.oneshot({ command = self.spec.command, system = request.system, model = request.model }),
    timeout = 120,
    on_stdout = function(line)
      out[#out + 1] = line
    end,
    on_stderr = function(line)
      problems[#problems + 1] = line
    end,
    on_exit = function()
      finished:resolve()
    end,
  })
  job.send(prompt(request.messages))
  job.close()
  finished:await()
  local answer = result(table.concat(out, "\n"))
  if not answer or wire.failed(answer) then
    local reason = answer and wire.failure(answer) or table.concat(problems, "\n")
    return nil, { kind = "provider", message = reason ~= "" and reason or "claude gave no answer" }
  end
  return { text = answer.result or "", usage = wire.usage(answer.usage) }
end

function M.setup(opts)
  opts = opts or {}
  local models = {}
  for index, id in ipairs(opts.models or MODELS) do
    models[index] = { id = id, reasoning = true, efforts = EFFORTS }
  end
  uji.provider.add({
    id = opts.id or "claude-code",
    name = opts.name or "Claude Code",
    api = Api(opts),
    loop = require("claude_code.loop")(opts),
    base_url = "",
    models = models,
  })
end

return M
