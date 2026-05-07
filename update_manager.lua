local M = {}

local MANIFEST_PATH = 'lua\\pasthetic\\manifest.json'
local LOCAL_ROOT = 'lua\\pasthetic\\'
local MANIFEST_URLS = {
    'https://raw.githubusercontent.com/Garagoro/Pastethic/refs/heads/main/manifest.json',
    'https://cdn.jsdelivr.net/gh/Garagoro/Pastethic@main/manifest.json'
}
local DEFAULT_BASE_URLS = {
    'https://raw.githubusercontent.com/Garagoro/Pastethic/refs/heads/main/',
    'https://cdn.jsdelivr.net/gh/Garagoro/Pastethic@main/'
}

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

local function entry_path(path)
    if type(path) ~= 'string' or path == '' then
        return nil
    end

    path = path:gsub('\\', '/')

    if path:find('%.%.', 1, true) ~= nil or path:sub(1, 1) == '/' or path:find(':', 1, true) ~= nil then
        return nil
    end

    return LOCAL_ROOT .. path:gsub('/', '\\')
end

function M.new(deps)
    deps = deps or {}

    local client = deps.client or client
    local json = assert(deps.json or json, 'update_manager: json dependency is required')
    local readfile = deps.readfile or readfile
    local writefile = deps.writefile or writefile
    local logging = deps.logging or {}

    local state = {
        busy = false,
        checked = false,
        update_available = false,
        pending = {},
        manifest = nil,
        manifest_body = nil,
        last_error = nil
    }

    local function log(msg)
        if type(logging.log) == 'function' then
            logging.log(msg)
        elseif client ~= nil and client.log ~= nil then
            client.log('[Pasthetic] ' .. msg)
        end
    end

    local function success(msg)
        if type(logging.success) == 'function' then
            logging.success(msg)
        else
            log(msg)
        end
    end

    local function error_log(msg)
        if type(logging.error) == 'function' then
            logging.error(msg)
        else
            log(msg)
        end
    end

    local function body_preview(body)
        if type(body) ~= 'string' then
            return type(body)
        end

        local preview = body:sub(1, 160):gsub('[\r\n\t]', ' ')

        return ('string len=%d preview=%q'):format(#body, preview)
    end

    local function decode_manifest(body)
        if type(body) ~= 'string' or body == '' then
            return nil, 'empty manifest body: ' .. body_preview(body)
        end

        body = body:gsub('^\239\187\191', ''):gsub('^%s+', '')

        local ok, decoded = pcall(json.decode, body)

        if not ok then
            return nil, ('json decode failed: %s; %s'):format(tostring(decoded), body_preview(body))
        end

        if type(decoded) ~= 'table' then
            return nil, ('manifest root is %s; %s'):format(type(decoded), body_preview(body))
        end

        if type(decoded.files) ~= 'table' then
            return nil, ('manifest files is %s; %s'):format(type(decoded.files), body_preview(body))
        end

        return decoded
    end

    local function http_get(url, callback)
        local ok, http = pcall(require, 'gamesense/http')

        if not ok or type(http) ~= 'table' or type(http.get) ~= 'function' then
            return false
        end

        local request_ok = pcall(http.get, url, function(success_flag, response)
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
                return
            end

            callback(nil, ('%s status=%s %s'):format(tostring(success_flag), tostring(status), body_preview(body)))
        end)

        return request_ok
    end

    local function http_get_first(urls, callback)
        local index = 1
        local last_error = nil

        local function try_next()
            local url = urls[index]

            if url == nil then
                callback(nil, last_error or 'no urls')
                return
            end

            index = index + 1

            local requested = http_get(url, function(body, err)
                if type(body) == 'string' then
                    callback(body, nil, url)
                    return
                end

                last_error = err or ('request failed: ' .. url)
                try_next()
            end)

            if not requested then
                last_error = 'gamesense/http unavailable'
                try_next()
            end
        end

        try_next()

        return true
    end

    local function compare_manifest(manifest)
        local pending = {}

        if type(manifest) ~= 'table' or type(manifest.files) ~= 'table' then
            return pending, false
        end

        for i = 1, #manifest.files do
            local entry = manifest.files[i]
            local local_path = entry_path(entry.path)
            local ok_read, body = false, nil

            if local_path ~= nil and readfile ~= nil then
                ok_read, body = pcall(readfile, local_path)
            end

            if local_path == nil then
                pending[#pending + 1] = { entry = entry, reason = 'bad path' }
            elseif not ok_read or type(body) ~= 'string' then
                pending[#pending + 1] = { entry = entry, reason = 'missing' }
            elseif type(entry.size) == 'number' and #body ~= entry.size then
                pending[#pending + 1] = { entry = entry, reason = 'size' }
            elseif type(entry.checksum) == 'string' and adler32(body) ~= entry.checksum then
                pending[#pending + 1] = { entry = entry, reason = 'checksum' }
            end
        end

        return pending, true
    end

    local function fetch_manifest(callback)
        return http_get_first(MANIFEST_URLS, function(body, err)
            local manifest, decode_error = decode_manifest(body)

            if manifest == nil then
                callback(nil, nil, decode_error or err or 'bad manifest json')
                return
            end

            callback(manifest, body, nil)
        end)
    end

    local function get_base_urls(manifest)
        local list = {}

        if type(manifest.base_urls) == 'table' then
            for i = 1, #manifest.base_urls do
                if type(manifest.base_urls[i]) == 'string' then
                    list[#list + 1] = manifest.base_urls[i]
                end
            end
        end

        if type(manifest.base_url) == 'string' then
            list[#list + 1] = manifest.base_url
        end

        for i = 1, #DEFAULT_BASE_URLS do
            list[#list + 1] = DEFAULT_BASE_URLS[i]
        end

        return list
    end

    local manager = {}

    function manager.has_update()
        return state.update_available and #state.pending > 0
    end

    function manager.is_busy()
        return state.busy
    end

    function manager.get_pending_count()
        return #state.pending
    end

    function manager.check(callback)
        if state.busy then
            error_log('update check is already running')
            return false
        end

        state.busy = true
        state.last_error = nil
        log('checking updates...')

        local started = fetch_manifest(function(manifest, body, err)
            state.busy = false

            if manifest == nil then
                state.checked = true
                state.update_available = false
                state.pending = {}
                state.last_error = err or 'manifest download failed'
                error_log('update check failed: ' .. tostring(state.last_error))

                if callback ~= nil then callback(false, state) end
                return
            end

            local pending, ok = compare_manifest(manifest)

            if not ok then
                state.checked = true
                state.update_available = false
                state.pending = {}
                state.last_error = 'manifest is invalid'
                error_log('update check failed: manifest is invalid')

                if callback ~= nil then callback(false, state) end
                return
            end

            state.checked = true
            state.manifest = manifest
            state.manifest_body = body
            state.pending = pending
            state.update_available = #pending > 0

            if state.update_available then
                log(('update available: %d file(s) differ'):format(#pending))
            else
                success('no updates found')

                if writefile ~= nil and type(body) == 'string' then
                    pcall(writefile, MANIFEST_PATH, body)
                end
            end

            if callback ~= nil then callback(true, state) end
        end)

        if not started then
            state.busy = false
            state.checked = true
            state.update_available = false
            state.pending = {}
            state.last_error = 'gamesense/http unavailable'
            error_log('update check failed: gamesense/http unavailable')

            if callback ~= nil then callback(false, state) end
            return false
        end

        return true
    end

    function manager.download(callback)
        if state.busy then
            error_log('update task is already running')
            return false
        end

        if not manager.has_update() or state.manifest == nil then
            error_log('no update available; run check updates first')
            return false
        end

        if writefile == nil then
            error_log('download update failed: writefile unavailable')
            return false
        end

        state.busy = true

        local files = state.pending
        local manifest = state.manifest
        local base_urls = get_base_urls(manifest)
        local pending_count = #files
        local downloaded, failed = 0, 0

        log(('downloading update: %d file(s)'):format(pending_count))

        local function finish_one(ok)
            if ok then
                downloaded = downloaded + 1
            else
                failed = failed + 1
            end

            pending_count = pending_count - 1

            if pending_count > 0 then
                return
            end

            state.busy = false

            if failed == 0 then
                state.pending = {}
                state.update_available = false

                if type(state.manifest_body) == 'string' then
                    pcall(writefile, MANIFEST_PATH, state.manifest_body)
                end

                success(('update downloaded: %d file(s), reload script'):format(downloaded))
            else
                error_log(('update partially failed: downloaded %d, failed %d'):format(downloaded, failed))
            end

            if callback ~= nil then callback(failed == 0, state) end
        end

        for i = 1, #files do
            local entry = files[i].entry or files[i]
            local local_path = entry_path(entry.path)

            if local_path == nil then
                finish_one(false)
            else
                local urls = {}

                for j = 1, #base_urls do
                    urls[#urls + 1] = base_urls[j] .. entry.path
                end

                local requested = http_get_first(urls, function(body)
                    if type(body) ~= 'string' then
                        finish_one(false)
                        return
                    end

                    if type(entry.size) == 'number' and #body ~= entry.size then
                        finish_one(false)
                        return
                    end

                    if type(entry.checksum) == 'string' and adler32(body) ~= entry.checksum then
                        finish_one(false)
                        return
                    end

                    local ok_write = pcall(writefile, local_path, body)
                    finish_one(ok_write)
                end)

                if not requested then
                    finish_one(false)
                end
            end
        end

        return true
    end

    return manager
end

return M
