local M = {}

function M.new(deps)
    deps = deps or {}

    local json = deps.json or json
    local base64 = deps.base64 or base64
    local constants = deps.constants or (require 'pasthetic/core').constants
    local client_api = deps.client or client
    local unpack_fn = deps.unpack or unpack

    local config_system = {}
    local BASE64_KEY = 'bjW9MagJsut5xDz36Hvl74nC8Eoy0GIUVX2NLQepckFfrBYOhRZKAwmSqidP1T+/='

    local HOTKEY_MODE = {
        [0] = 'Always on',
        [1] = 'On hotkey',
        [2] = 'Toggle',
        [3] = 'Off hotkey'
    }

    local item_list = {}
    local item_data = {}

    local function get_item_value(item)
        if item.type == 'hotkey' then
            local _, mode, key = item:get()
            return { HOTKEY_MODE[mode], key or 0 }
        end

        return { item:get() }
    end

    local function get_key_values(arr)
        local list = {}

        if arr ~= nil then
            for i = 1, #arr do
                list[arr[i]] = i
            end
        end

        return list
    end

    local function extract_payload(str)
        if type(str) ~= 'string' then
            return nil
        end

        return str:match('%[' .. constants.CONFIG_PREFIX .. '%] (.-)_')
            or str:match('%[' .. constants.LEGACY_CONFIG_PREFIX .. '%] (.-)_')
    end

    local function normalize_values(values)
        if type(values) ~= 'table' then
            return values
        end

        local result = {}

        for i = 1, #values do
            if values[i] == constants.LEGACY_SCRIPT_NAME then
                result[i] = constants.SCRIPT_NAME
            else
                result[i] = values[i]
            end
        end

        return result
    end

    function config_system.push(tab, name, item)
        if item_data[tab] == nil then
            item_data[tab] = {}
        end

        local data = {
            tab = tab,
            name = name,
            item = item
        }

        if item_data[tab][name] ~= nil and client_api ~= nil and type(client_api.error_log) == 'function' then
            client_api.error_log(string.format('config collision: [ %s, %s ]', tab, name))
        end

        item_data[tab][name] = item
        table.insert(item_list, data)

        return item
    end

    function config_system.encode(data)
        local ok, result = pcall(json.stringify, data)
        if not ok then
            return false, result
        end

        ok, result = pcall(base64.encode, result, BASE64_KEY)
        if not ok then
            return false, result
        end

        return true, string.format('[%s] %s_', constants.CONFIG_PREFIX, result)
    end

    function config_system.decode(str)
        local data = extract_payload(str)
        if data == nil then
            return false, 'Invalid config'
        end

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

    function config_system.import(data, categories)
        if data == nil then
            return false, 'config is empty'
        end

        local keys = get_key_values(categories)
        local updated_items = {}

        for k, v in pairs(data) do
            if categories ~= nil and keys[k] == nil then
                goto continue
            end

            local items = item_data[k]
            if items == nil then
                goto continue
            end

            for m, n in pairs(v) do
                local item = items[m]

                if item ~= nil then
                    local ok = pcall(item.set, item, unpack_fn(normalize_values(n)))

                    if ok then
                        table.insert(updated_items, item)
                    end
                end
            end

            ::continue::
        end

        for i = 1, #updated_items do
            pcall(updated_items[i].fire_events, updated_items[i])
        end

        return true, nil
    end

    function config_system.export(categories)
        local list = {}
        local keys = get_key_values(categories)

        for k, v in pairs(item_data) do
            if categories ~= nil and keys[k] == nil then
                goto continue
            end

            local values = {}

            for m, n in pairs(v) do
                values[m] = get_item_value(n)
            end

            list[k] = values

            ::continue::
        end

        return list
    end

    return config_system
end

return M
