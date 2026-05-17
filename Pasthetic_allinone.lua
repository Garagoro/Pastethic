-- Pasthetic all-in-one bootstrap.
-- This small file downloads and runs the generated bundle from GitHub.
local BOOTSTRAP_VERSION = "2026.05.17-10"
local CACHE_PATH = "pasthetic\\Pasthetic_allinone.cache.lua"
local MANIFEST_URLS = {
    "https://raw.githubusercontent.com/Garagoro/Pasthetic/refs/heads/main/manifest.json",
    "https://raw.githubusercontent.com/Garagoro/Pasthetic/main/manifest.json",
}
local BASE_URLS = {
    "https://raw.githubusercontent.com/Garagoro/Pasthetic/refs/heads/main/",
    "https://raw.githubusercontent.com/Garagoro/Pasthetic/main/",
}

local function log(r, g, b, msg)
    if client ~= nil and client.color_log ~= nil then
        client.color_log(180, 100, 255, "[Pasthetic] \0")
        client.color_log(r or 255, g or 255, b or 255, msg)
    end
end

local function tohex32(n)
    local chars = "0123456789abcdef"
    local out = {}
    for i = 8, 1, -1 do
        local d = n % 16
        out[i] = chars:sub(d + 1, d + 1)
        n = (n - d) / 16
    end
    return table.concat(out)
end

local function adler32(data)
    local a, b = 1, 0
    for i = 1, #data do
        a = (a + data:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return tohex32((b * 65536 + a) % 4294967296)
end

local function url_path(path)
    if type(path) ~= "string" then return "" end
    path = path:gsub("\\", "/")
    return (path:gsub("([^%w%-%._~/])", function(char)
        return ("%%%02X"):format(char:byte())
    end))
end

local function decode_manifest(body)
    if type(body) ~= "string" or body == "" then return nil end
    body = body:gsub("^\239\187\191", ""):gsub("^%s+", "")
    local parser = json ~= nil and (json.parse or json.decode) or nil
    if type(parser) ~= "function" then return nil end
    local ok, decoded = pcall(parser, body)
    if not ok or type(decoded) ~= "table" then return nil end
    return decoded
end

local function compare_versions(left, right)
    left = tostring(left or "")
    right = tostring(right or "")
    local a, b = {}, {}
    for part in left:gmatch("%d+") do a[#a + 1] = tonumber(part) or 0 end
    for part in right:gmatch("%d+") do b[#b + 1] = tonumber(part) or 0 end
    for i = 1, math.max(#a, #b) do
        local av, bv = a[i] or 0, b[i] or 0
        if av ~= bv then return av > bv and 1 or -1 end
    end
    return 0
end

local function get_artifact(manifest)
    local artifact = manifest ~= nil and manifest.artifacts ~= nil and manifest.artifacts.allinone or nil
    if type(artifact) == "table" and type(artifact.path) == "string" then
        return artifact
    end
    return nil
end

local function http_get(url, callback)
    local ok, http = pcall(require, "gamesense/http")
    if not ok or type(http) ~= "table" or type(http.get) ~= "function" then
        return false
    end
    return pcall(http.get, url, function(success, response)
        local status, body
        if type(success) == "table" and response == nil then
            response = success
            success = true
        elseif type(success) == "string" and response == nil then
            body = success
            status = 200
            success = true
        end
        if type(response) == "table" then
            status = response.status or response.status_code or response.code
            body = response.body or response.data or response.content or response.text
        elseif type(response) == "string" and body == nil then
            status = 200
            body = response
        end
        callback(success and (status == nil or status == 200 or status == "200") and body or nil)
    end)
end

local function run_bundle(source, label)
    local loader = loadstring or load
    if type(loader) ~= "function" then
        log(250, 50, 75, "loadstring unavailable")
        return false
    end
    local chunk, err = loader(source, "@" .. (label or "Pasthetic_allinone_bundle.lua"))
    if chunk == nil then
        log(250, 50, 75, "bundle syntax error: " .. tostring(err))
        return false
    end
    _G.__pasthetic_allinone_bootstrap = true
    local ok, runtime_err = pcall(chunk)
    _G.__pasthetic_allinone_bootstrap = nil
    if not ok then
        error(runtime_err)
    end
    return true
end

local function run_cache(reason)
    if readfile == nil then
        log(250, 50, 75, reason .. "; no cached bundle")
        return
    end
    local ok, cached = pcall(readfile, CACHE_PATH)
    if ok and type(cached) == "string" and cached ~= "" then
        log(255, 255, 255, reason .. "; loading cached all-in-one")
        run_bundle(cached, CACHE_PATH)
    else
        log(250, 50, 75, reason .. "; no cached bundle")
    end
end

local function get_base_urls(manifest)
    local urls = {}
    if type(manifest) == "table" and type(manifest.base_urls) == "table" then
        for i = 1, #manifest.base_urls do
            if type(manifest.base_urls[i]) == "string" then
                urls[#urls + 1] = manifest.base_urls[i]
            end
        end
    end
    if type(manifest) == "table" and type(manifest.base_url) == "string" then
        urls[#urls + 1] = manifest.base_url
    end
    for i = 1, #BASE_URLS do urls[#urls + 1] = BASE_URLS[i] end
    return urls
end

local function fetch_best_manifest(callback)
    local index = 1
    local best_manifest, best_body
    local function next_url()
        local url = MANIFEST_URLS[index]
        if url == nil then
            callback(best_manifest, best_body)
            return
        end
        index = index + 1
        if not http_get(url, function(body)
            local manifest = decode_manifest(body)
            local artifact = get_artifact(manifest)
            local best_artifact = get_artifact(best_manifest)
            if artifact ~= nil and (
                best_artifact == nil or compare_versions(artifact.version, best_artifact.version) > 0
            ) then
                best_manifest = manifest
                best_body = body
            end
            next_url()
        end) then
            next_url()
        end
    end
    next_url()
end

local function fetch_bundle(manifest, artifact)
    local base_urls = get_base_urls(manifest)
    local remote_path = url_path(artifact.path)
    local index = 1
    local function next_url()
        local base_url = base_urls[index]
        if base_url == nil then
            run_cache("bundle download failed")
            return
        end
        index = index + 1
        if not http_get(base_url .. remote_path, function(body)
            if type(body) == "string"
                and (type(artifact.size) ~= "number" or #body == artifact.size)
                and (type(artifact.checksum) ~= "string" or adler32(body) == artifact.checksum)
            then
                if writefile ~= nil then pcall(writefile, CACHE_PATH, body) end
                run_bundle(body, artifact.path)
            else
                next_url()
            end
        end) then
            next_url()
        end
    end
    next_url()
end

log(255, 255, 255, "loading all-in-one...")
fetch_best_manifest(function(manifest)
    local artifact = get_artifact(manifest)
    if artifact == nil then
        run_cache("manifest download failed")
        return
    end
    fetch_bundle(manifest, artifact)
end)