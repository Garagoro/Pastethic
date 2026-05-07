local M = {}

function M.start(deps)
    local resource = assert(deps.resource, 'rage_peek_assist: resource dependency is required')
    local ui = assert(deps.ui, 'rage_peek_assist: ui dependency is required')
    local entity = assert(deps.entity, 'rage_peek_assist: entity dependency is required')
    local csgo_weapons = assert(deps.csgo_weapons, 'rage_peek_assist: csgo_weapons dependency is required')
    local software = assert(deps.software, 'rage_peek_assist: software dependency is required')
    local localplayer = assert(deps.localplayer, 'rage_peek_assist: localplayer dependency is required')
    local ragebot = assert(deps.ragebot, 'rage_peek_assist: ragebot dependency is required')
    local utils = assert(deps.utils, 'rage_peek_assist: utils dependency is required')

    local ref = resource.main.ragebot.peek_assist
    local ref_weapon_type = software.ragebot.weapon_type
    local ref_dt_limit = software.ragebot.aimbot.double_tap_fake_lag_limit

    local function get_local_weapon_group(weapon)
        local weapon_info = csgo_weapons(weapon)

        if weapon_info == nil then
            return nil
        end

        local weapon_type = weapon_info.type
        local weapon_index = weapon_info.idx

        if weapon_type == 'pistol' then
            if weapon_index == 1 then
                return 'Desert Eagle'
            end

            if weapon_index == 64 then
                return 'Revolver R8'
            end

            return 'Pistols'
        end

        if weapon_type == 'sniperrifle' then
            if weapon_index == 40 then
                return 'Scout'
            end

            if weapon_index == 9 then
                return 'AWP'
            end

            return 'Auto Snipers'
        end

        return nil
    end

    local function get_threat_weapon_group(weapon)
        local weapon_info = csgo_weapons(weapon)

        if weapon_info == nil then
            return nil
        end

        local weapon_index = weapon_info.idx

        if weapon_index == 9 then
            return 'AWP'
        end

        if weapon_index == 11 or weapon_index == 38 then
            return 'G3SG1 / SCAR-20'
        end

        if weapon_index == 64 then
            return 'R8 Revolver'
        end

        return nil
    end

    local function set_weapon_limit(weapon_group, value)
        local previous_weapon_group = ui.get(ref_weapon_type)

        ui.set(ref_weapon_type, weapon_group)
        ragebot.set(ref_dt_limit, value)
        ui.set(ref_weapon_type, previous_weapon_group)
    end

    local function should_update()
        return (
            ref.enabled:get()
            and software.is_double_tap_active()
            and localplayer.is_peeking
        )
    end

    local function on_setup_command()
        if not should_update() then
            return
        end

        local me = entity.get_local_player()

        if me == nil or not entity.is_alive(me) then
            return
        end

        local weapon = entity.get_player_weapon(me)

        if weapon == nil then
            return
        end

        local local_weapon_group = get_local_weapon_group(weapon)

        if local_weapon_group == nil or not ref.weapons:get(local_weapon_group) then
            return
        end

        local threat = localplayer.peek_threat

        if threat == nil or not entity.is_alive(threat) then
            return
        end

        local threat_weapon = entity.get_player_weapon(threat)

        if threat_weapon == nil then
            return
        end

        local weapon_group = get_threat_weapon_group(threat_weapon)

        if weapon_group == nil then
            return
        end

        set_weapon_limit(weapon_group, ref.limit:get())
    end

    local function on_reset()
        ragebot.unset(ref_dt_limit)
    end

    local function on_enabled(item)
        local value = item:get()

        if not value then
            on_reset()
        end

        utils.event_callback('shutdown', on_reset, value)
        utils.event_callback('setup_command', on_setup_command, value)
        utils.event_callback('finish_command', on_reset, value)
        utils.event_callback('pre_config_save', on_reset, value)
    end

    ref.enabled:set_callback(on_enabled, true)
end

return M
