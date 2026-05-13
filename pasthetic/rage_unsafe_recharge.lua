local M = {}

function M.start(deps)
    local resource = assert(deps.resource, 'rage_unsafe_recharge: resource dependency is required')
    local bit = assert(deps.bit, 'rage_unsafe_recharge: bit dependency is required')
    local ui = assert(deps.ui, 'rage_unsafe_recharge: ui dependency is required')
    local globals = assert(deps.globals, 'rage_unsafe_recharge: globals dependency is required')
    local entity = assert(deps.entity, 'rage_unsafe_recharge: entity dependency is required')
    local client = assert(deps.client, 'rage_unsafe_recharge: client dependency is required')
    local csgo_weapons = assert(deps.csgo_weapons, 'rage_unsafe_recharge: csgo_weapons dependency is required')
    local exploit = assert(deps.exploit, 'rage_unsafe_recharge: exploit dependency is required')
    local ragebot = assert(deps.ragebot, 'rage_unsafe_recharge: ragebot dependency is required')
    local utils = assert(deps.utils, 'rage_unsafe_recharge: utils dependency is required')

    local ref = resource.main.ragebot.unsafe_recharge
    local prev_state = false

    local ref_enabled = {
        ui.reference('Rage', 'Aimbot', 'Enabled')
    }

    local ref_double_tap = {
        ui.reference('Rage', 'Aimbot', 'Double tap')
    }

    local ref_on_shot_antiaim = {
        ui.reference('AA', 'Other', 'On shot anti-aim')
    }

    local ref_duck_peek_assist = ui.reference(
        'Rage', 'Other', 'Duck peek assist'
    )

    local function is_double_tap_active()
        return ui.get(ref_double_tap[1])
            and ui.get(ref_double_tap[2])
    end

    local function is_on_shot_antiaim_active()
        return ui.get(ref_on_shot_antiaim[1])
            and ui.get(ref_on_shot_antiaim[2])
    end

    local function is_tickbase_changed(player)
        return (globals.tickcount() - entity.get_prop(player, 'm_nTickBase')) > 0
    end

    local function should_change(me, weapon)
        local weapon_info = csgo_weapons(weapon)

        if weapon_info == nil then
            return false
        end

        local threat = client.current_threat()

        if threat == nil then
            return false
        end

        local esp_data = entity.get_esp_data(threat)

        if esp_data == nil then
            return false
        end

        local esp_flags = esp_data.flags

        if esp_flags == nil then
            return false
        end

        if bit.band(esp_flags, 2048) == 0 then
            return false
        end

        if ui.get(ref_duck_peek_assist) then
            return false
        end

        local state = is_double_tap_active()
        local charged = exploit.get().shift

        if prev_state ~= state then
            if state and not charged then
                return true
            end

            prev_state = state
        end

        if is_on_shot_antiaim_active() then
            return not is_tickbase_changed(me)
        end

        return false
    end

    local function update_values()
        ragebot.set(ref_enabled[1], false)
    end

    local function restore_values()
        ragebot.unset(ref_enabled[1])
    end

    local function on_shutdown()
        restore_values()
    end

    local function on_setup_command()
        local me = entity.get_local_player()

        if me == nil then
            return false
        end

        local weapon = entity.get_player_weapon(me)

        if weapon == nil then
            return false
        end

        if should_change(me, weapon) then
            update_values()
        else
            restore_values()
        end
    end

    local function update_event_callbacks(value)
        if not value then
            restore_values()
        end

        utils.event_callback('shutdown', on_shutdown, value)
        utils.event_callback('setup_command', on_setup_command, value)
    end

    local function on_enabled(item)
        update_event_callbacks(item:get())
    end

    ref.enabled:set_callback(on_enabled, true)
end

return M
