local M = {}

function M.start(deps)
    local resource = assert(deps.resource, 'anim_breaker: resource dependency is required')
    local ui = assert(deps.ui, 'anim_breaker: ui dependency is required')
    local entity = assert(deps.entity, 'anim_breaker: entity dependency is required')
    local client = assert(deps.client, 'anim_breaker: client dependency is required')
    local globals = assert(deps.globals, 'anim_breaker: globals dependency is required')
    local utils = assert(deps.utils, 'anim_breaker: utils dependency is required')
    local localplayer = assert(deps.localplayer, 'anim_breaker: localplayer dependency is required')
    local software = assert(deps.software, 'anim_breaker: software dependency is required')
    local override = assert(deps.override, 'anim_breaker: override dependency is required')
    local ragebot = assert(deps.ragebot, 'anim_breaker: ragebot dependency is required')
    local c_entity = assert(deps.c_entity, 'anim_breaker: c_entity dependency is required')
    local anim_breaker do
        local ref = resource.main.animations

        local ANIMATION_LAYER_MOVEMENT_MOVE = 6
        local ANIMATION_LAYER_LEAN = 12

        local anim_data = {
            layers = { },
            server_anim_states = { },
            fakelag_states = { },
            history = 64,
            fakelag_history = 17,
            extrapolation_time = 0.05,
            switch_time = 0,
            choke_state = false,
            last_unchoked_state = nil,
            initialized = false,
        }

        local fake_lag_limit = ui.reference('AA', 'Fake lag', 'Limit')

        local function initialize_animfix_layers()
            anim_data.layers = { }

            for i = 0, 12 do
                anim_data.layers[i] = {
                    cycle = 0,
                    weight = 0,
                    playback_rate = 0,
                    sequence = 0
                }
            end

            anim_data.initialized = true
        end

        local function update_air_legs(player, layer)
            if player == nil or layer == nil then
                return
            end

            local value = ref.air_legs:get()

            if value == 'Static' then
                local weight = ref.air_legs_weight:get()
                entity.set_prop(player, 'm_flPoseParameter', weight * 0.01, 6)

                return
            end

            if value == 'Moonwalk' then
                layer.weight = 1.0
                layer.cycle = (globals.curtime() * 0.55) % 1

                return
            end

            if value == 'Kangaroo' then
                entity.set_prop(player, 'm_flPoseParameter', math.random(), 3)
                entity.set_prop(player, 'm_flPoseParameter', math.random(), 7)
                entity.set_prop(player, 'm_flPoseParameter', math.random(), 6)

                return
            end
        end

        local function update_ground_legs(player)
            local value = ref.ground_legs:get()

            if value == 'Static' then
                entity.set_prop(player, 'm_flPoseParameter', 1.0, 0)
                override.set(software.antiaimbot.other.leg_movement, 'Always slide')

                return
            end

            if value == 'Jitter' then
                local tickcount = globals.tickcount()

                local offset_1 = ref.legs_offset_1:get()
                local offset_2 = ref.legs_offset_2:get()

                local speed = ref.legs_jitter_time:get()

                local mul = 1.0 / (tickcount % (speed * 4) >= (speed * 2) and 200 or 400)
                local offset = tickcount % (speed * 2) >= (speed) and offset_1 or offset_2

                entity.set_prop(player, 'm_flPoseParameter', offset * mul, 0)
                override.set(software.antiaimbot.other.leg_movement, 'Always slide')

                return
            end

            if value == 'Moonwalk' then
                entity.set_prop(player, 'm_flPoseParameter', 0.0, 7)
                override.set(software.antiaimbot.other.leg_movement, 'Never slide')

                return
            end

            if value == 'Kangaroo' then
                entity.set_prop(player, 'm_flPoseParameter', math.random(), 3)
                entity.set_prop(player, 'm_flPoseParameter', math.random(), 7)
                entity.set_prop(player, 'm_flPoseParameter', math.random(), 6)

                override.unset(software.antiaimbot.other.leg_movement)

                return
            end

            if value == 'Pacan4ik' then
                local offset_1 = ref.legs_offset_1:get() * 0.01
                local offset_2 = ref.legs_offset_2:get() * 0.01

                local leg_movement = utils.random_int(0, 1) == 0
                    and 'Off' or 'Always slide'

                entity.set_prop(player, 'm_flPoseParameter', utils.random_float(offset_1, offset_2), 0)
                override.set(software.antiaimbot.other.leg_movement, leg_movement)

                return
            end

            override.unset(software.antiaimbot.other.leg_movement)
        end

        local function update_pitch_on_land(player, animstate)
            if not ref.options:get 'Pitch zero on land' then
                return
            end

            if animstate.hit_in_ground_animation then
                entity.set_prop(player, 'm_flPoseParameter', 0.5, 12)
            end
        end

        local function update_move_lean(layer)
            if not ref.options:get 'Move lean' then
                return
            end

            local value = ref.move_lean:get()

            if value == -1 or not localplayer.is_moving then
                return
            end

            layer.weight = value
        end

        local function is_freeze_time()
            local game_rules = entity.get_game_rules()

            if game_rules == nil then
                return false
            end

            return entity.get_prop(game_rules, 'm_bFreezePeriod') == 1
        end

        local function clamp01(value)
            if value == nil or value ~= value then
                return 0
            end

            return utils.clamp(value, 0, 1)
        end

        local function clamp_positive(value)
            if value == nil or value ~= value then
                return 0
            end

            return math.max(0, value)
        end

        local function capture_animfix_state(entity_info, time, choked)
            local state = {
                time = time,
                choked = choked,
                weapon = entity.get_player_weapon(entity.get_local_player()),
                layers = { }
            }

            for layer_idx, _ in pairs(anim_data.layers) do
                local layer = entity_info:get_anim_overlay(layer_idx)

                if layer ~= nil then
                    state.layers[layer_idx] = {
                        cycle = layer.cycle,
                        weight = layer.weight,
                        playback_rate = layer.playback_rate,
                        sequence = layer.sequence
                    }
                end
            end

            return state
        end

        local function find_interpolation_states(time)
            local server_states = anim_data.server_anim_states

            if #server_states < 2 then
                return nil, nil
            end

            for i = #server_states - 1, 1, -1 do
                if server_states[i].time <= time and server_states[i + 1].time >= time then
                    return server_states[i], server_states[i + 1]
                end
            end

            return server_states[#server_states - 1], server_states[#server_states]
        end

        local function extrapolate_value(value1, value2, rate, time)
            return value2 + ((value2 - value1) / rate) * time
        end

        local function apply_animfix_state(entity_info, state, fakelag_pass)
            for layer_idx, _ in pairs(anim_data.layers) do
                local layer = entity_info:get_anim_overlay(layer_idx)
                local source = state.layers[layer_idx]

                if layer ~= nil and source ~= nil then
                    layer.cycle = clamp01(source.cycle)

                    if fakelag_pass and layer_idx == ANIMATION_LAYER_LEAN then
                        layer.weight = 0
                        layer.playback_rate = 0
                    else
                        layer.weight = clamp01(source.weight)
                        layer.playback_rate = clamp_positive(source.playback_rate)
                    end

                    if source.sequence ~= nil then
                        layer.sequence = math.floor(source.sequence + 0.5)
                    end
                end
            end
        end

        local function apply_interpolated_animfix(entity_info, state1, state2, t)
            local state = {
                layers = { }
            }

            for layer_idx, _ in pairs(anim_data.layers) do
                local layer1 = state1.layers[layer_idx]
                local layer2 = state2.layers[layer_idx]

                if layer1 ~= nil and layer2 ~= nil then
                    if (layer_idx == 1 or layer_idx == 2) and state1.weapon ~= state2.weapon then
                        state.layers[layer_idx] = layer2
                    else
                        state.layers[layer_idx] = {
                            cycle = layer1.cycle == layer2.cycle
                                and layer2.cycle
                                or utils.lerp(layer1.cycle, layer2.cycle, t),
                            weight = layer1.weight == layer2.weight
                                and layer2.weight
                                or utils.lerp(layer1.weight, layer2.weight, t),
                            playback_rate = layer1.playback_rate == layer2.playback_rate
                                and layer2.playback_rate
                                or utils.lerp(layer1.playback_rate, layer2.playback_rate, t),
                            sequence = layer2.sequence
                        }
                    end
                end
            end

            apply_animfix_state(entity_info, state, false)
        end

        local function apply_extrapolated_animfix(entity_info)
            local server_states = anim_data.server_anim_states

            if #server_states < 2 then
                return false
            end

            local state1 = server_states[#server_states - 1]
            local state2 = server_states[#server_states]
            local time_diff = state2.time - state1.time

            if time_diff < 0.001 then
                return false
            end

            local state = {
                layers = { }
            }

            for layer_idx, _ in pairs(anim_data.layers) do
                local layer1 = state1.layers[layer_idx]
                local layer2 = state2.layers[layer_idx]

                if layer1 ~= nil and layer2 ~= nil then
                    state.layers[layer_idx] = {
                        cycle = layer1.cycle == layer2.cycle
                            and layer2.cycle
                            or extrapolate_value(layer1.cycle, layer2.cycle, time_diff, anim_data.extrapolation_time),
                        weight = layer1.weight == layer2.weight
                            and layer2.weight
                            or extrapolate_value(layer1.weight, layer2.weight, time_diff, anim_data.extrapolation_time),
                        playback_rate = layer1.playback_rate == layer2.playback_rate
                            and layer2.playback_rate
                            or extrapolate_value(layer1.playback_rate, layer2.playback_rate, time_diff, anim_data.extrapolation_time),
                        sequence = layer2.sequence
                    }
                end
            end

            apply_animfix_state(entity_info, state, false)

            return true
        end

        local function update_animfix_data(cmd)
            local me = entity.get_local_player()

            if me == nil or not entity.is_alive(me) or is_freeze_time() then
                return
            end

            if not anim_data.initialized then
                initialize_animfix_layers()
            end

            local entity_info = c_entity(me)

            if entity_info == nil then
                return
            end

            local anim_state = entity_info:get_anim_state()

            if anim_state == nil then
                return
            end

            local oldcommandack = globals.oldcommandack()

            if oldcommandack - anim_data.switch_time > ui.get(fake_lag_limit) then
                anim_data.choke_state = not anim_data.choke_state
                anim_data.switch_time = oldcommandack
            end

            local server_state = capture_animfix_state(entity_info, globals.curtime(), anim_data.choke_state)

            table.insert(anim_data.server_anim_states, server_state)

            if #anim_data.server_anim_states > anim_data.history then
                table.remove(anim_data.server_anim_states, 1)
            end

            table.insert(anim_data.fakelag_states, server_state)

            if #anim_data.fakelag_states > anim_data.fakelag_history then
                table.remove(anim_data.fakelag_states, 1)
            end

            if not anim_data.choke_state then
                anim_data.last_unchoked_state = server_state
            end
        end

        local function update_animfix_render()
            if not anim_data.initialized or is_freeze_time() then
                return
            end

            local me = entity.get_local_player()

            if me == nil then
                return
            end

            local entity_info = c_entity(me)

            if entity_info == nil then
                return
            end

            local anim_state = entity_info:get_anim_state()

            if anim_state == nil then
                return
            end

            if anim_data.choke_state and anim_data.last_unchoked_state ~= nil then
                apply_animfix_state(entity_info, anim_data.last_unchoked_state, true)
                return
            end

            local state1, state2 = find_interpolation_states(globals.curtime())

            if state1 == nil or state2 == nil then
                apply_extrapolated_animfix(entity_info)
                return
            end

            local time_diff = state2.time - state1.time

            if time_diff <= 0 then
                apply_extrapolated_animfix(entity_info)
                return
            end

            local t = utils.clamp((globals.curtime() - state1.time) / time_diff, 0, 1)

            apply_interpolated_animfix(entity_info, state1, state2, t)
        end

        local function reset_animfix()
            anim_data.server_anim_states = { }
            anim_data.fakelag_states = { }
            anim_data.switch_time = 0
            anim_data.choke_state = false
            anim_data.last_unchoked_state = nil
            initialize_animfix_layers()
        end

        local function restore_values()
            override.unset(software.antiaimbot.other.leg_movement)
        end

        local function on_shutdown()
            restore_values()
            anim_data.layers = { }
            anim_data.server_anim_states = { }
            anim_data.fakelag_states = { }
            anim_data.last_unchoked_state = nil
        end

        local function on_player_death(ctx)
            if not (ctx.userid and ctx.attacker) then
                return
            end

            local me = entity.get_local_player()

            if me ~= client.userid_to_entindex(ctx.userid) then
                return
            end

            reset_animfix()
        end

        local function on_pre_render()
            local me = entity.get_local_player()

            if me == nil or not entity.is_alive(me) then
                return
            end

            local entity_info = c_entity(me)

            if entity_info == nil then
                return
            end

            local animstate = entity_info:get_anim_state()

            if animstate == nil then
                return
            end

            local layer_move = entity_info:get_anim_overlay(ANIMATION_LAYER_MOVEMENT_MOVE)
            local layer_lean = entity_info:get_anim_overlay(ANIMATION_LAYER_LEAN)

            update_animfix_render()

            if localplayer.is_onground then
                update_ground_legs(me)
                update_pitch_on_land(me, animstate)
            else
                update_air_legs(me, layer_move)
            end

            update_move_lean(layer_lean)
        end

        local function update_event_callbacks(value)
            if not value then
                restore_values()

                utils.event_callback(
                    'setup_command',
                    update_animfix_data,
                    false
                )
            end

            utils.event_callback(
                'setup_command',
                update_animfix_data,
                value
            )

            utils.event_callback(
                'shutdown',
                on_shutdown,
                value
            )

            utils.event_callback(
                'pre_render',
                on_pre_render,
                value
            )

            utils.event_callback(
                'round_start',
                reset_animfix,
                value
            )

            utils.event_callback(
                'level_init',
                reset_animfix,
                value
            )

            utils.event_callback(
                'player_death',
                on_player_death,
                value
            )
        end

        local callbacks do
            reset_animfix()
            update_event_callbacks(true)
        end
    end

    return true
end

function M.health()
    return true
end

return M