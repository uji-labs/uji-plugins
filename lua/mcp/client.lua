local Client = {}
Client.__index = Client

local M = {}

function M.start(name, spec)
    local self = setmetatable({
        name = name,
        spec = spec,
        next_id = 0,
        pending = {},
        registered = {},
        ready = false,
    }, Client)
    self.job = uji.job.start({
        cmd = spec.cmd,
        cwd = spec.cwd,
        on_stdout = function(line) self:receive(line) end,
        on_stderr = function(line) uji.notify(name .. ": " .. line) end,
        on_exit = function(code) self:closed(code) end,
    })
    return self
end

function Client:request(method, params, callback)
    self.next_id = self.next_id + 1
    local id = self.next_id
    self.pending[id] = callback
    uji.job.send(self.job, uji.json.encode({
        jsonrpc = "2.0",
        id = id,
        method = method,
        params = params or {},
    }))
end

function Client:notify(method, params)
    uji.job.send(self.job, uji.json.encode({
        jsonrpc = "2.0",
        method = method,
        params = params or {},
    }))
end

function Client:receive(line)
    if line == "" then
        return
    end
    local ok, message = pcall(uji.json.decode, line)
    if not ok or type(message) ~= "table" or message.id == nil then
        return
    end
    local callback = self.pending[message.id]
    if not callback then
        return
    end
    self.pending[message.id] = nil
    callback(message.result, message.error)
end

function Client:closed(code)
    self.ready = false
    for _, name in ipairs(self.registered) do
        uji.tool.unregister(name)
    end
    self.registered = {}
    for id, callback in pairs(self.pending) do
        self.pending[id] = nil
        callback(nil, { message = "server exited with " .. tostring(code) })
    end
    if code ~= 0 then
        uji.notify(self.name .. ": server exited with " .. tostring(code))
    end
end

function Client:stop()
    uji.job.stop(self.job)
end

return M
