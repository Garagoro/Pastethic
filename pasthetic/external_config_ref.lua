local M = {}

function M.wrap(deps, ref, on_fire)
    local ui = assert(deps.ui, 'external_config_ref: ui dependency is required')

    if ref == nil then
        return nil
    end

    local item = {
        ref = ref,
        type = ui.type(ref)
    }

    function item:get()
        return ui.get(self.ref)
    end

    function item:set(...)
        ui.set(self.ref, ...)
    end

    function item:fire_events()
        if on_fire ~= nil then
            pcall(on_fire)
        end
    end

    function item:set_visible(value)
        return ui.set_visible(self.ref, value)
    end

    function item:set_callback(callback)
        return ui.set_callback(self.ref, callback)
    end

    return item
end

function M.register_bundled_dormant(deps)
    local ui = assert(deps.ui, 'external_config_ref: ui dependency is required')
    local config_system = assert(deps.config_system, 'external_config_ref: config_system dependency is required')
    local menu_logic = assert(deps.menu_logic, 'external_config_ref: menu_logic dependency is required')
    local menu = assert(deps.menu, 'external_config_ref: menu dependency is required')
    local globals_table = deps.globals_table or _G

    local dormant_api = rawget(globals_table, 'pasthetic_dormant') or rawget(globals_table, 'aesthetic_dormant')

    if type(dormant_api) ~= 'table' or type(dormant_api.refs) ~= 'table' then
        return nil
    end

    local refs = dormant_api.refs
    local update_state = dormant_api.update_state
    local menu_events = menu.get_event_bus()

    local function push_external(name, ref, on_fire)
        local item = M.wrap({ ui = ui }, ref, on_fire)

        if item == nil then
            return nil
        end

        config_system.push('Ragebot', name, item)
        menu_logic.register_external(item)

        pcall(ui.set_callback, ref, function()
            if on_fire ~= nil then
                pcall(on_fire)
            end

            menu_events.item_changed:fire(item)
        end)

        return item
    end

    return {
        enabled = push_external('dormant.enabled', refs.dormant_switch, update_state),
        hotkey = push_external('dormant.hotkey', refs.dormant_key),
        minimum_damage = push_external('dormant.minimum_damage', refs.dormant_mindmg),
        indicator = push_external('dormant.indicator', refs.dormant_indicator)
    }
end

return M
