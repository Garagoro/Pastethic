local M = {}

function M.new(deps)
    deps = deps or {}

    local json = deps.json or json
    local base64 = deps.base64 or base64
    local constants = deps.constants or (require 'pasthetic/core').constants
    local logging = deps.logging or {}
    local read_file_impl = deps.readfile or readfile
    local write_file_impl = deps.writefile or writefile

    local localdb = {}
    local BASE64_KEY = 'BqvbCHsU5NwhxAzGKjFgytIT0oXlurekOdS8ZiPVaEnR7219Q6mM3DfLW4YpcJ+/='
    local PATH = deps.path or '.'
    local FILE = PATH .. '\\' .. constants.LOCALDB_FILE
    local LEGACY_FILE = PATH .. '\\' .. constants.LEGACY_LOCALDB_FILE
    local store = {}

    local function log_error(msg)
        if type(logging.error) == 'function' then
            logging.error(msg)
        end
    end

    local function log_info(msg)
        if type(logging.log) == 'function' then
            logging.log(msg)
        end
    end

    local function read_file()
        local content = read_file_impl(FILE)
        if content ~= nil then
            return content
        end

        return read_file_impl(LEGACY_FILE)
    end

    local function write_file(str)
        write_file_impl(FILE, str)
    end

    local function encode_data(data)
        local ok, result = pcall(json.stringify, data)
        if not ok then
            return false, result
        end

        ok, result = pcall(base64.encode, result, BASE64_KEY)
        if not ok then
            return false, result
        end

        return true, result
    end

    local function decode_data(data)
        local ok, result = pcall(base64.decode, data, BASE64_KEY)
        if not ok then
            return false, result
        end

        ok, result = pcall(json.parse, result)
        if not ok then
            return false, result
        end

        return true, result
    end

    local function write_storage(data)
        local ok, result = encode_data(data)
        if not ok then
            log_error('Unable to encode data')
            return false
        end

        write_file(result)
        return true
    end

    local function parse_storage()
        local content = read_file()

        if content == nil then
            if not write_storage({}) then
                log_info('Unable to create db')
            end

            return {}
        end

        local ok, result = decode_data(content)
        if not ok then
            log_error('Unable to decode db')
            log_info('Trying to flush db')

            if not write_storage({}) then
                log_error('Unable to flush db')
            end

            return {}
        end

        return result
    end

    local mt = {}

    function mt:__index(key)
        return store[key]
    end

    function mt:__newindex(key, value)
        store[key] = value
        write_storage(store)
    end

    store = parse_storage()
    setmetatable(localdb, mt)

    return localdb
end

return M
