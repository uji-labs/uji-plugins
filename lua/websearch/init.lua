local M = {}

local DEFAULTS = {
  backend = "auto",
  key_env = "BRAVE_API_KEY",
  brave_endpoint = "https://api.search.brave.com/res/v1/web/search",
  duck_endpoint = "https://html.duckduckgo.com/html/",
  agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
  count = 5,
  timeout = 20,
}

local state = { opts = DEFAULTS }

local function merged(base, over)
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, v in pairs(over or {}) do out[k] = v end
  return out
end

local function escape(text)
  return (tostring(text):gsub("[^%w%-%._~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

local function unescape(text)
  return (tostring(text or ""):gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

local ENTITIES = {
  ["&amp;"] = "&", ["&lt;"] = "<", ["&gt;"] = ">",
  ["&quot;"] = '"', ["&#39;"] = "'", ["&#x27;"] = "'", ["&nbsp;"] = " ",
}

local function plain(text)
  text = tostring(text or ""):gsub("<[^>]*>", "")
  text = text:gsub("&%a+;", ENTITIES):gsub("&#x?%w+;", ENTITIES)
  return (text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function render(hits, want)
  if #hits == 0 then return "No results." end
  local lines = {}
  for i, hit in ipairs(hits) do
    if i > want then break end
    lines[#lines + 1] = string.format("%d. %s\n   %s\n   %s", i, hit.title, hit.url, hit.snippet)
  end
  return table.concat(lines, "\n\n")
end

function M.parse_brave(body, want)
  local ok, parsed = pcall(uji.json.decode, body)
  if not ok or type(parsed) ~= "table" then
    return "error: search returned something that was not JSON"
  end
  if parsed.error then
    return "error: " .. tostring(parsed.error.detail or parsed.error.code or "search failed")
  end
  local hits = {}
  for _, hit in ipairs((parsed.web and parsed.web.results) or {}) do
    hits[#hits + 1] = { title = plain(hit.title), url = tostring(hit.url), snippet = plain(hit.description) }
  end
  return render(hits, want)
end

function M.parse_duck(body, want)
  local hits = {}
  local snippets = {}
  for snippet in body:gmatch('result__snippet[^>]*>(.-)</a>') do
    snippets[#snippets + 1] = plain(snippet)
  end
  local at = 0
  for url, title in body:gmatch('result__a[^>]*href="([^"]+)"[^>]*>(.-)</a>') do
    at = at + 1
    local target = url
    local wrapped = target:match("^//duckduckgo%.com/l/.*[?&]uddg=([^&]+)")
    if wrapped then target = unescape(wrapped) end
    hits[#hits + 1] = { title = plain(title), url = target, snippet = snippets[at] or "" }
  end
  return render(hits, want)
end

local function fetch(request, done, finish)
  request.timeout = state.opts.timeout
  uji.http.request(request, function(response, err)
    if response then
      done(finish(response.body))
    else
      done("error: search request failed: " .. err)
    end
  end)
end

function M.backend()
  local opts = state.opts
  if opts.backend ~= "auto" then return opts.backend end
  local key = os.getenv(opts.key_env)
  return (key and key ~= "") and "brave" or "duckduckgo"
end

local function search(query, want, done)
  local opts = state.opts
  if M.backend() == "brave" then
    fetch({
      url = string.format("%s?q=%s&count=%d", opts.brave_endpoint, escape(query), want),
      headers = {
        Accept = "application/json",
        ["X-Subscription-Token"] = os.getenv(opts.key_env),
      },
    }, done, function(body) return M.parse_brave(body, want) end)
  else
    fetch({
      url = opts.duck_endpoint,
      method = "POST",
      headers = {
        ["User-Agent"] = opts.agent,
        ["Content-Type"] = "application/x-www-form-urlencoded",
      },
      body = "q=" .. escape(query),
    }, done, function(body) return M.parse_duck(body, want) end)
  end
end

function M.setup(opts)
  state.opts = merged(DEFAULTS, opts)

  uji.tool.register("web_search", {
    description = "Search the web and return the top results as title, url and snippet. "
      .. "Use it for current information, documentation and error messages you do not recognise.",
    subject = "web search",
    defer = true,
    parameters = {
      type = "object",
      properties = {
        query = { type = "string", description = "What to search for." },
        count = { type = "integer", description = "How many results to return." },
      },
      required = { "query" },
    },
    run = function(args, done)
      local query = args and args.query
      if type(query) ~= "string" or query == "" then
        done("error: query is required")
        return
      end
      local want = tonumber(args.count) or state.opts.count
      search(query, math.max(1, math.min(want, 20)), done)
    end,
  })
end

return M
