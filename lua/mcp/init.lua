local client = require("mcp.client")

local M = { servers = {} }

local function data_dir()
  local override = os.getenv("UJI_DATA_DIR")
  if override and override ~= "" then return override end
  return (os.getenv("HOME") or ".") .. "/.local/share/uji"
end

local function store_path() return data_dir() .. "/mcp.json" end

local function read_store()
  local handle = io.open(store_path(), "r")
  if not handle then return {} end
  local text = handle:read("*a")
  handle:close()
  local ok, parsed = pcall(uji.json.decode, text)
  return (ok and type(parsed) == "table" and parsed) or {}
end

local function write_store(entries)
  os.execute(string.format("mkdir -p %q", data_dir()))
  local handle = io.open(store_path(), "w")
  if not handle then
    uji.notify("mcp: could not write " .. store_path())
    return
  end
  handle:write(uji.json.encode(entries))
  handle:close()
  os.execute(string.format("chmod 600 %q", store_path()))
end

local PROTOCOL = "2024-11-05"

local function render(result)
    if type(result) ~= "table" then
        return ""
    end
    local parts = {}
    for _, part in ipairs(result.content or {}) do
        if part.type == "text" and part.text then
            table.insert(parts, part.text)
        elseif part.type == "resource" and part.resource and part.resource.text then
            table.insert(parts, part.resource.text)
        else
            table.insert(parts, "[" .. tostring(part.type) .. "]")
        end
    end
    local text = table.concat(parts, "\n")
    if result.isError then
        return "error: " .. text
    end
    return text
end

local function register(server, tools)
    for _, tool in ipairs(tools or {}) do
        local name = server.name .. "__" .. tool.name
        uji.tool.add(name, {
            description = tool.description or tool.name,
            parameters = tool.inputSchema or { type = "object", properties = {} },
            subject = tool.name,
            run = function(args, ctx)
                server:request("tools/call", { name = tool.name, arguments = args }, function(result, err)
                    if err then
                        ctx.done("error: " .. (err.message or "call failed"))
                    else
                        ctx.done(render(result))
                    end
                end)
            end,
        })
        table.insert(server.registered, name)
    end
end

local function handshake(server, on_ready)
    server:request("initialize", {
        protocolVersion = PROTOCOL,
        capabilities = {},
        clientInfo = { name = "uji", version = "0.1.0" },
    }, function(_, err)
        if err then
            uji.notify(server.name .. ": initialize failed: " .. (err.message or "?"))
            return
        end
        server:notify("notifications/initialized")
        server:request("tools/list", {}, function(result, list_err)
            if list_err then
                uji.notify(server.name .. ": tools/list failed: " .. (list_err.message or "?"))
                return
            end
            register(server, result and result.tools)
            server.ready = true
            if on_ready then
                on_ready(server)
            end
        end)
    end)
end

local function connect(name, spec, on_ready)
  local server = client.start(name, spec)
  M.servers[name] = server
  handshake(server, on_ready)
  return server
end

local function remember(name, spec)
  local entries = read_store()
  entries[name] = { url = spec.url, token = spec.token }
  write_store(entries)
end

local function forget(name)
  local entries = read_store()
  entries[name] = nil
  write_store(entries)
end

local function name_for(url)
  return (url:match("^https?://([^/:]+)") or url):gsub("%W", "_")
end

function M.add(url, on_ready)
  if type(url) ~= "string" or not url:match("^https?://") then
    uji.notify("mcp: that is not a URL")
    return
  end
  local name = name_for(url)
  local spec = { url = url }
  spec.on_token = function(token)
    spec.token = token
    remember(name, spec)
  end
  connect(name, spec, function(server)
    remember(name, spec)
    uji.notify(("mcp: %s ready, %d tools"):format(name, #server.registered))
    if on_ready then on_ready(server) end
  end)
end

function M.remove(name)
  local server = M.servers[name]
  if server then
    server:stop()
    M.servers[name] = nil
  end
  forget(name)
  uji.notify("mcp: removed " .. name)
end

local function choose(title, on_pick)
  local names = {}
  for name in pairs(M.servers) do names[#names + 1] = name end
  table.sort(names)
  if #names == 0 then
    uji.notify("mcp: no servers")
    return
  end
  local items = {}
  for _, name in ipairs(names) do
    local server = M.servers[name]
    items[#items + 1] = ("%s  %s  %d tools"):format(
      name, server.ready and "ready" or "connecting", #server.registered)
  end
  uji.ui.select({ title = title, items = items }, function(choice)
    if not choice then return end
    on_pick(choice:match("^(%S+)"))
  end)
end

function M.setup(opts)
  opts = opts or {}
  for name, spec in pairs(opts.servers or {}) do
    connect(name, spec, opts.on_ready)
  end
  for name, spec in pairs(read_store()) do
    if not M.servers[name] then
      spec.on_token = function(token)
        spec.token = token
        remember(name, spec)
      end
      connect(name, spec, opts.on_ready)
    end
  end

  uji.command.add("mcp", function(args)
    local verb, rest = args:match("^(%S*)%s*(.*)$")
    if verb == "add" then
      if rest ~= "" then
        M.add(rest)
      else
        uji.ui.prompt({ title = "MCP server URL" }, function(url)
          if url and url ~= "" then M.add(url) end
        end)
      end
    elseif verb == "remove" then
      choose("Remove which server?", M.remove)
    else
      choose("MCP servers", function(name)
        local server = M.servers[name]
        uji.notify(("%s: %s"):format(name, table.concat(server.registered, ", ")))
      end)
    end
  end)
end

function M.stop()
    for name, server in pairs(M.servers) do
        server:stop()
        M.servers[name] = nil
    end
end

function M.list()
    local out = {}
    for name, server in pairs(M.servers) do
        out[name] = { ready = server.ready, tools = server.registered }
    end
    return out
end

return M
