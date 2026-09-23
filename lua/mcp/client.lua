local auth = require("mcp.auth")

local Client = {}
Client.__index = Client

local M = {}

local TIMEOUT = 45

function M.start(name, spec)
    local self = setmetatable({
        name = name,
        spec = spec,
        next_id = 0,
        pending = {},
        registered = {},
        ready = false,
        http = spec.url ~= nil,
        session = nil,
        token = spec.token,
    }, Client)
    if not self.http then
        self.job = uji.job.start({
            cmd = spec.cmd,
            cwd = spec.cwd,
            on_stdout = function(line) self:receive(line) end,
            on_stderr = function(line) uji.notify(name .. ": " .. line) end,
            on_exit = function(code) self:closed(code) end,
        })
    end
    return self
end

local function body_of(method, params, id)
    local message = { jsonrpc = "2.0", method = method, params = params or {} }
    if id then
        message.id = id
    end
    return uji.json.encode(message)
end

function Client:headers()
    return {
        ["Content-Type"] = "application/json",
        Accept = "application/json, text/event-stream",
        ["Mcp-Session-Id"] = self.session,
        Authorization = self.token and ("Bearer " .. self.token),
    }
end

function Client:post(payload, retry)
    uji.http.request({
        url = self.spec.url,
        method = "POST",
        headers = self:headers(),
        body = payload,
        timeout = TIMEOUT,
    }, function(response, err)
        if not response then
            self:fail("request failed: " .. err)
            return
        end
        self:answer(response, payload, retry)
    end)
end

function Client:answer(response, payload, retry)
    local headers = response.headers
    self.session = headers["mcp-session-id"] or self.session

    if response.status == 401 and not retry then
        self:authorize(headers["www-authenticate"], payload)
        return
    end
    if response.status < 200 or response.status >= 300 then
        self:fail("server answered " .. response.status)
        return
    end
    for line in response.body:gmatch("[^\r\n]+") do
        self:receive(line:match("^data:%s*(.+)$") or line)
    end
end

function Client:authorize(challenge, payload)
    auth.acquire(self.name, self.spec.url, challenge, function(token, err)
        if not token then
            self:fail(err or "authorization failed")
            return
        end
        self.token = token
        if self.spec.on_token then
            self.spec.on_token(token)
        end
        self:post(payload, true)
    end)
end

function Client:fail(message)
    uji.notify(self.name .. ": " .. message)
    for id, callback in pairs(self.pending) do
        self.pending[id] = nil
        callback(nil, { message = message })
    end
end

function Client:request(method, params, callback)
    self.next_id = self.next_id + 1
    local id = self.next_id
    self.pending[id] = callback
    local payload = body_of(method, params, id)
    if self.http then
        self:post(payload, false)
    else
        uji.job.send(self.job, payload)
    end
end

function Client:notify(method, params)
    local payload = body_of(method, params, nil)
    if self.http then
        self:post(payload, false)
    else
        uji.job.send(self.job, payload)
    end
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
    if self.http then
        self:closed(0)
    else
        uji.job.stop(self.job)
    end
end

return M
