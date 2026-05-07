local M = {}

function M.start(deps)
    local resource = assert(deps.resource, 'rage_force_lethal: resource dependency is required')
    local session = assert(deps.session, 'rage_force_lethal: session dependency is required')
    local ui = assert(deps.ui, 'rage_force_lethal: ui dependency is required')
    local entity = assert(deps.entity, 'rage_force_lethal: entity dependency is required')
    local client = assert(deps.client, 'rage_force_lethal: client dependency is required')
    local renderer = assert(deps.renderer, 'rage_force_lethal: renderer dependency is required')
    local csgo_weapons = assert(deps.csgo_weapons, 'rage_force_lethal: csgo_weapons dependency is required')
    local software = assert(deps.software, 'rage_force_lethal: software dependency is required')
    local exploit = assert(deps.exploit, 'rage_force_lethal: exploit dependency is required')
    local ragebot = assert(deps.ragebot, 'rage_force_lethal: ragebot dependency is required')
    local utils = assert(deps.utils, 'rage_force_lethal: utils dependency is required')

    local ref = resource.main.ragebot.force_lethal
    local ref_hitchance = resource.main.ragebot.hitchance
    local shared = session.force_lethal

    local ref_force_body_aim = ui.reference(
        'Rage', 'Aimbot', 'Force body aim'
    )

    local ref_hit_chance = ui.reference(
        'Rage', 'Aimbot', 'Minimum hit chance'
    )

    local ref_minimum_damage = ui.reference(
        'Rage', 'Aimbot', 'Minimum damage'
    )

    local function get_weapon_type(weapon)
        local weapon_info = csgo_weapons(weapon)

        if weapon_info == nil then
            return nil
        end

        local weapon_index = weapon_info.idx

        if weapon_index == 1 then
            return 'Desert Eagle'
        end

        if weapon_index == 11 or weapon_index == 38 then
            return 'Auto Snipers'
        end

        return nil
    end

    local function update_force_lethal()
        local me = entity.get_local_player()

        if me == nil then
            return
        end

        local weapon = entity.get_player_weapon(me)

        if weapon == nil then
            return
        end

        local weapon_type = get_weapon_type(weapon)

        if weapon_type == nil then
            return
        end

        if not ref.weapons:get(weapon_type) then
            return
        end

        local mode = ref.mode:get()

        local is_double_tap = (
            software.is_double_tap_active()
            and exploit.get().shift
        )

        local should_hp_damage = (
            not is_double_tap and
            not ui.get(ref_force_body_aim)
        )

        if should_hp_damage then
            ragebot.set(ref_minimum_damage, 100)

            if not ref_hitchance.enabled:get() then
                local items = ref[weapon_type]

                if items ~= nil and items.hitchance ~= nil then
                    local value = items.hitchance:get()

                    if value ~= -1 then
                        ragebot.set(ref_hit_chance, value)
                    end
                end
            end

            shared.updated_division = false
            shared.updated_this_tick = true

            return
        end

        if mode == 'Damage = HP/2' then
            local threat = client.current_threat()

            if threat == nil then
                return
            end

            local health = entity.get_prop(threat, 'm_iHealth')

            ragebot.set(ref_minimum_damage, math.ceil(health / 2))

            shared.updated_division = true
            shared.updated_this_tick = true

            return
        end
    end

    local function on_shutdown()
        ragebot.unset(ref_minimum_damage)
    end

    local function on_run_command()
        shared.updated_division = false
        shared.updated_this_tick = false

        update_force_lethal()
    end

    local function on_finish_command()
        if not ref_hitchance.enabled:get() then
            ragebot.unset(ref_hit_chance)
        end

        ragebot.unset(ref_minimum_damage)
    end

    local function on_paint()
        if software.is_override_minimum_damage() then
            return
        end

        local me = entity.get_local_player()

        if me == nil or not entity.is_alive(me) then
            return
        end

        if shared.updated_this_tick then
            local r, g, b, a = 255, 0, 50, 255

            if shared.updated_division then
                r, g, b, a = 255, 255, 255, 200
            end

            renderer.indicator(r, g, b, a, 'FL')
        end
    end

    local function on_enabled(item)
        local value = item:get()

        if not value then
            ragebot.unset(ref_minimum_damage)
        end

        utils.event_callback('shutdown', on_shutdown, value)
        utils.event_callback('run_command', on_run_command, value)
        utils.event_callback('finish_command', on_finish_command, value)
        utils.event_callback('paint', on_paint, value)
    end

    ref.enabled:set_callback(on_enabled, true)
end

return M
