-- Pasthetic entrypoint: fallback module loader + app wiring.
-- Feature/runtime code lives in pasthetic\*.lua modules.
local PASTHETIC_GIT_URL = 'https://github.com/Garagoro/Pasthetic'

local function log_loader_reinstall_hint()
    if client ~= nil and client.color_log ~= nil then
        client.color_log(250, 50, 75, '[Pasthetic] \0')
        client.color_log(255, 255, 255, 'Redownload the loader from GitHub: ' .. PASTHETIC_GIT_URL)
    end
end

local function can_read_file(path)
    if readfile == nil then
        return false
    end

    local ok, result = pcall(readfile, path)
    return ok and type(result) == 'string'
end

local LOCAL_PREFIX = can_read_file('pasthetic\\core.lua') and '' or (can_read_file('pasthetic\\pasthetic\\core.lua') and 'pasthetic\\' or '')

local function local_path(path)
    if LOCAL_PREFIX == '' or type(path) ~= 'string' or path == '' then
        return path
    end

    return LOCAL_PREFIX .. path
end

local function require_pasthetic_module(name)
    if package ~= nil and package.loaded ~= nil then
        package.loaded[name] = nil
    end

    local ok, result = pcall(require, name)

    if ok then
        return result
    end

    if readfile == nil or loadstring == nil then
        log_loader_reinstall_hint()
        error(result)
    end

    local path = name:gsub('/', '\\') .. '.lua'
    local source = readfile(local_path(path))

    if source == nil then
        local nested_path = 'pasthetic\\' .. path
        source = readfile(local_path(nested_path))

        if source ~= nil then
            path = nested_path
        end
    end

    if source == nil then
        log_loader_reinstall_hint()
        error(result)
    end

    local chunk, load_error = loadstring(source, '@' .. path)

    if chunk == nil then
        log_loader_reinstall_hint()
        error(load_error)
    end

    ok, result = pcall(chunk)

    if not ok then
        log_loader_reinstall_hint()
        error(result)
    end

    package.loaded[name] = result

    return result
end

local ffi = require 'ffi'
local vector = require 'vector'
local base64 = require 'gamesense/base64'
local clipboard = require 'gamesense/clipboard'
local chat = require 'gamesense/chat'
local localize = require 'gamesense/localize'
local c_entity = require 'gamesense/entity'
local csgo_weapons = require 'gamesense/csgo_weapons'

-- ====================================================================
-- Update manager (inlined — handles bootstrap install and auto-update)
-- ====================================================================

local MANIFEST_URLS = {
    'https://raw.githubusercontent.com/Garagoro/Pasthetic/main/manifest.json',
    'https://raw.githubusercontent.com/Garagoro/Pasthetic/refs/heads/main/manifest.json',
}
local BASE_URLS = {
    'https://raw.githubusercontent.com/Garagoro/Pasthetic/main/',
    'https://raw.githubusercontent.com/Garagoro/Pasthetic/refs/heads/main/',
}
local MANIFEST_PATH = local_path('manifest.json')

local _create_dir
do
    pcall(ffi.cdef, 'int __stdcall CreateDirectoryA(const char*, void*);')
    local ok, k32 = pcall(ffi.load, 'kernel32')
    if ok and k32 ~= nil then
        _create_dir = function(path) pcall(k32.CreateDirectoryA, path, nil) end
    end
end
local function create_dir(path)
    if _create_dir ~= nil and type(path) == 'string' and path ~= '' then _create_dir(path) end
end

local function create_parent_dirs(path)
    if type(path) ~= 'string' then return end

    path = path:gsub('\\', '/')

    local current = ''

    for part in path:gmatch('([^/]+)/') do
        current = current == '' and part or (current .. '\\' .. part)
        create_dir(current)
    end
end

local function um_log(msg)
    client.color_log(180, 100, 255, '[Pasthetic] \0')
    client.color_log(255, 255, 255, msg)
end

local function um_success(msg)
    client.color_log(180, 100, 255, '[Pasthetic] \0')
    client.color_log(100, 220, 100, msg)
end

local function um_error(msg)
    client.color_log(250, 50, 75, '[Pasthetic] \0')
    client.color_log(255, 255, 255, msg)
end

local function um_git_error(msg)
    um_error(msg)
    log_loader_reinstall_hint()
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

local function entry_path(path)
    if type(path) ~= 'string' or path == '' then return nil end
    path = path:gsub('\\', '/')
    if path:find('%.%.', 1, true) ~= nil or path:sub(1, 1) == '/' or path:find(':', 1, true) ~= nil then
        return nil
    end
    return path:gsub('/', '\\')
end

local function url_path(path)
    if type(path) ~= 'string' then return '' end

    path = path:gsub('\\', '/')

    return (path:gsub('([^%w%-%._~/])', function(char)
        return ('%%%02X'):format(char:byte())
    end))
end

local function verify_file_body(path, expected_size, expected_checksum)
    if readfile == nil or type(path) ~= 'string' then
        return false
    end

    local ok, body = pcall(readfile, path)
    if not ok or type(body) ~= 'string' then
        return false
    end

    if type(expected_size) == 'number' and #body ~= expected_size then
        return false
    end

    if type(expected_checksum) == 'string' and adler32(body) ~= expected_checksum then
        return false
    end

    return true
end

local function add_unique_path(paths, seen, path)
    if type(path) ~= 'string' or path == '' then
        return
    end

    path = path:gsub('/', '\\')

    if seen[path] then
        return
    end

    seen[path] = true
    paths[#paths + 1] = path
end

local function get_update_target_paths(local_entry_path)
    if __pasthetic_allinone ~= true then
        return { local_path(local_entry_path) }
    end

    local paths, seen = {}, {}
    local target_name = __pasthetic_allinone_target_path or local_entry_path

    add_unique_path(paths, seen, target_name)
    add_unique_path(paths, seen, local_entry_path)
    add_unique_path(paths, seen, '.\\' .. local_entry_path)
    add_unique_path(paths, seen, '..\\' .. local_entry_path)
    add_unique_path(paths, seen, 'pasthetic\\' .. local_entry_path)

    return paths
end

local function write_update_targets(paths, body, expected_size, expected_checksum)
    local wrote = 0

    for i = 1, #paths do
        local target_path = paths[i]
        create_parent_dirs(target_path)

        local ok_write = writefile ~= nil and pcall(writefile, target_path, body)

        if ok_write and verify_file_body(target_path, expected_size, expected_checksum) then
            wrote = wrote + 1
        end
    end

    return wrote > 0, wrote
end

local function should_skip_manifest_entry(entry)
    if type(entry) ~= 'table' then
        return true
    end

    local path = entry.path
    if type(path) ~= 'string' then
        return true
    end

    path = path:gsub('\\', '/')
    return path == 'Pasthetic allinone.lua'
        or path == 'Pasthetic_allinone.lua'
        or path == 'Pasthetic_allinone_bundle.lua'
        or path:match('/%.gitkeep$') ~= nil
        or (type(entry.size) == 'number' and entry.size == 0)
end

local function um_http_get(url, callback)
    local ok, http = pcall(require, 'gamesense/http')
    if not ok or type(http) ~= 'table' or type(http.get) ~= 'function' then
        return false
    end
    local req_ok = pcall(http.get, url, function(success_flag, response)
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
    return req_ok
end

local function um_http_get_first(urls, callback)
    local index = 1
    local last_err = nil
    local function try_next()
        local url = urls[index]
        if url == nil then callback(nil, last_err or 'all urls failed') return end
        index = index + 1
        local ok = um_http_get(url, function(body, err)
            if type(body) == 'string' then callback(body, nil, url)
            else last_err = err; try_next() end
        end)
        if not ok then last_err = 'gamesense/http unavailable'; try_next() end
    end
    try_next()
    return true
end

local function decode_manifest(body)
    if type(body) ~= 'string' or body == '' then return nil, 'empty body' end
    body = body:gsub('^\239\187\191', ''):gsub('^%s+', '')
    local parser = json.parse or json.decode
    if type(parser) ~= 'function' then return nil, 'json parser unavailable' end
    local ok, decoded = pcall(parser, body)
    if not ok then return nil, 'json decode failed: ' .. tostring(decoded) end
    if type(decoded) ~= 'table' or type(decoded.files) ~= 'table' then
        return nil, 'invalid manifest structure'
    end
    return decoded
end

local function compare_version_strings(left, right)
    left = tostring(left or '')
    right = tostring(right or '')

    local left_parts, right_parts = {}, {}

    for part in left:gmatch('%d+') do
        left_parts[#left_parts + 1] = tonumber(part) or 0
    end

    for part in right:gmatch('%d+') do
        right_parts[#right_parts + 1] = tonumber(part) or 0
    end

    local count = math.max(#left_parts, #right_parts)

    for i = 1, count do
        local a = left_parts[i] or 0
        local b = right_parts[i] or 0

        if a ~= b then
            return a > b and 1 or -1
        end
    end

    return 0
end

local function get_allinone_manifest_entry(manifest)
    if type(manifest) ~= 'table' then
        return nil
    end

    local artifacts = manifest.artifacts
    if type(artifacts) == 'table' and type(artifacts.allinone) == 'table' then
        return artifacts.allinone
    end

    if type(manifest.files) == 'table' then
        for i = 1, #manifest.files do
            local entry = manifest.files[i]
            if type(entry) == 'table'
                and (entry.path == 'Pasthetic_allinone.lua' or entry.path == 'Pasthetic allinone.lua')
            then
                return entry
            end
        end
    end

    return nil
end

local function get_manifest_sort_version(manifest)
    local entry = get_allinone_manifest_entry(manifest)

    if type(entry) == 'table' and type(entry.version) == 'string' then
        return entry.version
    end

    return tostring(manifest ~= nil and manifest.version or '')
end

local function um_http_get_best_manifest(callback)
    local index = 1
    local last_err = nil
    local best_body, best_manifest, best_url

    local function try_next()
        local url = MANIFEST_URLS[index]

        if url == nil then
            if best_body ~= nil then
                callback(best_body, nil, best_url)
            else
                callback(nil, last_err or 'all urls failed')
            end

            return
        end

        index = index + 1

        local ok = um_http_get(url, function(body, err)
            if type(body) == 'string' then
                local manifest = decode_manifest(body)

                if manifest ~= nil then
                    if best_manifest == nil
                        or compare_version_strings(
                            get_manifest_sort_version(manifest),
                            get_manifest_sort_version(best_manifest)
                        ) > 0
                    then
                        best_body = body
                        best_manifest = manifest
                        best_url = url
                    end
                else
                    last_err = err
                end
            else
                last_err = err
            end

            try_next()
        end)

        if not ok then
            last_err = 'gamesense/http unavailable'
            try_next()
        end
    end

    try_next()
    return true
end

local function compare_allinone_manifest(manifest)
    local entry = get_allinone_manifest_entry(manifest)

    if type(entry) ~= 'table' then
        return {}, false
    end

    local local_entry_path = entry_path(__pasthetic_allinone_target_path or entry.path)
    local ok_read, body = false, nil

    if local_entry_path ~= nil and readfile ~= nil then
        ok_read, body = pcall(readfile, local_entry_path)
    end

    if local_entry_path == nil then
        return { { entry = entry, reason = 'bad path' } }, true
    elseif not ok_read or type(body) ~= 'string' then
        return { { entry = entry, reason = 'missing' } }, true
    elseif type(entry.size) == 'number' and #body ~= entry.size then
        return { { entry = entry, reason = 'size' } }, true
    elseif type(entry.checksum) == 'string' and adler32(body) ~= entry.checksum then
        return { { entry = entry, reason = 'checksum' } }, true
    end

    return {}, true
end

local function compare_manifest(manifest)
    if __pasthetic_allinone == true then
        return compare_allinone_manifest(manifest)
    end

    local pending = {}
    if type(manifest) ~= 'table' or type(manifest.files) ~= 'table' then
        return pending, false
    end
    for i = 1, #manifest.files do
        local entry = manifest.files[i]
        if not should_skip_manifest_entry(entry) then
            local local_entry_path = entry_path(entry.path)
            local ok_read, body = false, nil
            if local_entry_path ~= nil and readfile ~= nil then
                ok_read, body = pcall(readfile, local_path(local_entry_path))
            end
            if local_entry_path == nil then
                pending[#pending + 1] = { entry = entry, reason = 'bad path' }
            elseif not ok_read or type(body) ~= 'string' then
                pending[#pending + 1] = { entry = entry, reason = 'missing' }
            elseif type(entry.size) == 'number' and #body ~= entry.size then
                pending[#pending + 1] = { entry = entry, reason = 'size' }
            elseif type(entry.checksum) == 'string' and adler32(body) ~= entry.checksum then
                pending[#pending + 1] = { entry = entry, reason = 'checksum' }
            end
        end
    end
    return pending, true
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
    for i = 1, #BASE_URLS do
        list[#list + 1] = BASE_URLS[i]
    end
    return list
end

local function reload_active_scripts_after_update()
    if client == nil or type(client.reload_active_scripts) ~= 'function' then
        return false
    end

    local function reload()
        pcall(client.reload_active_scripts)
    end

    if type(client.delay_call) == 'function' then
        client.delay_call(1.0, reload)
    else
        reload()
    end

    return true
end

local function cache_manifest(body)
    if __pasthetic_allinone == true then
        return
    end

    if writefile ~= nil and type(body) == 'string' then
        pcall(writefile, MANIFEST_PATH, body)
    end
end

local um_state = {
    busy            = false,
    update_available = false,
    pending         = {},
    manifest        = nil,
    manifest_body   = nil,
}

local update_manager = {}

function update_manager.has_update()
    return um_state.update_available and #um_state.pending > 0
end

function update_manager.is_busy()
    return um_state.busy
end

local function format_pending_files(pending)
    local names = {}

    for i = 1, #pending do
        local entry = pending[i].entry or pending[i]
        if type(entry) == 'table' and type(entry.path) == 'string' then
            names[#names + 1] = entry.path
        end
    end

    if #names == 0 then
        return ''
    end

    return ' (' .. table.concat(names, ', ') .. ')'
end

function update_manager.check(callback)
    if um_state.busy then
        um_error('update check is already running')
        if callback ~= nil then callback(false) end
        return false
    end
    um_state.busy = true
    um_log('checking updates...')

    local started = um_http_get_best_manifest(function(body, err)
        local manifest, decode_err = decode_manifest(body)

        if manifest == nil then
            um_state.busy = false
            um_state.update_available = false
            um_state.pending = {}
            um_git_error('update check failed: ' .. tostring(decode_err or err or 'manifest download failed'))
            if callback ~= nil then callback(false) end
            return
        end

        local pending, ok = compare_manifest(manifest)

        if not ok then
            um_state.busy = false
            um_state.update_available = false
            um_state.pending = {}
            um_git_error('update check failed: manifest is invalid')
            if callback ~= nil then callback(false) end
            return
        end

        um_state.busy = false
        um_state.manifest = manifest
        um_state.manifest_body = body
        um_state.pending = pending
        um_state.update_available = #pending > 0

        if um_state.update_available then
            if __pasthetic_allinone == true then
                local artifact = get_allinone_manifest_entry(manifest)
                local current_version = tostring(__pasthetic_allinone_version or 'unknown')
                local remote_version = artifact ~= nil and tostring(artifact.version or 'unknown') or 'unknown'

                if current_version ~= remote_version then
                    um_log(('all-in-one update available: %s -> %s'):format(current_version, remote_version))
                else
                    um_log('all-in-one update available')
                end
            else
                um_log(('%d file(s) need update%s'):format(#pending, format_pending_files(pending)))
            end
        else
            um_success(__pasthetic_allinone == true and 'all-in-one up to date' or 'all files up to date')
            cache_manifest(body)
        end

        if callback ~= nil then callback(true) end
    end)

    if not started then
        um_state.busy = false
        um_state.update_available = false
        um_state.pending = {}
        um_git_error('update check failed: gamesense/http unavailable')
        if callback ~= nil then callback(false) end
        return false
    end

    return true
end

function update_manager.download(callback)
    if um_state.busy then
        um_error('download is already running')
        return false
    end

    if not update_manager.has_update() or um_state.manifest == nil then
        um_error('nothing to download; run check first')
        return false
    end

    if writefile == nil then
        um_git_error('download failed: writefile unavailable')
        return false
    end

    um_state.busy = true

    local files     = um_state.pending
    local manifest  = um_state.manifest
    local base_urls = get_base_urls(manifest)
    local remaining = #files
    local downloaded, failed = 0, 0

    um_log(('downloading %d file(s)...'):format(remaining))

    local function finish_one(ok)
        if ok then downloaded = downloaded + 1 else failed = failed + 1 end
        remaining = remaining - 1
        if remaining > 0 then return end

        um_state.busy = false

        if failed == 0 then
            um_state.pending = {}
            um_state.update_available = false
            if type(um_state.manifest_body) == 'string' then
                cache_manifest(um_state.manifest_body)
            end
            um_success(
                __pasthetic_allinone == true
                    and 'all-in-one updated — reloading active scripts...'
                    or ('%d file(s) updated — reloading active scripts...'):format(downloaded)
            )

            if not reload_active_scripts_after_update() then
                um_log('reload active scripts manually to apply')
            end
        else
            um_git_error(('download partially failed: %d ok, %d failed'):format(downloaded, failed))
        end

        if callback ~= nil then callback(failed == 0) end
    end

    for i = 1, #files do
        local entry     = files[i].entry or files[i]
        if should_skip_manifest_entry(entry) then
            finish_one(true)
        else
            local local_entry_path = entry_path(entry.path)
            if local_entry_path == nil then
                finish_one(false)
            else
                local target_paths = get_update_target_paths(local_entry_path)
                local remote_path = url_path(entry.path)
                local urls = {}
                for j = 1, #base_urls do
                    urls[#urls + 1] = base_urls[j] .. remote_path
                end
                local requested = um_http_get_first(urls, function(file_body)
                    if type(file_body) ~= 'string' then finish_one(false) return end
                    if type(entry.size) == 'number' and #file_body ~= entry.size then finish_one(false) return end
                    if type(entry.checksum) == 'string' and adler32(file_body) ~= entry.checksum then finish_one(false) return end
                    local ok_write = write_update_targets(target_paths, file_body, entry.size, entry.checksum)
                    finish_one(ok_write)
                end)
                if not requested then finish_one(false) end
            end
        end
    end

    return true
end

-- ====================================================================
-- Bootstrap: if modules are missing show download button and stop
-- ====================================================================

do
    local installed = __pasthetic_allinone == true or (readfile ~= nil and (function()
        local ok, result = pcall(readfile, local_path('pasthetic\\core.lua'))
        return ok and type(result) == 'string'
    end)())

    if not installed then
        log_loader_reinstall_hint()

        ui.new_button('CONFIG', 'Lua', 'Download Pasthetic modules', function()
            if um_state.busy then return end
            update_manager.check(function(ok)
                if not ok or not update_manager.has_update() then
                    if ok then um_log('nothing to download') end
                    return
                end
                update_manager.download()
            end)
        end)
        return
    end
end

-- ====================================================================
-- Module loading
-- ====================================================================

local core = require_pasthetic_module 'pasthetic/core'
local pasthetic_constants = core.constants
local const = core.static_data
local text_fmt = core.text_fmt
local pasthetic_localdb = require_pasthetic_module 'pasthetic/localdb'
local pasthetic_config_system = require_pasthetic_module 'pasthetic/config_system'
local pasthetic_utils = require_pasthetic_module 'pasthetic/utils'
local event_system = require_pasthetic_module 'pasthetic/event_system'
local pasthetic_ui_overrides = require_pasthetic_module 'pasthetic/ui_overrides'
local pasthetic_menu_logic = require_pasthetic_module 'pasthetic/menu_logic'
local pasthetic_software = require_pasthetic_module 'pasthetic/software'
local pasthetic_text_anims = require_pasthetic_module 'pasthetic/text_anims'
local pasthetic_localplayer = require_pasthetic_module 'pasthetic/localplayer'
local pasthetic_statement = require_pasthetic_module 'pasthetic/statement'
local pasthetic_engine_interfaces = require_pasthetic_module 'pasthetic/engine_interfaces'
local pasthetic_exploit = require_pasthetic_module 'pasthetic/exploit'
local pasthetic_menu = require_pasthetic_module 'pasthetic/menu'
local pasthetic_windows = require_pasthetic_module 'pasthetic/windows'
local pasthetic_external_config_ref = require_pasthetic_module 'pasthetic/external_config_ref'
local pasthetic_diagnostics = require_pasthetic_module 'pasthetic/diagnostics'
local pasthetic_resource_builder = require_pasthetic_module 'pasthetic/resource_builder'
local pasthetic_config_controller = require_pasthetic_module 'pasthetic/config_controller'
local pasthetic_colorskinscsgo = require_pasthetic_module 'pasthetic/colorskinscsgo'
local pasthetic_dormant = require_pasthetic_module 'pasthetic/dormant'
local pasthetic_runtime_modules = require_pasthetic_module 'pasthetic/runtime_modules'

local contains = core.contains

local script = core.new_script({
    user_name = _USER_NAME
})

local function start_optional_module(label, module, ...)
    if module == nil or type(module.start) ~= 'function' then
        return nil
    end

    local ok, result = pcall(module.start, ...)

    if not ok then
        client.color_log(250, 50, 75, '[Pasthetic] \0')
        client.color_log(255, 255, 255, 'failed to start ' .. label .. ': ' .. tostring(result))
        return nil
    end

    return result
end

start_optional_module('colorskinscsgo', pasthetic_colorskinscsgo)

local color = core.new_color({
    ffi = ffi
})

local motion = core.new_motion({
    globals = globals
})

local utils = pasthetic_utils.new({
    ffi = ffi,
    client = client,
    entity = entity,
    globals = globals
})

local ilocalize = pasthetic_engine_interfaces.new_ilocalize({
    vtable_bind = vtable_bind
})

local surface = pasthetic_engine_interfaces.new_surface({
    ffi = ffi,
    vtable_bind = vtable_bind,
    ilocalize = ilocalize
})

local software = pasthetic_software.new({
    ui = ui,
    utils = utils
})

local ui_callback = core.new_ui_callback({
    ui = ui,
    contains = contains
})

local ragebot = pasthetic_ui_overrides.new_ragebot({
    ui = ui,
    unpack = unpack
})

local override = pasthetic_ui_overrides.new_override({
    ui = ui,
    unpack = unpack
})

local logging = core.new_logging({
    client = client,
    cvar = cvar,
    constants = pasthetic_constants
})

local diagnostics = pasthetic_diagnostics.new({
    client = client,
    prefix = '[Pasthetic]'
})

local localdb = pasthetic_localdb.new({
    json = json,
    base64 = base64,
    logging = logging,
    constants = pasthetic_constants,
    readfile = readfile,
    writefile = writefile
})

local config_system = pasthetic_config_system.new({
    json = json,
    base64 = base64,
    client = client,
    constants = pasthetic_constants,
    unpack = unpack
})

local menu = pasthetic_menu.new({
    ui = ui,
    event_system = event_system,
    unpack = unpack
})

local menu_logic = pasthetic_menu_logic.new({
    menu = menu,
    event_system = event_system,
    logging = logging
})

local dormant_resource = nil

local function wrap_external_config_ref(ref, on_fire)
    return pasthetic_external_config_ref.wrap({ ui = ui }, ref, on_fire)
end

local dormant_api = start_optional_module('dormant', pasthetic_dormant)

if dormant_api ~= nil then
    dormant_resource = pasthetic_external_config_ref.register_dormant({
        ui = ui,
        config_system = config_system,
        menu_logic = menu_logic,
        menu = menu,
        dormant_api = dormant_api
    })
end

local text_anims = pasthetic_text_anims.new({
    utils = utils,
    color = color
})

local session = core.new_session()

local localplayer = pasthetic_localplayer.new({
    bit = bit,
    client = client,
    entity = entity,
    vector = vector,
    c_entity = c_entity,
    utils = utils
})

local exploit = pasthetic_exploit.new({
    client = client,
    entity = entity,
    globals = globals,
    vector = vector,
    utils = utils,
    toticks = toticks
})

local statement = pasthetic_statement.new({
    client = client,
    localplayer = localplayer,
    software = software
})

local resource = diagnostics:start('resource_builder', function()
    return pasthetic_resource_builder.start({
        script = script,
        menu = menu,
        ui = ui,
        const = const,
        ui_callback = ui_callback,
        external_config_ref = pasthetic_external_config_ref,
        config_system = config_system,
        menu_logic = menu_logic,
        software = software,
        client = client,
        utils = utils,
        logging = logging,
        color = color,
        dormant_resource = dormant_resource,
        contains = contains,
        unpack = unpack
    })
end)
diagnostics:health('resource_builder', pasthetic_resource_builder, { resource = resource })

local windows = pasthetic_windows.new({
    vector = vector,
    client = client,
    globals = globals,
    ui = ui,
    renderer = renderer,
    menu = menu,
    utils = utils
})

local config_controller = diagnostics:start('config_controller', function()
    return pasthetic_config_controller.start({
        resource = resource,
        constants = pasthetic_constants,
        localdb = localdb,
        database = database,
        logging = logging,
        config_system = config_system,
        windows = windows,
        menu = menu,
        menu_logic = menu_logic,
        clipboard = clipboard,
        utils = utils,
        client = client,
        ui = ui,
        contains = contains
    })
end)
diagnostics:health('config_controller', pasthetic_config_controller, { controller = config_controller })

pasthetic_runtime_modules.start({
    require_module = require_pasthetic_module,
    script = script,
    resource = resource,
    diagnostics = diagnostics,
    ui = ui,
    entity = entity,
    client = client,
    globals = globals,
    vector = vector,
    plist = plist,
    csgo_weapons = csgo_weapons,
    ragebot = ragebot,
    utils = utils,
    unpack = unpack,
    session = session,
    renderer = renderer,
    software = software,
    exploit = exploit,
    localplayer = localplayer,
    override = override,
    bit = bit,
    toticks = toticks,
    cvar = cvar,
    ui_callback = ui_callback,
    panorama = panorama,
    clipboard = clipboard,
    chat = chat,
    localize = localize,
    color = color,
    motion = motion,
    surface = surface,
    text_fmt = text_fmt,
    totime = totime,
    c_entity = c_entity,
    statement = statement,
    ffi = ffi,
    materialsystem = materialsystem,
    has_update = function()
        return update_manager.has_update()
    end
})

-- ====================================================================
-- Auto-update: check on startup, show download button if needed
-- ====================================================================

if __pasthetic_disable_allinone_update ~= true then
    local download_update_btn

    local function hide_download_update_btn()
        if download_update_btn ~= nil then
            ui.set_visible(download_update_btn, false)
        end
    end

    download_update_btn = ui.new_button(
        'CONFIG',
        'Lua',
        __pasthetic_allinone == true and 'Download latest all-in-one' or 'Download latest version',
        function()
        if um_state.busy then return end
        if update_manager.has_update() then
            update_manager.download(function(success)
                if success then hide_download_update_btn() end
            end)
        else
            update_manager.check(function(ok)
                if ok and update_manager.has_update() then
                    update_manager.download(function(success)
                        if success then hide_download_update_btn() end
                    end)
                end
            end)
        end
    end)
    hide_download_update_btn()

    update_manager.check(function(ok)
        if ok and update_manager.has_update() then
            ui.set_visible(download_update_btn, true)
        end
    end)
end
