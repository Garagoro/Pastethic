local M = {}

local HOTKEY_MODE = {
    [0] = 'Always on',
    [1] = 'On hotkey',
    [2] = 'Toggle',
    [3] = 'Off hotkey'
}

local function make_get_value(ui)
    return function(item)
        local item_type = ui.type(item)
        local value = { ui.get(item) }

        if item_type == 'hotkey' then
            local mode = HOTKEY_MODE[value[2]]
            local keycode = value[3] or 0

            return { mode, keycode }
        end

        return value
    end
end

function M.new_ragebot(deps)
    deps = deps or {}

    local ui = deps.ui or ui
    local unpack_fn = deps.unpack or unpack
    local ragebot = {}
    local item_data = {}
    local ref_weapon_type = ui.reference(
        'Rage', 'Weapon type', 'Weapon type'
    )
    local get_value = make_get_value(ui)

    function ragebot.set(item, ...)
        local weapon_type = ui.get(ref_weapon_type)

        if item_data[item] == nil then
            item_data[item] = {}
        end

        local data = item_data[item]

        if data[weapon_type] == nil then
            data[weapon_type] = {
                type = weapon_type,
                value = get_value(item)
            }
        end

        ui.set(item, ...)
    end

    function ragebot.unset(item)
        local data = item_data[item]

        if data == nil then
            return
        end

        local weapon_type = ui.get(ref_weapon_type)

        for k, v in pairs(data) do
            ui.set(ref_weapon_type, v.type)
            ui.set(item, unpack_fn(v.value))

            data[k] = nil
        end

        ui.set(ref_weapon_type, weapon_type)
        item_data[item] = nil
    end

    return ragebot
end

function M.new_override(deps)
    deps = deps or {}

    local ui = deps.ui or ui
    local unpack_fn = deps.unpack or unpack
    local override = {}
    local item_data = {}
    local get_value = make_get_value(ui)

    function override.get(item)
        local value = item_data[item]

        if value == nil then
            return nil
        end

        return unpack_fn(value)
    end

    function override.set(item, ...)
        if item_data[item] == nil then
            item_data[item] = get_value(item)
        end

        ui.set(item, ...)
    end

    function override.unset(item)
        local value = item_data[item]

        if value == nil then
            return
        end

        ui.set(item, unpack_fn(value))
        item_data[item] = nil
    end

    return override
end

return M
