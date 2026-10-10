-- Your own SearXNG instance, at the url option or SEARXNG_URL. It only
-- searches, so pages are read here: fetched, and their HTML turned into text.
local M = {}

local function encoded(text)
  return (text:gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function instance(opts)
  return ((opts.url or os.getenv("SEARXNG_URL") or ""):gsub("/+$", ""))
end

function M.search(opts, query, count, done)
  local base = instance(opts)
  if base == "" then
    return done("error: set url, or SEARXNG_URL, to your SearXNG instance")
  end
  return uji.http.request({
    url = base .. "/search?format=json&q=" .. encoded(query),
    timeout = opts.timeout,
    headers = { Accept = "application/json" },
  }, function(response, err)
    if not response then
      return done("error: " .. err)
    end
    if response.status == 403 then
      return done("error: searxng refused JSON; add json to search.formats in its settings.yml")
    end
    if response.status == 429 then
      return done("error: searxng's limiter blocked the request; set server.limiter: false in its settings.yml, "
        .. "or use the url of the proxy in front of it")
    end
    if response.status ~= 200 then
      return done("error: searxng answered " .. response.status .. ": " .. response.body:sub(1, 300))
    end
    local ok, reply = pcall(uji.json.decode, response.body, { nulls = false })
    if not ok or type(reply) ~= "table" then
      return done("error: searxng sent an answer that is not JSON")
    end
    local found = {}
    for _, result in ipairs(reply.results or {}) do
      if #found == count then break end
      found[#found + 1] = ("Title: %s\nURL: %s\n%s"):format(result.title or "", result.url or "", result.content or "")
    end
    done(#found > 0 and table.concat(found, "\n\n") or "No results.")
  end)
end

local function anycase(word)
  return (word:gsub("%a", function(c) return "[" .. c:lower() .. c:upper() .. "]" end))
end

local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " " }

local function text_of(html)
  local text = html:gsub("<!%-%-.-%-%->", "")
  for _, tag in ipairs({ "script", "style", "noscript", "svg", "head" }) do
    text = text:gsub("<" .. anycase(tag) .. "[%s>].-</" .. anycase(tag) .. "%s*>", " ")
  end
  text = text:gsub("<%s*[Bb][Rr]%s*/?>", "\n")
  for _, tag in ipairs({ "p", "div", "li", "tr", "pre", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6" }) do
    text = text:gsub("</" .. anycase(tag) .. "%s*>", "\n")
  end
  text = text:gsub("<[^>]*>", "")
  text = text:gsub("&(%a+);", function(name) return ENTITIES[name:lower()] end)
  text = text:gsub("&#(%d+);", function(n) n = tonumber(n); return n < 128 and string.char(n) or nil end)
  text = text:gsub("[ \t\r]+", " "):gsub(" *\n *", "\n"):gsub("\n\n\n+", "\n\n")
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.fetch(opts, url, chars, done)
  return uji.http.request({
    url = url,
    timeout = opts.timeout,
    headers = { Accept = "text/html, text/plain;q=0.9, */*;q=0.5", ["User-Agent"] = "uji websearch" },
  }, function(response, err)
    if not response then
      return done("error: " .. err)
    end
    if response.status < 200 or response.status >= 300 then
      return done("error: " .. url .. " answered " .. response.status)
    end
    local kind = response.headers["content-type"] or ""
    local text = kind:find("html") and text_of(response.body) or response.body
    done(text ~= "" and text:sub(1, chars) or "The page has no text.")
  end)
end

return M
