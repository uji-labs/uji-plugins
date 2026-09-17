local client = require("mcp.client")

local M = { servers = {} }

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
        uji.tool.register(name, {
            description = tool.description or tool.name,
            parameters = tool.inputSchema or { type = "object", properties = {} },
            subject = tool.name,
            defer = true,
            run = function(args, done)
                server:request("tools/call", { name = tool.name, arguments = args }, function(result, err)
                    if err then
                        done("error: " .. (err.message or "call failed"))
                    else
                        done(render(result))
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

function M.setup(opts)
    for name, spec in pairs((opts or {}).servers or {}) do
        local server = client.start(name, spec)
        M.servers[name] = server
        handshake(server, (opts or {}).on_ready)
    end
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
