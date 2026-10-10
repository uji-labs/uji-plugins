local M = {}

-- Each backend is a module in backend/ with search(opts, query, count, done)
-- and fetch(opts, url, chars, done).
local BACKENDS = { exa = true, searxng = true }

local DEFAULTS = {
  backend = "exa",
  policy = "allow",
  count = 5,
  chars = 20000,
  timeout = 30,
}

local function merged(base, over)
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, v in pairs(over or {}) do out[k] = v end
  return out
end

function M.setup(opts)
  opts = merged(DEFAULTS, opts)
  if not BACKENDS[opts.backend] then
    error('websearch: backend must be "exa" or "searxng", not ' .. tostring(opts.backend))
  end
  local backend = require("websearch.backend." .. opts.backend)

  uji.tool.add("web_search", {
    description = "Search the web and return the top results with their title, url and highlights. "
      .. "Use it for current information, documentation and error messages you do not recognise.",
    subject = "web search",
    policy = opts.policy,
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
      local count = math.max(1, math.min(tonumber(args.count) or opts.count, 20))
      return backend.search(opts, query, count, ctx.done)
    end,
  })

  uji.tool.add("web_fetch", {
    description = "Fetch a web page and return its text. "
      .. "Use it to read a page that web_search found or a URL you were given.",
    subject = function(args)
      return type(args) == "table" and type(args.url) == "string" and args.url or "web fetch"
    end,
    policy = opts.policy,
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
      local chars = math.max(1, tonumber(args.chars) or opts.chars)
      return backend.fetch(opts, url, chars, ctx.done)
    end,
  })
end

return M
