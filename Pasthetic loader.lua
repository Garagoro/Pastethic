-- Pasthetic public loader.
-- Downloads the newest generated bundle from GitHub or runs the local root cache.
local PASTHETIC_GIT_URL = 'https://github.com/Garagoro/Pasthetic'
local CACHE_PATH = 'Pasthetic.bundle'

local MANIFEST_URLS = {
    'https://raw.githubusercontent.com/Garagoro/Pasthetic/main/manifest.json',
    'https://raw.githubusercontent.com/Garagoro/Pasthetic/refs/heads/main/manifest.json',
}

local BASE_URLS = {
    'https://raw.githubusercontent.com/Garagoro/Pasthetic/main/',
    'https://raw.githubusercontent.com/Garagoro/Pasthetic/refs/heads/main/',
}

local state = {
    busy = false,
    loaded = false
}
local request_serial = 0

local function log(r, g, b, msg)
    if client ~= nil and client.color_log ~= nil then
        client.color_log(180, 100, 255, '[Pasthetic] \0')
        client.color_log(r or 255, g or 255, b or 255, tostring(msg))
    end
end

local function ok(msg)
    log(100, 220, 100, msg)
end

local function err(msg)
    log(250, 50, 75, msg)
end

local function reinstall_hint()
    err('Redownload the loader from GitHub: ' .. PASTHETIC_GIT_URL)
end

local function tohex32(n)
    local chars = '0123456789abcdef'
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
    if type(path) ~= 'string' then
        return ''
    end

    path = path:gsub('\\', '/')

    return (path:gsub('([^%w%-%._~/])', function(char)
        return ('%%%02X'):format(char:byte())
    end))
end

local function uncached_url(url)
    request_serial = request_serial + 1

    local stamp = request_serial
    if globals ~= nil and type(globals.realtime) == 'function' then
        stamp = math.floor(globals.realtime() * 1000000)
    end

    local separator = url:find('?', 1, true) ~= nil and '&' or '?'
    return url .. separator .. 'pasthetic=' .. tostring(stamp) .. '_' .. tostring(request_serial)
end

local function compare_versions(left, right)
    left = tostring(left or '')
    right = tostring(right or '')

    local left_parts, right_parts = {}, {}

    for part in left:gmatch('%d+') do
        left_parts[#left_parts + 1] = tonumber(part) or 0
    end

    for part in right:gmatch('%d+') do
        right_parts[#right_parts + 1] = tonumber(part) or 0
    end

    for i = 1, math.max(#left_parts, #right_parts) do
        local a = left_parts[i] or 0
        local b = right_parts[i] or 0

        if a ~= b then
            return a > b and 1 or -1
        end
    end

    return 0
end

local function decode_manifest(body)
    if type(body) ~= 'string' or body == '' then
        return nil
    end

    body = body:gsub('^\239\187\191', ''):gsub('^%s+', '')

    if json == nil then
        return nil
    end

    local parser = json.parse or json.decode
    if type(parser) ~= 'function' then
        return nil
    end

    local ok_decode, decoded = pcall(parser, body)
    if not ok_decode or type(decoded) ~= 'table' then
        return nil
    end

    return decoded
end

local function get_bundle_artifact(manifest)
    local artifacts = type(manifest) == 'table' and manifest.artifacts or nil

    if type(artifacts) == 'table' and type(artifacts.bundle) == 'table' then
        return artifacts.bundle
    end

    return nil
end

local function get_manifest_version(manifest)
    local artifact = get_bundle_artifact(manifest)

    if type(artifact) == 'table' and type(artifact.version) == 'string' then
        return artifact.version
    end

    return tostring(type(manifest) == 'table' and manifest.version or '')
end

local function get_base_urls(manifest)
    local urls = {}

    if type(manifest) == 'table' and type(manifest.base_urls) == 'table' then
        for i = 1, #manifest.base_urls do
            if type(manifest.base_urls[i]) == 'string' then
                urls[#urls + 1] = manifest.base_urls[i]
            end
        end
    end

    if type(manifest) == 'table' and type(manifest.base_url) == 'string' then
        urls[#urls + 1] = manifest.base_url
    end

    for i = 1, #BASE_URLS do
        urls[#urls + 1] = BASE_URLS[i]
    end

    return urls
end

local function http_get(url, callback)
    local ok_http, http = pcall(require, 'gamesense/http')

    if not ok_http or type(http) ~= 'table' or type(http.get) ~= 'function' then
        return false
    end

    return pcall(http.get, url, function(success_flag, response)
        local status, body

        if type(success_flag) == 'table' and response == nil then
            response = success_flag
            success_flag = true
        elseif type(success_flag) == 'string' and response == nil then
            body = success_flag
            status = 200
            success_flag = true
        elseif type(success_flag) == 'number' and type(response) == 'string' then
            status = success_flag
            body = response
            success_flag = status == 200
        end

        if type(response) == 'table' then
            status = response.status or response.status_code or response.code
            body = response.body or response.data or response.content or response.text
        elseif type(response) == 'string' and body == nil then
            status = 200
            body = response
        end

        local status_ok = status == nil or status == 200 or status == '200'

        if success_flag and status_ok and type(body) == 'string' then
            callback(body)
        else
            callback(nil, tostring(status))
        end
    end)
end

local function verify_bundle(body, artifact)
    if type(body) ~= 'string' or body == '' then
        return false, 'empty bundle'
    end

    if type(artifact.size) == 'number' and #body ~= artifact.size then
        return false, 'size mismatch'
    end

    if type(artifact.checksum) == 'string' and adler32(body) ~= artifact.checksum then
        return false, 'checksum mismatch'
    end

    return true
end

local function run_bundle(source, label)
    local loader = loadstring or load

    if type(loader) ~= 'function' then
        err('loadstring unavailable')
        return false
    end

    local chunk, load_error = loader(source, '@' .. (label or CACHE_PATH))

    if chunk == nil then
        err('bundle syntax error: ' .. tostring(load_error))
        return false
    end

    _G.__pasthetic_public_loader = true
    _G.__pasthetic_allinone_bootstrap = true

    local ok_run, runtime_error = pcall(chunk)

    _G.__pasthetic_allinone_bootstrap = nil
    _G.__pasthetic_public_loader = nil

    if not ok_run then
        error(runtime_error)
    end

    state.loaded = true
    return true
end

local function load_cached()
    if state.busy then
        return
    end

    if readfile == nil then
        err('readfile unavailable')
        return
    end

    local ok_read, body = pcall(readfile, CACHE_PATH)

    if not ok_read or type(body) ~= 'string' or body == '' then
        err('local cache is missing; press Newest first')
        return
    end

    ok('loading cached bundle')
    run_bundle(body, CACHE_PATH)
end

local function fetch_best_manifest(callback)
    local index = 1
    local best_manifest = nil
    local best_body = nil
    local best_url = nil
    local last_error = nil

    local function next_url()
        local url = MANIFEST_URLS[index]

        if url == nil then
            callback(best_manifest, best_body, best_url, last_error)
            return
        end

        index = index + 1

        local requested = http_get(uncached_url(url), function(body, error_text)
            local manifest = decode_manifest(body)
            local artifact = get_bundle_artifact(manifest)

            if manifest ~= nil and artifact ~= nil then
                if best_manifest == nil
                    or compare_versions(get_manifest_version(manifest), get_manifest_version(best_manifest)) > 0
                then
                    best_manifest = manifest
                    best_body = body
                    best_url = url
                end
            elseif manifest ~= nil then
                last_error = 'manifest has no bundle artifact'
            else
                last_error = error_text or 'invalid manifest'
            end

            next_url()
        end)

        if not requested then
            last_error = 'gamesense/http unavailable'
            next_url()
        end
    end

    next_url()
end

local function write_cache(body, artifact)
    if writefile == nil then
        err('writefile unavailable; running without cache')
        return false
    end

    local ok_write = pcall(writefile, CACHE_PATH, body)

    if not ok_write then
        err('cache write failed; running downloaded bundle in memory')
        return false
    end

    if readfile ~= nil then
        local ok_read, cached = pcall(readfile, CACHE_PATH)
        local ok_verify = ok_read and verify_bundle(cached, artifact)

        if not ok_verify then
            err('cache verification failed; running downloaded bundle in memory')
            return false
        end
    end

    return true
end

local function fetch_bundle(manifest, artifact)
    local base_urls = get_base_urls(manifest)
    local remote_path = url_path(artifact.path)
    local index = 1
    local last_error = nil

    local function next_url()
        local base_url = base_urls[index]

        if base_url == nil then
            state.busy = false
            err('bundle download failed: ' .. tostring(last_error or 'all urls failed'))
            reinstall_hint()
            return
        end

        index = index + 1

        local requested = http_get(uncached_url(base_url .. remote_path), function(body, error_text)
            local valid, verify_error = verify_bundle(body, artifact)

            if valid then
                write_cache(body, artifact)
                state.busy = false
                ok('bundle loaded: ' .. tostring(artifact.version or 'unknown'))
                run_bundle(body, artifact.path or CACHE_PATH)
            else
                last_error = verify_error or error_text
                next_url()
            end
        end)

        if not requested then
            last_error = 'gamesense/http unavailable'
            next_url()
        end
    end

    next_url()
end

local function load_newest()
    if state.busy then
        return
    end

    state.busy = true
    log(255, 255, 255, 'checking newest bundle...')

    fetch_best_manifest(function(manifest, body, url, error_text)
        local artifact = get_bundle_artifact(manifest)

        if artifact == nil then
            state.busy = false
            err('manifest download failed: ' .. tostring(error_text or 'invalid manifest'))
            reinstall_hint()
            return
        end

        log(255, 255, 255, 'downloading bundle: ' .. tostring(artifact.version or 'unknown'))
        fetch_bundle(manifest, artifact)
    end)
end

ui.new_button('CONFIG', 'Lua', 'Pasthetic: Newest', load_newest)
ui.new_button('CONFIG', 'Lua', 'Pasthetic: Local cache', load_cached)

log(255, 255, 255, 'loader ready — use Newest or Local cache')
