local M = {}

local REDIRECT = "http://localhost/callback"
local TIMEOUT = 30

local function fetch(request, done)
    request.timeout = TIMEOUT
    uji.http.request(request, function(response, err)
        if not response then
            done(nil, "request failed: " .. err)
            return
        end
        local ok, parsed = pcall(uji.json.decode, response.body)
        if not ok or type(parsed) ~= "table" then
            done(nil, "response was not JSON")
        else
            done(parsed)
        end
    end)
end

local function get(url, done)
    fetch({ url = url }, done)
end

local function post(url, payload, done)
    fetch({
        url = url,
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        body = uji.json.encode(payload),
    }, done)
end

local function form(url, fields, done)
    local parts = {}
    for key, value in pairs(fields) do
        parts[#parts + 1] = key .. "=" .. tostring(value):gsub("[^%w%-%._~]", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
    end
    fetch({
        url = url,
        method = "POST",
        headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
        body = table.concat(parts, "&"),
    }, done)
end

local function shell(command)
    local handle = io.popen(command)
    if not handle then return nil end
    local out = handle:read("*a")
    handle:close()
    return (out:gsub("%s+$", ""))
end

-- Lua has no crypto. openssl is present everywhere uji runs, and the verifier
-- never leaves this process.
local function pkce()
    local verifier = shell("openssl rand -base64 60 | tr -d '=+/\\n' | cut -c1-64")
    if not verifier or verifier == "" then return nil end
    local challenge = shell(string.format(
        "printf %%s %q | openssl dgst -sha256 -binary | openssl base64 | tr '+/' '-_' | tr -d '=\\n'",
        verifier))
    if not challenge or challenge == "" then return nil end
    return verifier, challenge
end

local function metadata_url(challenge, url)
    local found = challenge and challenge:match('resource_metadata="([^"]+)"')
    if found then return found end
    local origin = url:match("^(https?://[^/]+)")
    return origin and (origin .. "/.well-known/oauth-protected-resource")
end

local function query(url, key)
    return url:match("[?&]" .. key .. "=([^&#]+)")
end

--- Walk discovery, register, authorize and exchange. `done(token, err)`.
function M.acquire(name, url, challenge_header, done)
    local resource = metadata_url(challenge_header, url)
    if not resource then
        done(nil, "server wants authorization but advertised no metadata")
        return
    end
    get(resource, function(meta, err)
        if not meta then
            done(nil, err or "could not read resource metadata")
            return
        end
        local issuer = meta.authorization_servers and meta.authorization_servers[1]
        if not issuer then
            done(nil, "resource metadata named no authorization server")
            return
        end
        get(issuer .. "/.well-known/oauth-authorization-server", function(server, server_err)
            if not server then
                done(nil, server_err or "could not read authorization server metadata")
                return
            end
            M.register(name, server, done)
        end)
    end)
end

function M.register(name, server, done)
    if not server.registration_endpoint then
        done(nil, "server has no registration endpoint and uji has no client id for it")
        return
    end
    post(server.registration_endpoint, {
        client_name = "uji",
        redirect_uris = { REDIRECT },
        grant_types = { "authorization_code", "refresh_token" },
        response_types = { "code" },
        token_endpoint_auth_method = "none",
    }, function(client, err)
        if not client or not client.client_id then
            done(nil, err or "client registration was refused")
            return
        end
        M.authorize(name, server, client, done)
    end)
end

function M.authorize(name, server, client, done)
    local verifier, challenge = pkce()
    if not verifier then
        done(nil, "could not generate a PKCE challenge (is openssl installed?)")
        return
    end
    local target = string.format(
        "%s?response_type=code&client_id=%s&redirect_uri=%s&code_challenge=%s&code_challenge_method=S256",
        server.authorization_endpoint, client.client_id, REDIRECT, challenge)

    uji.notify(name .. ": opening your browser to sign in")
    uji.ui.exec({ "sh", "-c", 'if command -v xdg-open >/dev/null; then xdg-open "$1"; else open "$1"; fi', "sh", target })
    uji.ui.prompt({
        title = "Paste the URL your browser was redirected to",
    }, function(pasted)
        if not pasted or pasted == "" then
            done(nil, "sign-in cancelled")
            return
        end
        local code = query(pasted, "code")
        if not code then
            done(nil, "no authorization code in that URL")
            return
        end
        form(server.token_endpoint, {
            grant_type = "authorization_code",
            code = code,
            redirect_uri = REDIRECT,
            client_id = client.client_id,
            code_verifier = verifier,
        }, function(tokens, err)
            if not tokens or not tokens.access_token then
                done(nil, err or "token exchange failed")
                return
            end
            done(tokens.access_token)
        end)
    end)
end

return M
