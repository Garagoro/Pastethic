local M = {}

function M.start(deps)
    local resource = assert(deps.resource, 'rage_hitchance: resource dependency is required')
    local session = assert(deps.session, 'rage_hitchance: session dependency is required')
    local ui = assert(deps.ui, 'rage_hitchance: ui dependency is required')
    local entity = assert(deps.entity, 'rage_hitchance: entity dependency is required')
    local client = assert(deps.client, 'rage_hitchance: client dependency is required')
    local vector = assert(deps.vector, 'rage_hitchance: vector dependency is required')
    local renderer = assert(deps.renderer, 'rage_hitchance: renderer dependency is required')
    local csgo_weapons = assert(deps.csgo_weapons, 'rage_hitchance: csgo_weapons dependency is required')
    local software = assert(deps.software, 'rage_hitchance: software dependency is required')
    local exploit = assert(deps.exploit, 'rage_hitchance: exploit dependency is required')
    local localplayer = assert(deps.localplayer, 'rage_hitchance: localplayer dependency is required')
    local ragebot = assert(deps.ragebot, 'rage_hitchance: ragebot dependency is required')
    local utils = assert(deps.utils, 'rage_hitchance: utils dependency is required')

    local ref = resource.main.ragebot.hitchance
    local ref_force_lethal = resource.main.ragebot.force_lethal
    local shared = session.hitchance
    local UNITS_TO_FOOT = 0.0254 * 3.28084

    local ref_hit_chance = ui.reference('Rage', 'Aimbot', 'Minimum hit chance')

    local function get_distance(player, target)
        if player == nil or target == nil then
            return nil
        end

        local player_origin = vector(entity.get_origin(player))
        local target_origin = vector(entity.get_origin(target))

        return (target_origin - player_origin):length()
    end

    local function get_value(me, weapon_type, items)
        local threat = client.current_threat()
        local force_lethal_value = nil
        local is_double_tap = software.is_double_tap_active() and exploit.get().shift

        if ref_force_lethal.enabled:get() and not is_double_tap then
            local force_items = ref_force_lethal[weapon_type]

            if force_items ~= nil and force_items.hitchance ~= nil then
                local value = force_items.hitchance:get()

                if value ~= -1 then
                    force_lethal_value = value
                end
            end
        end

        if items.options:get 'Hotkey' and ref.hotkey:get() then
            shared.updated_hotkey = true
            return items['Hotkey'].value:get()
        end

        if items.options:get 'Crouch' then
            local is_crouched = (
                localplayer.is_onground and
                localplayer.is_crouched and
                not software.is_duck_peek_assist()
            )

            if is_crouched then
                return items['Crouch'].value:get()
            end
        end

        if items.options:get 'Peek Assist' and software.is_quick_peek_assist() then
            return items['Peek Assist'].value:get()
        end

        if items.options:get 'No Scope' then
            local goal_distance = items['No Scope'].distance:get()
            local hitchance_value = items['No Scope'].value:get()

            if goal_distance == 101 then
                return hitchance_value
            end

            local distance = get_distance(me, threat)

            if distance ~= nil and (distance * UNITS_TO_FOOT) <= goal_distance then
                return hitchance_value
            end
        end

        if items.options:get 'In Air' and not localplayer.is_onground then
            return items['In Air'].value:get()
        end

        if force_lethal_value ~= nil then
            return force_lethal_value
        end
    end

    local function get_weapon_type(weapon)
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

    local function update_hitchance()
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

        local items = ref[weapon_type]

        if items == nil then
            return
        end

        local value = get_value(me, weapon_type, items)

        if value == nil then
            return
        end

        ragebot.set(ref_hit_chance, value)
        shared.updated_this_tick = true
    end

    local function on_shutdown()
        ragebot.unset(ref_hit_chance)
    end

    local function on_run_command()
        shared.updated_hotkey = false
        shared.updated_this_tick = false

        update_hitchance()
    end

    local function on_finish_command()
        ragebot.unset(ref_hit_chance)
    end

    local function on_paint()
        local me = entity.get_local_player()

        if me == nil or not entity.is_alive(me) then
            return
        end

        local should_render = shared.updated_hotkey and shared.updated_this_tick

        if not should_render then
            return
        end

        local text = ref.indicator_text:get()

        if text == 'Off' then
            return
        end

        renderer.indicator(255, 255, 255, 200, text)
    end

    local function on_pre_config_save()
        ragebot.unset(ref_hit_chance)
    end

    local function on_enabled(item)
        local value = item:get()

        if not value then
            ragebot.unset(ref_hit_chance)
        end

        utils.event_callback('shutdown', on_shutdown, value)
        utils.event_callback('run_command', on_run_command, value)
        utils.event_callback('finish_command', on_finish_command, value)
        utils.event_callback('paint', on_paint, value)
        utils.event_callback('pre_config_save', on_pre_config_save, value)
    end

    ref.enabled:set_callback(on_enabled, true)
end

return M
