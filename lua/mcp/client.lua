local auth = require("mcp.auth")

local Client = {}
Client.__index = Client

local M = {}

local TIMEOUT = "45"

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
    local out = {
        "-H", "Content-Type: application/json",
        "-H", "Accept: application/json, text/event-stream",
    }
    if self.session then
        out[#out + 1] = "-H"
        out[#out + 1] = "Mcp-Session-Id: " .. self.session
    end
    if self.token then
        out[#out + 1] = "-H"
        out[#out + 1] = "Authorization: Bearer " .. self.token
    end
    return out
end

function Client:post(payload, retry)
    local lines = {}
    local cmd = { "curl", "-sS", "-i", "--max-time", TIMEOUT, "-X", "POST" }
    for _, part in ipairs(self:headers()) do
        cmd[#cmd + 1] = part
    end
    cmd[#cmd + 1] = "-d"
    cmd[#cmd + 1] = payload
    cmd[#cmd + 1] = self.spec.url
    uji.job.start({
        cmd = cmd,
        on_stdout = function(line) lines[#lines + 1] = line end,
        on_stderr = function(line) uji.notify(self.name .. ": " .. line) end,
        on_exit = function(code)
            if code ~= 0 then
                self:fail("request failed (curl exit " .. tostring(code) .. ")")
                return
            end
            self:answer(lines, payload, retry)
        end,
    })
end

local function split_headers(lines)
    local headers, body, at = {}, {}, 1
    while at <= #lines do
        local line = lines[at]:gsub("\r$", "")
        at = at + 1
        if line == "" then break end
        headers[#headers + 1] = line
    end
    while at <= #lines do
        body[#body + 1] = lines[at]:gsub("\r$", "")
        at = at + 1
    end
    return headers, body
end

local function header(headers, name)
    local want = name:lower()
    for _, line in ipairs(headers) do
        local key, value = line:match("^([^:]+):%s*(.+)$")
        if key and key:lower() == want then
            return value
        end
    end
    return nil
end

local function status_of(headers)
    return tonumber((headers[1] or ""):match("^HTTP/[%d%.]+%s+(%d+)")) or 0
end

function Client:answer(lines, payload, retry)
    local headers, body = split_headers(lines)
    local status = status_of(headers)
    local session = header(headers, "Mcp-Session-Id")
    if session then
        self.session = session
    end

    if status == 401 and not retry then
        self:authorize(header(headers, "WWW-Authenticate"), payload)
        return
    end
    if status < 200 or status >= 300 then
        self:fail("server answered " .. tostring(status))
        return
    end
    for _, line in ipairs(body) do
        local data = line:match("^data:%s*(.+)$")
        self:receive(data or line)
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
