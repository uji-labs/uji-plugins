local M = {}

local EXA = "https://mcp.exa.ai/mcp"

local DEFAULTS = {
  policy = "allow",
  count = 5,
  chars = 20000,
  timeout = 30,
}

local state = { opts = DEFAULTS }

local function merged(base, over)
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, v in pairs(over or {}) do out[k] = v end
  return out
end

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

local function exa(tool, arguments, empty, done)
  return uji.http.request({
    url = EXA,
    method = "POST",
    timeout = state.opts.timeout,
    headers = { ["Content-Type"] = "application/json", Accept = "application/json, text/event-stream" },
    body = uji.json.encode({ jsonrpc = "2.0", id = 1, method = "tools/call", params = { name = tool, arguments = arguments } }),
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

function M.setup(opts)
  state.opts = merged(DEFAULTS, opts)

  uji.tool.add("web_search", {
    description = "Search the web and return the top results with their title, url and highlights. "
      .. "Use it for current information, documentation and error messages you do not recognise.",
    subject = "web search",
    policy = state.opts.policy,
    parameters = {
      type = "object",
      properties = {
        query = { type = "string", description = "What to search for, described as the page you want to find." },
        count = { type = "integer", description = "How many results to return." },
      },
      required = { "query" },
    },
    run = function(args, ctx)
      local query = args and args.query
      if type(query) ~= "string" or query == "" then
        return "error: query is required"
      end
      local count = math.max(1, math.min(tonumber(args.count) or state.opts.count, 20))
      return exa("web_search_exa", { query = query, objective = query, numResults = count }, "No results.", ctx.done)
    end,
  })

  uji.tool.add("web_fetch", {
    description = "Fetch a web page and return its text. "
      .. "Use it to read a page that web_search found or a URL you were given.",
    subject = function(args)
      return type(args) == "table" and type(args.url) == "string" and args.url or "web fetch"
    end,
    policy = state.opts.policy,
    parameters = {
      type = "object",
      properties = {
        url = { type = "string", description = "The http or https address of the page." },
        chars = { type = "integer", description = "How many characters of the page's text to return at most." },
      },
      required = { "url" },
    },
    run = function(args, ctx)
      local url = args and args.url
      if type(url) ~= "string" or not url:match("^https?://") then
        return "error: url must start with http:// or https://"
      end
      local chars = math.max(1, tonumber(args.chars) or state.opts.chars)
      return exa("web_fetch_exa", { urls = { url }, maxCharacters = chars }, "The page has no text.", ctx.done)
    end,
  })
end

return M
