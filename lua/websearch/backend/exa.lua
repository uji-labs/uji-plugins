-- Exa's public search service, through its MCP endpoint. It needs no key, but
-- the free service is rate limited per address; a key from Exa lifts that.
local M = {}

local EXA = "https://mcp.exa.ai/mcp"

local function answer(response)
  local ok, reply = pcall(uji.json.decode, response.body:match("data: ([^\n]+)") or response.body)
  if not ok or type(reply) ~= "table" then
    return nil, "exa sent an answer that is not JSON"
  end
  if type(reply.error) == "table" then
    return nil, tostring(reply.error.message)
  end
  local result = type(reply.result) == "table" and reply.result or {}
  local texts = {}
  for _, item in ipairs(result.content or {}) do
    if item.type == "text" then texts[#texts + 1] = item.text end
  end
  local text = table.concat(texts, "\n\n")
  if result.isError then
    return nil, text
  end
  return text
end

local function endpoint(opts)
  local key = opts.key or os.getenv("EXA_API_KEY")
  if key and key ~= "" then
    return EXA .. "?exaApiKey=" .. key
  end
  return EXA
end

local function call(opts, tool, arguments, empty, done)
  local body = { jsonrpc = "2.0", id = 1, method = "tools/call", params = { name = tool, arguments = arguments } }
  return uji.http.request({
    url = endpoint(opts),
    method = "POST",
    timeout = opts.timeout,
    headers = { ["Content-Type"] = "application/json", Accept = "application/json, text/event-stream" },
    body = uji.json.encode(body),
  }, function(response, err)
    if not response then
      return done("error: " .. err)
    end
    if response.status ~= 200 then
      return done("error: exa answered " .. response.status .. ": " .. response.body:sub(1, 300))
    end
    local text, problem = answer(response)
    if not text then
      return done("error: " .. problem)
    end
    done(text ~= "" and text or empty)
  end)
end

function M.search(opts, query, count, done)
  return call(opts, "web_search_exa", { query = query, objective = query, numResults = count }, "No results.", done)
end

function M.fetch(opts, url, chars, done)
  return call(opts, "web_fetch_exa", { urls = { url }, maxCharacters = chars }, "The page has no text.", done)
end

return M
