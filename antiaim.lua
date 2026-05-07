local M = {}

function M.start(deps)
    local resource = assert(deps.resource, 'antiaim: resource dependency is required')
    local ui = assert(deps.ui, 'antiaim: ui dependency is required')
    local entity = assert(deps.entity, 'antiaim: entity dependency is required')
    local client = assert(deps.client, 'antiaim: client dependency is required')
    local globals = assert(deps.globals, 'antiaim: globals dependency is required')
    local utils = assert(deps.utils, 'antiaim: utils dependency is required')
    local localplayer = assert(deps.localplayer, 'antiaim: localplayer dependency is required')
    local software = assert(deps.software, 'antiaim: software dependency is required')
    local override = assert(deps.override, 'antiaim: override dependency is required')
    local vector = assert(deps.vector, 'antiaim: vector dependency is required')
    local c_entity = assert(deps.c_entity, 'antiaim: c_entity dependency is required')
    local statement = assert(deps.statement, 'antiaim: statement dependency is required')
    local csgo_weapons = assert(deps.csgo_weapons, 'antiaim: csgo_weapons dependency is required')
    local exploit = assert(deps.exploit, 'antiaim: exploit dependency is required')
    local bit = assert(deps.bit, 'antiaim: bit dependency is required')
    local toticks = assert(deps.toticks, 'antiaim: toticks dependency is required')
    local presets = assert(deps.presets, 'antiaim: presets dependency is required')
    local preset_runtime = presets.new({ utils = utils })
local antiaim = { } do
    local inverts = 0
    local inverted = false

    local delay_ticks = 0
    local delay_state = {
        items = nil,
        body_yaw = nil,
        current = 1,
        last = nil,
        from = nil,
        to = nil,
        chaos = nil,
        needs_update = true
    }

    local buffer = { } do
        local ref = software.antiaimbot.angles

        local function override_value(item, ...)
            if ... == nil then
                return
            end

            override.set(item, ...)
        end

        local Buffer = { } do
            Buffer.__index = Buffer

            function Buffer:clear()
                for k in pairs(self) do
                    self[k] = nil
                end
            end

            function Buffer:copy(target)
                for k, v in pairs(target) do
                    self[k] = v
                end
            end

            function Buffer:unset()
                override.unset(ref.roll)

                override.unset(ref.freestanding[2])
                override.unset(ref.freestanding[1])

                override.unset(ref.edge_yaw)

                override.unset(ref.freestanding_body_yaw)

                override.unset(ref.body_yaw[2])
                override.unset(ref.body_yaw[1])

                override.unset(ref.yaw[2])
                override.unset(ref.yaw[1])

                override.unset(ref.yaw_jitter[2])
                override.unset(ref.yaw_jitter[1])

                override.unset(ref.yaw_base)

                override.unset(ref.pitch[2])
                override.unset(ref.pitch[1])

                override.unset(ref.enabled)
            end

            function Buffer:set()
                if self.pitch_offset ~= nil then
                    self.pitch_offset = utils.clamp(
                        self.pitch_offset, -89, 89
                    )
                end

                if self.yaw_offset ~= nil then
                    self.yaw_offset = utils.normalize(
                        self.yaw_offset, -180, 180
                    )
                end

                if self.jitter_offset ~= nil then
                    self.jitter_offset = utils.normalize(
                        self.jitter_offset, -180, 180
                    )
                end

                if self.body_yaw_offset ~= nil then
                    self.body_yaw_offset = utils.clamp(
                        self.body_yaw_offset, -180, 180
                    )
                end

                override_value(ref.enabled, self.enabled)

                override_value(ref.pitch[1], self.pitch)
                override_value(ref.pitch[2], self.pitch_offset)

                override_value(ref.yaw_base, self.yaw_base)

                override_value(ref.yaw[1], self.yaw)
                override_value(ref.yaw[2], self.yaw_offset)

                override_value(ref.yaw_jitter[1], self.yaw_jitter)
                override_value(ref.yaw_jitter[2], self.jitter_offset)

                override_value(ref.body_yaw[1], self.body_yaw)
                override_value(ref.body_yaw[2], self.body_yaw_offset)

                override_value(ref.freestanding_body_yaw, self.freestanding_body_yaw)

                override_value(ref.edge_yaw, self.edge_yaw)

                if self.freestanding == true then
                    override_value(ref.freestanding[1], true)
                    override_value(ref.freestanding[2], 'Always on')
                elseif self.freestanding == false then
                    override_value(ref.freestanding[1], false)
                    override_value(ref.freestanding[2], 'On hotkey')
                end

                override_value(ref.roll, self.roll)
            end
        end

        setmetatable(buffer, Buffer)
        antiaim.buffer = buffer
    end

    local safe_head = { } do
        local ref = resource.antiaim.features.safe_head

        local function should_update()
            return ref.enabled:get()
        end

        local function get_condition(me, threat)
            local weapon = entity.get_player_weapon(me)

            if weapon == nil then
                return nil
            end

            local weapon_info = csgo_weapons(weapon)

            if weapon_info == nil then
                return nil
            end

            local weapon_type = weapon_info.type
            local weapon_index = weapon_info.idx

            -- fun fact: taser is also a knife type of weapon
            local is_knife = weapon_type == 'knife'
            local is_taser = weapon_index == 31

            local my_origin = vector(entity.get_origin(me))
            local threat_origin = vector(entity.get_origin(threat))

            local delta = threat_origin - my_origin

            local height = -delta.z
            local distancesqr = delta:length2dsqr()

            if localplayer.is_onground then
                local is_distance_state = not localplayer.is_moving
                    or localplayer.is_crouched

                if is_distance_state and height >= 10 and distancesqr > 1000 * 1000 then
                    return 'Distance'
                end

                if localplayer.is_crouched then
                    if height >= 48 then
                        return 'Crouch'
                    end
                else
                    if not localplayer.is_moving and height >= 24 then
                        return 'Standing'
                    end
                end

                return nil
            end

            if localplayer.is_crouched then
                if is_taser and height > -20 and distancesqr < 500 * 500 then
                    return 'Air crouch taser'
                end

                if is_knife  then
                    return 'Air crouch knife'
                end

                if height > 160 then
                    return 'Air crouch'
                end
            end

            return nil
        end

        local function update_buffer(condition)
            if condition == 'Air crouch knife' then
                buffer.pitch = 'Default'
                buffer.yaw_base = 'At targets'

                buffer.yaw = '180'
                buffer.yaw_offset = 37

                buffer.yaw_left = 0
                buffer.yaw_right = 0

                buffer.yaw_jitter = 'Off'
                buffer.jitter_offset = 0

                buffer.body_yaw = 'Static'
                buffer.body_yaw_offset = 1

                buffer.freestanding_body_yaw = false

                buffer.roll = 0
                buffer.defensive = nil

                return
            end

            buffer.pitch = 'Default'
            buffer.yaw_base = 'At targets'

            buffer.yaw = '180'
            buffer.yaw_offset = 0

            buffer.yaw_left = 0
            buffer.yaw_right = 0

            buffer.yaw_jitter = 'Off'
            buffer.jitter_offset = 0

            buffer.body_yaw = 'Static'
            buffer.body_yaw_offset = 0

            buffer.freestanding_body_yaw = false

            buffer.roll = 0
            buffer.defensive = nil
        end

        local function update_spam(cmd, condition)
            if not ref.e_spam_while_active:get() then
                return
            end

            local buffer_ctx = { }

            buffer_ctx.pitch = 'Custom'
            buffer_ctx.pitch_offset = 0

            buffer_ctx.yaw = '180'
            buffer_ctx.yaw_offset = 180

            buffer_ctx.yaw_jitter = 'Off'
            buffer_ctx.jitter_offset = 0

            buffer_ctx.body_yaw = 'Static'
            buffer_ctx.body_yaw_offset = 180
            buffer_ctx.freestanding_body_yaw = false

            cmd.force_defensive = true

            buffer.defensive = buffer_ctx
        end

        function safe_head:update(cmd)
            if not should_update() then
                return false
            end

            local me = entity.get_local_player()

            if me == nil then
                return false
            end

            local threat = client.current_threat()

            if threat == nil  then
                return false
            end

            local condition = get_condition(me, threat)

            if condition == nil then
                return false
            end

            local is_enabled = ref.conditions:get(condition)

            if not is_enabled then
                return false
            end

            update_buffer(condition)
            update_spam(cmd, condition)

            return true
        end
    end

    local edge_yaw = { } do
        local ref = resource.antiaim.hotkeys.edge_yaw

        local function get_state()
            if not localplayer.is_onground then
                return 'Air'
            end

            if localplayer.is_crouched then
                return 'Crouched'
            end

            if localplayer.is_moving then
                if software.is_slow_motion() then
                    return 'Slow Walk'
                end

                return 'Moving'
            end

            return 'Standing'
        end

        local function is_disabled()
            return ref.disablers:get(
                get_state()
            )
        end

        local function is_enabled()
            if not ref.enabled:get() then
                return false
            end

            if not ref.hotkey:get() then
                return false
            end

            return not is_disabled()
        end

        function edge_yaw:update(cmd)
            if not is_enabled() then
                buffer.edge_yaw = false

                return
            end

            buffer.edge_yaw = true
        end
    end

    local defensive = { } do
        local generated_pitch = 0
        local generated_yaw = 0

        local pitch_inverted = false
        local modifier_delay_ticks = 0
        local defensive_angle_delay_state = {
            pitch = {
                items = nil,
                mode = nil,
                current = 1,
                last = nil,
                ticks = 0,
                from = nil,
                to = nil,
                chaos = nil,
                applied = nil,
                pending = nil,
                last_command = nil
            },
            yaw = {
                items = nil,
                mode = nil,
                current = 1,
                last = nil,
                ticks = 0,
                from = nil,
                to = nil,
                chaos = nil,
                applied = nil,
                pending = nil,
                last_command = nil
            }
        }
        local local_hittable_active = false
        local defensive_adaptive = {
            last_calibration = 0,
            ping_ms = 0,
            tickrate = 64,
            jitter_mult = 1.0,
            adaptive_offset = 0,
            success_count = 0,
            fail_count = 0,
            last_calculation_tick = nil,
            cached_result = true,
            cached_delay = 0,
            performance_score = 1.0,
            consecutive_failures = 0,
            last_defensive_tick = 0,
            was_active = false,
            velocity_history = { },
            enemy_aim_history = { },
            chaos_seed = 0x9E3779B9,
            lorenz = {
                x = 0.1,
                y = 0.1,
                z = 0.1
            },
            current_offset = 0,
            target_offset = 0,
            direction = 1,
            next_change_tick = 0
        }

        local function is_exploit_active()
            if software.is_double_tap_active() then
                return true
            end

            if software.is_on_shot_antiaim_active() then
                return true
            end

            return false
        end

        local function adaptive_chaos_random(min, max)
            local state = defensive_adaptive
            local tick = globals.tickcount()
            local time = globals.realtime()

            state.chaos_seed = bit.bxor(state.chaos_seed, bit.lshift(state.chaos_seed, 13))
            state.chaos_seed = bit.bxor(state.chaos_seed, bit.rshift(state.chaos_seed, 17))
            state.chaos_seed = bit.bxor(state.chaos_seed, bit.lshift(state.chaos_seed, 5))
            state.chaos_seed = bit.bxor(state.chaos_seed, math.floor(time * 1000000) % 999983)
            state.chaos_seed = bit.bxor(state.chaos_seed, tick * 73939)

            local dt = 0.01
            local dx = 10 * (state.lorenz.y - state.lorenz.x) * dt
            local dy = (state.lorenz.x * (28 - state.lorenz.z) - state.lorenz.y) * dt
            local dz = (state.lorenz.x * state.lorenz.y - 2.667 * state.lorenz.z) * dt

            state.lorenz.x = utils.clamp(state.lorenz.x + dx, -50, 50)
            state.lorenz.y = utils.clamp(state.lorenz.y + dy, -50, 50)
            state.lorenz.z = utils.clamp(state.lorenz.z + dz, 0, 50)

            local range = max - min + 1
            local normalized = utils.clamp(((state.lorenz.x + state.lorenz.y) * 0.02 + 5) / 10, 0, 1)
            local seed_influence = math.abs(state.chaos_seed) % range
            local value = min + math.floor(normalized * range * 0.6 + seed_influence * 0.4)

            return utils.clamp(value, min, max)
        end

        local function calibrate_adaptive_server()
            local tick = globals.tickcount()

            if tick - defensive_adaptive.last_calibration < 64 then
                return
            end

            defensive_adaptive.last_calibration = tick
            defensive_adaptive.tickrate = math.floor(1 / globals.tickinterval())
            defensive_adaptive.ping_ms = client.latency() * 1000

            if defensive_adaptive.ping_ms < 30 then
                defensive_adaptive.jitter_mult = 0.8
            elseif defensive_adaptive.ping_ms < 60 then
                defensive_adaptive.jitter_mult = 1.0
            elseif defensive_adaptive.ping_ms < 100 then
                defensive_adaptive.jitter_mult = 1.3
            else
                defensive_adaptive.jitter_mult = 1.6
            end

            local attempts = defensive_adaptive.success_count + defensive_adaptive.fail_count
            local success_rate = defensive_adaptive.success_count / math.max(1, attempts)

            if attempts > 5 then
                if success_rate < 0.5 then
                    defensive_adaptive.adaptive_offset = math.min(3, defensive_adaptive.adaptive_offset + 1)
                elseif success_rate > 0.8 and defensive_adaptive.adaptive_offset > 0 then
                    defensive_adaptive.adaptive_offset = math.max(0, defensive_adaptive.adaptive_offset - 1)
                end
            end
        end

        local function record_adaptive_result(success)
            if success then
                defensive_adaptive.success_count = defensive_adaptive.success_count + 1
            else
                defensive_adaptive.fail_count = defensive_adaptive.fail_count + 1
            end

            local attempts = defensive_adaptive.success_count + defensive_adaptive.fail_count

            if attempts > 10 then
                local success_rate = defensive_adaptive.success_count / attempts

                if success_rate < 0.4 then
                    defensive_adaptive.adaptive_offset = math.min(4, defensive_adaptive.adaptive_offset + 1)
                elseif success_rate > 0.85 then
                    defensive_adaptive.adaptive_offset = math.max(-1, defensive_adaptive.adaptive_offset - 1)
                end
            end

            if attempts > 50 then
                defensive_adaptive.success_count = math.floor(defensive_adaptive.success_count * 0.7)
                defensive_adaptive.fail_count = math.floor(defensive_adaptive.fail_count * 0.7)
            end
        end

        local function calculate_adaptive_delay()
            local tick = globals.tickcount()

            if defensive_adaptive.last_calculation_tick == tick then
                return defensive_adaptive.cached_delay
            end

            if tick % 16 == 0 then
                calibrate_adaptive_server()
            end

            local base_delay = 6

            if defensive_adaptive.performance_score > 0.8 then
                base_delay = 5
            elseif defensive_adaptive.performance_score < 0.4 then
                base_delay = 7
            end

            local velocity_mod = 0
            local threat_mod = 0
            local ping_mod = 0
            local me = entity.get_local_player()

            if me ~= nil then
                local velocity = vector(entity.get_prop(me, 'm_vecVelocity'))
                local speed = math.sqrt(velocity:length2dsqr())

                table.insert(defensive_adaptive.velocity_history, speed)

                if #defensive_adaptive.velocity_history > 5 then
                    table.remove(defensive_adaptive.velocity_history, 1)
                end

                local velocity_trend = 0

                if #defensive_adaptive.velocity_history >= 3 then
                    velocity_trend = defensive_adaptive.velocity_history[#defensive_adaptive.velocity_history] - defensive_adaptive.velocity_history[1]
                end

                if speed > 250 then
                    velocity_mod = velocity_trend > 50 and 4 or 3
                elseif speed > 150 then
                    velocity_mod = velocity_trend > 30 and 3 or 2
                elseif speed > 100 then
                    velocity_mod = 1
                elseif speed < 30 then
                    velocity_mod = -1
                end

                velocity_mod = math.floor(velocity_mod * defensive_adaptive.jitter_mult)
            end

            local threat = client.current_threat()

            if threat ~= nil and not entity.is_dormant(threat) then
                local enemy_pitch, enemy_yaw = entity.get_prop(threat, 'm_angEyeAngles')

                if enemy_pitch ~= nil and enemy_yaw ~= nil then
                    table.insert(defensive_adaptive.enemy_aim_history, {
                        yaw = enemy_yaw,
                        pitch = enemy_pitch
                    })

                    if #defensive_adaptive.enemy_aim_history > 12 then
                        table.remove(defensive_adaptive.enemy_aim_history, 1)
                    end

                    if #defensive_adaptive.enemy_aim_history >= 4 then
                        local yaw_variance = 0
                        local pitch_variance = 0

                        for i = 2, #defensive_adaptive.enemy_aim_history do
                            yaw_variance = yaw_variance + math.abs(defensive_adaptive.enemy_aim_history[i].yaw - defensive_adaptive.enemy_aim_history[i - 1].yaw)
                            pitch_variance = pitch_variance + math.abs(defensive_adaptive.enemy_aim_history[i].pitch - defensive_adaptive.enemy_aim_history[i - 1].pitch)
                        end

                        yaw_variance = yaw_variance / (#defensive_adaptive.enemy_aim_history - 1)
                        pitch_variance = pitch_variance / (#defensive_adaptive.enemy_aim_history - 1)

                        local total_variance = yaw_variance + pitch_variance

                        if total_variance < 3 then
                            threat_mod = 3
                        elseif total_variance < 8 then
                            threat_mod = 2
                        elseif total_variance < 20 then
                            threat_mod = 1
                        end

                        if #defensive_adaptive.enemy_aim_history >= 6 then
                            local recent_variance = 0

                            for i = #defensive_adaptive.enemy_aim_history - 2, #defensive_adaptive.enemy_aim_history do
                                recent_variance = recent_variance + math.abs(defensive_adaptive.enemy_aim_history[i].yaw - defensive_adaptive.enemy_aim_history[i - 1].yaw)
                            end

                            recent_variance = recent_variance / 3

                            if recent_variance < 2 then
                                threat_mod = threat_mod + 1
                            end
                        end
                    end
                end
            end

            if defensive_adaptive.ping_ms > 80 then
                ping_mod = 2
            elseif defensive_adaptive.ping_ms > 50 then
                ping_mod = 1
            end

            if defensive_adaptive.next_change_tick == 0 or tick >= defensive_adaptive.next_change_tick then
                local chaos_val = adaptive_chaos_random(0, 5)
                local direction_change = adaptive_chaos_random(1, 100) <= 30

                if direction_change then
                    defensive_adaptive.direction = -defensive_adaptive.direction
                end

                defensive_adaptive.target_offset = base_delay + velocity_mod + threat_mod + ping_mod + defensive_adaptive.adaptive_offset
                defensive_adaptive.target_offset = defensive_adaptive.target_offset + chaos_val * defensive_adaptive.direction
                defensive_adaptive.target_offset = utils.clamp(
                    defensive_adaptive.target_offset,
                    0,
                    defensive_adaptive.performance_score > 0.7 and 14 or 13
                )

                local change_interval = adaptive_chaos_random(2, 5)

                if threat_mod > 1 then
                    change_interval = math.max(1, change_interval - 1)
                elseif threat_mod == 0 then
                    change_interval = change_interval + 1
                end

                defensive_adaptive.next_change_tick = tick + change_interval
            end

            local smooth_speed = 0.35

            if threat_mod > 1 then
                smooth_speed = 0.7
            elseif threat_mod == 0 then
                smooth_speed = 0.2
            end

            defensive_adaptive.current_offset = defensive_adaptive.current_offset + (defensive_adaptive.target_offset - defensive_adaptive.current_offset) * smooth_speed

            if math.abs(defensive_adaptive.current_offset - defensive_adaptive.target_offset) < 0.1 then
                defensive_adaptive.current_offset = defensive_adaptive.target_offset
            end

            defensive_adaptive.cached_delay = utils.clamp(
                math.floor(defensive_adaptive.current_offset + 0.5),
                0,
                14
            )
            defensive_adaptive.last_calculation_tick = tick

            return defensive_adaptive.cached_delay
        end

        local function has_trigger(items, name)
            if items.triggers == nil or name == nil then
                return false
            end

            if items.triggers:get(name) then
                return true
            end

            local expected = tostring(name):lower()
            local values = { items.triggers:get() }

            for i = 1, #values do
                local value = values[i]

                if type(value) == 'table' then
                    for j = 1, #value do
                        if tostring(value[j]):lower() == expected then
                            return true
                        end
                    end
                elseif tostring(value):lower() == expected then
                    return true
                end
            end

            return false
        end

        local function get_esp_flag(entindex, bit_index)
            if entindex == nil then
                return false
            end

            local esp_data = entity.get_esp_data(entindex)

            if esp_data == nil or esp_data.flags == nil then
                return false
            end

            return bit.band(esp_data.flags, bit.lshift(1, bit_index)) ~= 0
        end

        local function is_defensive_window_active(items, defensive_data)
            if items.window == nil then
                return true
            end

            local mode = items.window:get()
            local left = defensive_data.left or 0

            if mode == 'Adaptive' then
                local tick = globals.tickcount()

                if left <= 0 then
                    if defensive_adaptive.last_defensive_tick > 0 then
                        if defensive_adaptive.was_active then
                            record_adaptive_result(true)
                            defensive_adaptive.consecutive_failures = 0
                            defensive_adaptive.performance_score = math.min(
                                1.0,
                                defensive_adaptive.performance_score + 0.05
                            )
                        else
                            defensive_adaptive.consecutive_failures = defensive_adaptive.consecutive_failures + 1

                            if defensive_adaptive.consecutive_failures >= 3 then
                                defensive_adaptive.performance_score = math.max(
                                    0.3,
                                    defensive_adaptive.performance_score - 0.1
                                )
                            end
                        end
                    end

                    defensive_adaptive.last_defensive_tick = 0
                    defensive_adaptive.was_active = false
                    defensive_adaptive.last_calculation_tick = nil
                    defensive_adaptive.cached_result = false
                    defensive_adaptive.velocity_history = { }
                    defensive_adaptive.enemy_aim_history = { }
                    defensive_adaptive.current_offset = 0
                    defensive_adaptive.direction = 1
                    defensive_adaptive.next_change_tick = 0

                    return false
                end

                if defensive_adaptive.last_defensive_tick == 0 then
                    defensive_adaptive.last_defensive_tick = tick
                    defensive_adaptive.was_active = true
                    defensive_adaptive.last_calculation_tick = nil
                end

                local delay = calculate_adaptive_delay()
                local active = left > delay

                if not active and left >= math.max(0, delay - 2) then
                    active = adaptive_chaos_random(1, 100) <= 30
                end

                if left <= 3 and not active then
                    active = true
                end

                defensive_adaptive.was_active = active
                defensive_adaptive.cached_result = active

                return active
            end

            if mode == 'Full' then
                return true
            end

            local max = math.max(defensive_data.max or 0, defensive_data.left or 0, 1)
            local progress = 1.0 - utils.clamp(left / max, 0.0, 1.0)

            if mode == 'Early' then
                return progress < 0.34
            end

            if mode == 'Middle' then
                return progress >= 0.34 and progress < 0.67
            end

            if mode == 'Late' then
                return progress >= 0.67
            end

            return true
        end

        local function should_force_defensive(items, defensive_data)
            if items.triggers == nil then
                return false
            end

            if has_trigger(items, 'Always') then
                return true
            end

            local me = entity.get_local_player()

            if me == nil then
                return false
            end

            if has_trigger(items, 'On weapon switch') then
                local next_attack = entity.get_prop(me, 'm_flNextAttack') or 0
                local ticks = toticks(next_attack - globals.curtime())

                if ticks > (defensive_data.left or 0) + 2 then
                    return true
                end
            end

            if has_trigger(items, 'On reload') then
                local weapon = entity.get_player_weapon(me)

                if get_esp_flag(me, 5) then
                    return true
                end

                if weapon ~= nil then
                    local next_attack = entity.get_prop(me, 'm_flNextAttack') or 0
                    local next_primary_attack = entity.get_prop(weapon, 'm_flNextPrimaryAttack') or 0
                    local next_attack_ticks = toticks(next_attack - globals.curtime())
                    local next_primary_ticks = toticks(next_primary_attack - globals.curtime())

                    if next_attack_ticks > 0 and next_primary_ticks > 0 then
                        return true
                    end
                end
            end

            local threat = client.current_threat()

            if has_trigger(items, 'On hittable') and get_esp_flag(threat, 11) then
                return true
            end

            if has_trigger(items, 'On dormant peek') and threat ~= nil then
                if entity.is_dormant(threat) then
                    if localplayer.is_vulnerable or get_esp_flag(me, 11) then
                        return true
                    end
                end
            end

            if has_trigger(items, 'On freestand') then
                local freestanding_ref = resource.antiaim.hotkeys.freestanding
                local custom_freestanding = (
                    freestanding_ref ~= nil
                    and freestanding_ref.enabled:get()
                    and freestanding_ref.hotkey:get()
                )

                if custom_freestanding or software.is_freestanding() then
                    return true
                end
            end

            return false
        end

        local function update_pitch_inverter()
            pitch_inverted = not pitch_inverted
        end

        local function update_modifier_inverter()
            modifier_delay_ticks = modifier_delay_ticks + 1
        end

        local function update_pitch(buffer, items)
            local value = items.pitch:get()

            local pitch_offset_1 = items.pitch_offset_1:get()
            local pitch_offset_2 = items.pitch_offset_2:get()

            local speed = items.pitch_speed:get()

            if value == 'Off' then
                return
            end

            if value == 'Static' then
                buffer.pitch = 'Custom'
                buffer.pitch_offset = pitch_offset_1

                return
            end

            if value == 'Sway' then
                local time = globals.realtime() * speed * 0.1
                local center = (pitch_offset_1 + pitch_offset_2) * 0.5
                local range = math.abs(pitch_offset_2 - pitch_offset_1) * 0.5
                local offset = center + math.sin(time) * range * (math.cos(time * 0.5) + 1) * 0.5

                buffer.pitch = 'Custom'
                buffer.pitch_offset = offset
            end

            if value == 'Spin' then
                local time = globals.curtime() * speed * 0.1
                local range = math.abs(pitch_offset_2 - pitch_offset_1)
                local center = (pitch_offset_1 + pitch_offset_2) * 0.5
                local offset = center + math.sin(time) * range * 0.5

                buffer.pitch = 'Custom'
                buffer.pitch_offset = utils.clamp(offset, -89, 89)

                return
            end

            if value == 'Cycling' then
                local cycle = math.abs(speed)
                local time = globals.curtime() * math.max(cycle, 1) * 0.1
                local progress = time % 1
                local offset = utils.lerp(
                    pitch_offset_1,
                    pitch_offset_2,
                    progress
                )

                buffer.pitch = 'Custom'
                buffer.pitch_offset = offset

                return
            end

            if value == 'Jitter' then
                local tickrate = math.floor(1 / globals.tickinterval())
                local speed_ticks = math.max(1, math.min(math.abs(speed * 0.1), 15))
                local interval = math.max(1, math.floor(tickrate / speed_ticks))
                local phase = math.floor(globals.tickcount() / interval) % 2

                buffer.pitch = 'Custom'
                buffer.pitch_offset = phase == 0
                    and pitch_offset_1
                    or pitch_offset_2

                return
            end

            if value == 'Switch' then
                local offset = pitch_inverted
                    and pitch_offset_2
                    or pitch_offset_1

                buffer.pitch = 'Custom'
                buffer.pitch_offset = offset

                return
            end

            if value == 'Random' then
                buffer.pitch = 'Custom'

                buffer.pitch_offset = utils.random_int(
                    pitch_offset_1, pitch_offset_2
                )

                return
            end

            if value == 'Randomize Jitter' then
                buffer.pitch = 'Custom'
                buffer.pitch_offset = utils.random_int(0, 1) == 0
                    and pitch_offset_1
                    or pitch_offset_2

                return
            end

            if value == 'Generated' then
                local exploit_data = exploit.get()
                local defensive_data = exploit_data.defensive

                if defensive_data.left <= 0 then
                    generated_pitch = nil
                elseif generated_pitch == nil then
                    generated_pitch = utils.random_int(
                        pitch_offset_1, pitch_offset_2
                    )
                end

                buffer.pitch = 'Custom'
                buffer.pitch_offset = generated_pitch or 0

                return
            end

            if value == 'Static Random' then
                local exp_data = exploit.get()
                local def_data = exp_data.defensive

                if def_data.left == def_data.max then
                    generated_pitch = utils.random_int(
                        pitch_offset_1, pitch_offset_2
                    )
                end

                buffer.pitch = 'Custom'
                buffer.pitch_offset = generated_pitch
            end
        end

        local function update_yaw(buffer, items)
            local value = items.yaw:get()

            local offset = items.yaw_offset:get()

            if value == 'Off' then
                return
            end

            buffer.freestanding = false

            buffer.yaw_left = 0
            buffer.yaw_right = 0

            buffer.yaw_offset = 0

            buffer.yaw_jitter = 'Off'
            buffer.jitter_offset = 0

            if value == 'Side Based' then
                buffer.yaw = '180'
                buffer.yaw_offset = 0

                buffer.yaw_left = -offset
                buffer.yaw_right = offset
            end

            if value == 'Opposite' then
                buffer.yaw = '180'
                buffer.yaw_offset = -180 + offset
            end

            if value == 'Spin' then
                buffer.yaw = '180'
                buffer.yaw_offset = globals.curtime() * (offset * 12) % 360
            end

            if value == 'Sway' then
                local speed = items.yaw_speed:get()

                local yaw_offset_1 = items.yaw_left:get()
                local yaw_offset_2 = items.yaw_right:get()

                local time = globals.realtime() * speed * 0.1
                local center = (yaw_offset_1 + yaw_offset_2) * 0.5
                local range = math.abs(yaw_offset_2 - yaw_offset_1) * 0.5
                local add = center + math.sin(time) * range * (math.cos(time * 0.5) + 1) * 0.5

                buffer.yaw = '180'
                buffer.yaw_offset = add
            end

            if value == 'Distortion' then
                local speed = items.yaw_speed:get()

                local yaw_offset_1 = items.yaw_left:get()
                local yaw_offset_2 = items.yaw_right:get()
                local center = (yaw_offset_1 + yaw_offset_2) * 0.5
                local range = math.abs(yaw_offset_2 - yaw_offset_1)
                local time = globals.curtime() * speed * 0.1
                local wobble = math.sin(time) * range * 0.5

                buffer.yaw = '180'
                buffer.yaw_offset = center + wobble

                return
            end

            if value == 'Freestand' then
                buffer.yaw = '180'
                buffer.yaw_offset = offset
                buffer.freestanding = true

                return
            end

            if value == 'Random' then
                local yaw_offset_1 = items.yaw_left:get()
                local yaw_offset_2 = items.yaw_right:get()
                local add = utils.random_int(
                    yaw_offset_1, yaw_offset_2
                )

                buffer.yaw = '180'
                buffer.yaw_offset = add
            end

            if value == 'Generated' then
                local exploit_data = exploit.get()
                local defensive_data = exploit_data.defensive

                if defensive_data.left <= 0 then
                    generated_yaw = nil
                elseif generated_yaw == nil then
                    local yaw_offset_1 = items.yaw_left:get()
                    local yaw_offset_2 = items.yaw_right:get()

                    generated_yaw = utils.random_int(
                        yaw_offset_1, yaw_offset_2
                    )
                end

                buffer.yaw = '180'
                buffer.yaw_offset = generated_yaw or 0
            end

            if value == 'Left/Right' then
                buffer.yaw = '180'
                buffer.yaw_offset = 0

                buffer.yaw_left = items.yaw_left:get()
                buffer.yaw_right = items.yaw_right:get()
            end

            if value == 'Static Random' then
                local exp_data = exploit.get()
                local def_data = exp_data.defensive

                if def_data.left == def_data.max then
                    local yaw_offset_1 = items.yaw_left:get()
                    local yaw_offset_2 = items.yaw_right:get()

                    generated_yaw = utils.random_int(
                        yaw_offset_1, yaw_offset_2
                    )
                end

                buffer.yaw = '180'
                buffer.yaw_offset = generated_yaw
            end

            if value == 'X-Way' then
                local ways_count = items.ways_count:get()
                local ways_custom = items.ways_custom:get()

                local stage = localplayer.sent_packets % ways_count

                if ways_custom then
                    local item_value = items['way_' .. stage + 1]

                    if item_value ~= nil then
                        local add = item_value:get()

                        buffer.yaw = '180'
                        buffer.yaw_offset = add
                    end
                else
                    local progress = stage / (ways_count - 1)
                    local add = utils.lerp(-offset, offset, progress)

                    buffer.yaw = '180'
                    buffer.yaw_offset = add
                end

                if items.ways_auto_body_yaw:get() then
                    local body_yaw_offset = 0

                    if buffer.yaw_offset < 0 then
                        body_yaw_offset = -1
                    end

                    if buffer.yaw_offset > 0 then
                        body_yaw_offset = 1
                    end

                    buffer.body_yaw = 'Static'
                    buffer.body_yaw_offset = body_yaw_offset
                end
            end

        end

        local function pick_defensive_angle_delay(state, items)
            return preset_runtime:pick_delay(state, items, 34)
        end

        local function capture_fields(target, fields)
            local held = { }

            for i = 1, #fields do
                local key = fields[i]
                held[key] = target[key]
            end

            return held
        end

        local function restore_fields(target, fields, held)
            if held == nil then
                return
            end

            for i = 1, #fields do
                local key = fields[i]
                target[key] = held[key]
            end
        end

        local function reset_angle_delay_state(state)
            state.items = nil
            state.mode = nil
            state.current = 1
            state.last = nil
            state.ticks = 0
            state.from = nil
            state.to = nil
            state.chaos = nil
            state.applied = nil
            state.pending = nil
            state.last_command = nil
        end

        local function update_hittable_angle_delay_reset()
            local me = entity.get_local_player()
            local hittable = get_esp_flag(me, 11)

            if hittable and not local_hittable_active then
                reset_angle_delay_state(defensive_angle_delay_state.pitch)
                reset_angle_delay_state(defensive_angle_delay_state.yaw)
            end

            local_hittable_active = hittable
        end

        local function apply_angle_delay(target, items, state, mode, enabled, fields, cmd)
            if not enabled or items.delay_from == nil or items.delay_to == nil then
                reset_angle_delay_state(state)
                return
            end

            local delay_from = items.delay_from:get()
            local delay_to = items.delay_to:get()
            local delay_chaos = items.delay_chaos ~= nil and items.delay_chaos:get() or 0

            if delay_from <= 1 and delay_to <= 1 then
                reset_angle_delay_state(state)
                return
            end

            local changed = (
                state.items ~= items
                or state.mode ~= mode
                or state.from ~= delay_from
                or state.to ~= delay_to
                or state.chaos ~= delay_chaos
            )

            if changed then
                state.items = items
                state.mode = mode
                state.from = delay_from
                state.to = delay_to
                state.chaos = delay_chaos
                state.current = pick_defensive_angle_delay(state, items)
                state.ticks = 0
                state.applied = capture_fields(target, fields)
                state.pending = state.applied
                state.last_command = nil
            end

            if state.applied == nil then
                state.applied = capture_fields(target, fields)
                state.pending = state.applied
                state.current = pick_defensive_angle_delay(state, items)
                state.ticks = 0
            end

            state.pending = capture_fields(target, fields)

            if state.last_command ~= cmd.command_number then
                state.last_command = cmd.command_number
                state.ticks = state.ticks + 1
            end

            if state.ticks >= state.current then
                state.applied = state.pending
                state.current = pick_defensive_angle_delay(state, items)
                state.ticks = 0
            end

            restore_fields(target, fields, state.applied)
        end

        local function update_body_yaw(buffer, items)
            if items.body_yaw == nil then
                return
            end

            local body_yaw = items.body_yaw:get()
            local body_yaw_offset = items.body_yaw_offset:get()

            local freestanding_body_yaw = false

            if body_yaw ~= 'Jitter' and body_yaw ~= 'Jitter Random' then
                freestanding_body_yaw = items.freestanding_body_yaw:get()
            end

            buffer.body_yaw = body_yaw
            buffer.body_yaw_offset = body_yaw_offset
            buffer.delay = 1

            buffer.freestanding_body_yaw = freestanding_body_yaw
        end

        function defensive:update(cmd)
            if cmd.chokedcommands == 0 then
                update_pitch_inverter()
                update_modifier_inverter()
            end
        end

        function defensive:apply(cmd, items)
            local is_duck_peek_active = software.is_duck_peek_assist()

            if not is_exploit_active() or is_duck_peek_active then
                return false
            end

            if not items.enabled:get() then
                return false
            end

            local exploit_data = exploit.get()
            local defensive_data = exploit_data.defensive
            update_hittable_angle_delay_reset()

            local trigger_active = should_force_defensive(items, defensive_data)

            if not trigger_active then
                return false
            end

            local trigger_tick_delay = items.trigger_tick_delay ~= nil
                and items.trigger_tick_delay:get()
                or 1

            if trigger_tick_delay > 1 and cmd.command_number % trigger_tick_delay ~= 0 then
                return false
            end

            cmd.force_defensive = 1

            local window_active = is_defensive_window_active(items, defensive_data)

            if defensive_data.left <= 0 then
                return false
            end

            if not window_active then
                return false
            end

            local buffer_ctx = { }

            update_body_yaw(buffer_ctx, items)
            update_pitch(buffer_ctx, items)
            update_yaw(buffer_ctx, items)

            local pitch_mode = items.pitch:get()
            local yaw_mode = items.yaw:get()
            local use_pitch_delay = pitch_mode ~= 'Off' and pitch_mode ~= 'Static'
            local use_yaw_delay = (
                yaw_mode ~= 'Off'
                and yaw_mode ~= 'Side Based'
                and yaw_mode ~= 'Opposite'
                and yaw_mode ~= 'Freestand'
                and yaw_mode ~= 'Left/Right'
            )

            apply_angle_delay(
                buffer_ctx, items, defensive_angle_delay_state.pitch,
                pitch_mode, use_pitch_delay, { 'pitch', 'pitch_offset' }, cmd
            )

            apply_angle_delay(
                buffer_ctx, items, defensive_angle_delay_state.yaw,
                yaw_mode, use_yaw_delay, {
                    'yaw', 'yaw_offset', 'yaw_left', 'yaw_right',
                    'yaw_jitter', 'jitter_offset', 'freestanding',
                    'body_yaw', 'body_yaw_offset', 'freestanding_body_yaw'
                }, cmd
            )

            buffer.defensive = buffer_ctx

            return true
        end
    end

    local fakelag_clone = { } do
        local ref = resource.antiaim.fakelag

        local HOTKEY_MODE = {
            [0] = 'Always on',
            [1] = 'On hotkey',
            [2] = 'Toggle',
            [3] = 'Off hotkey'
        }

        local function get_hotkey_value(_, mode, key)
            return HOTKEY_MODE[mode], key or 0
        end

        function fakelag_clone:update()
            override.set(software.antiaimbot.fake_lag.enabled[1], ref.enabled:get())
            override.set(software.antiaimbot.fake_lag.enabled[2], get_hotkey_value(ref.hotkey:get()))

            override.set(software.antiaimbot.fake_lag.amount, ref.amount:get())

            override.set(software.antiaimbot.fake_lag.variance, ref.variance:get())
            override.set(software.antiaimbot.fake_lag.limit, ref.limit:get())
        end

        function fakelag_clone:shutdown()
            override.unset(software.antiaimbot.fake_lag.enabled[1])
            override.unset(software.antiaimbot.fake_lag.enabled[2])

            override.unset(software.antiaimbot.fake_lag.amount)

            override.unset(software.antiaimbot.fake_lag.variance)
            override.unset(software.antiaimbot.fake_lag.limit)
        end
    end

    local builder = { } do
        local ref = resource.antiaim.builder

        local TEAM_T  = 2
        local TEAM_CT = 3

        local function get_move_direction(move_dir)
            local list = { }

            if move_dir.x > 0 then
                table.insert(list, 'Forward')
            end

            if move_dir.x < 0 then
                table.insert(list, 'Backward')
            end

            if move_dir.y > 0 then
                table.insert(list, 'Right')
            end

            if move_dir.y < 0 then
                table.insert(list, 'Left')
            end

            return table.concat(list, '-')
        end

        local function update_pitch(items)
            buffer.pitch = 'Default'
        end

        local function update_yaw_base(items)
            if items.yaw_base == nil then
                buffer.yaw_base = 'At targets'
            else
                buffer.yaw_base = items.yaw_base:get()
            end
        end

        local function update_yaw(items)
            local is_valid = (
                items.yaw_left ~= nil
                and items.yaw_right ~= nil
            )

            if not is_valid then
                return
            end

            local yaw_left = items.yaw_left:get()
            local yaw_right = items.yaw_right:get()

            local yaw_random = items.yaw_random:get()

            local random_left = yaw_left * yaw_random * 0.01
            local random_right = yaw_right * yaw_random * 0.01

            yaw_left = yaw_left + utils.random_int(-random_left, random_left)
            yaw_right = yaw_right + utils.random_int(-random_right, random_right)

            buffer.yaw = '180'
            buffer.yaw_offset = 0

            buffer.yaw_left = yaw_left
            buffer.yaw_right = yaw_right

            if items.yaw_direction ~= nil then
                local dir = get_move_direction(
                    localplayer.move_dir
                )

                local item_yaw_left = items['yaw_left_dir_' .. dir]
                local item_yaw_right = items['yaw_right_dir_' .. dir]

                if item_yaw_left ~= nil and item_yaw_right ~= nil then
                    buffer.yaw_left = item_yaw_left:get()
                    buffer.yaw_right = item_yaw_right:get()
                end
            end
        end

        local function update_jitter(items)
            if items.yaw_jitter == nil then
                return
            end

            local yaw_jitter = items.yaw_jitter:get()
            local jitter_mode = yaw_jitter
            local jitter_offset = items.jitter_offset:get()
            local is_dynamic_jitter = (
                yaw_jitter == 'Sway'
                or yaw_jitter == 'Randomized'
                or yaw_jitter == 'Center Flick'
                or yaw_jitter == 'Offset Flick'
            )

            if is_dynamic_jitter then
                local tick = globals.tickcount()
                local jitter_min = items.jitter_min ~= nil and items.jitter_min:get() or -60
                local jitter_max = items.jitter_max ~= nil and items.jitter_max:get() or 60
                local delay = items.jitter_delay ~= nil and items.jitter_delay:get() or 1
                local speed = items.jitter_speed ~= nil and items.jitter_speed:get() or 1
                local key = tostring(items.yaw_jitter)
                local jitter_random = items.jitter_random ~= nil and items.jitter_random:get() or 0
                local random_range = math.floor(math.abs(jitter_max - jitter_min) * 0.5 * jitter_random * 0.01 + 0.5)

                if yaw_jitter == 'Sway' then
                    jitter_offset = preset_runtime:get_sway(
                        key,
                        jitter_min,
                        jitter_max,
                        delay,
                        speed,
                        tick
                    )
                elseif yaw_jitter == 'Center Flick' or yaw_jitter == 'Offset Flick' then
                    jitter_offset = preset_runtime:get_flick(
                        key,
                        jitter_min,
                        jitter_max,
                        delay,
                        tick
                    )
                    yaw_jitter = yaw_jitter == 'Offset Flick' and 'Offset' or 'Center'
                else
                    jitter_offset = preset_runtime:get_randomized(
                        key,
                        jitter_min,
                        jitter_max,
                        delay,
                        tick
                    )
                end

                if random_range > 0 then
                    jitter_offset = jitter_offset + utils.random_int(
                        -random_range,
                        random_range
                    )
                end

                if jitter_mode == 'Sway' or jitter_mode == 'Randomized' then
                    yaw_jitter = 'Center'
                end
            elseif yaw_jitter ~= 'Off' then
                local random = items.jitter_random:get() * 0.01
                local random_offset = jitter_offset * random

                jitter_offset = jitter_offset + utils.random_int(
                    -random_offset, random_offset
                )
            end

            buffer.yaw_jitter = yaw_jitter
            buffer.jitter_offset = jitter_offset
        end

        local function pick_body_yaw_delay(items)
            return preset_runtime:pick_delay(delay_state, items, 20)
        end

        local function update_body_yaw_delay(items, body_yaw)
            local is_jitter = body_yaw == 'Jitter' or body_yaw == 'Jitter Random'

            if not is_jitter or items.delay_from == nil or items.delay_to == nil then
                delay_state.items = nil
                delay_state.body_yaw = nil
                delay_state.current = 1
                delay_state.from = nil
                delay_state.to = nil
                delay_state.chaos = nil
                delay_state.needs_update = true
                buffer.delay = 1
                return
            end

            local delay_from = items.delay_from:get()
            local delay_to = items.delay_to:get()
            local delay_chaos = items.delay_chaos ~= nil and items.delay_chaos:get() or 0
            local changed = (
                delay_state.items ~= items
                or delay_state.body_yaw ~= body_yaw
                or delay_state.from ~= delay_from
                or delay_state.to ~= delay_to
                or delay_state.chaos ~= delay_chaos
            )

            if changed then
                delay_state.items = items
                delay_state.body_yaw = body_yaw
                delay_state.from = delay_from
                delay_state.to = delay_to
                delay_state.chaos = delay_chaos
                delay_state.current = pick_body_yaw_delay(items)
                delay_state.needs_update = false
            elseif delay_state.needs_update then
                delay_state.current = pick_body_yaw_delay(items)
                delay_state.needs_update = false
            end

            buffer.delay = delay_state.current
        end

        local function update_body_yaw(items)
            if items.body_yaw == nil then
                return
            end

            local body_yaw = items.body_yaw:get()
            local body_yaw_offset = items.body_yaw_offset:get()

            local freestanding_body_yaw = false

            if body_yaw ~= 'Jitter' and body_yaw ~= 'Jitter Random' then
                freestanding_body_yaw = items.freestanding_body_yaw:get()
            end

            buffer.body_yaw = body_yaw
            buffer.body_yaw_offset = body_yaw_offset

            buffer.freestanding_body_yaw = freestanding_body_yaw

            update_body_yaw_delay(items, body_yaw)
        end

        function builder:get(state, team)
            local items = ref[state]

            if items == nil then
                return nil
            end

            return items[team]
        end

        function builder.get_team(player)
            local team = entity.get_prop(
                player, 'm_iTeamNum'
            )

            if team == TEAM_T then
                return 'Terrorist'
            end

            if team == TEAM_CT then
                return 'Counter-Terrorist'
            end

            return nil
        end

        function builder:is_active_ex(items)
            local angles = items.angles

            if angles == nil then
                return false
            end

            return angles.enabled == nil
                or angles.enabled:get()
        end

        function builder:is_active(state)
            local items = self:get(state)

            if items == nil then
                return false
            end

            return self:is_active_ex(items)
        end

        function builder:apply_ex(items)
            if items == nil then
                return false
            end

            local angles = items.angles

            if angles == nil then
                return false
            end

            buffer.enabled = true

            update_pitch(angles)
            update_yaw_base(angles)
            update_yaw(angles)
            update_jitter(angles)
            update_body_yaw(angles)

            return true
        end

        function builder:apply(state, team)
            local items = self:get(
                state, team
            )

            if items == nil then
                return false, nil
            end

            if not self:is_active_ex(items) then
                return false, items
            end

            local angles = items.angles

            if angles == nil then
                return false
            end

            self:apply_ex(items)
            return true, items
        end

        function builder:update(cmd, team)
            local states = statement.get()
            local state = states[#states]

            if state == nil then
                return false, nil, nil
            end

            local active, items = self:apply(
                state, team
            )

            if not active or items == nil then
                local _, new_items = self:apply(
                    'Default', team
                )

                if new_items ~= nil then
                    items = new_items
                    state = 'Default'
                end
            end

            return true, items, state
        end
    end

    local freestanding = { } do
        local ref = resource.antiaim.hotkeys.freestanding

        local last_ack_defensive_side = nil
        local freestanding_side = nil

        local function is_value_near(value, target)
            return math.abs(target - value) <= 2.0
        end

        local function get_target_yaw(player)
            local threat = client.current_threat()

            if threat == nil then
                return nil
            end

            local player_origin = vector(
                entity.get_origin(player)
            )

            local threat_origin = vector(
                entity.get_origin(threat)
            )

            local delta = threat_origin - player_origin
            local _, yaw = delta:angles()

            return yaw - 180
        end

        local function get_approximated_side(yaw)
            if is_value_near(yaw, -90) then
                return -90
            end

            if is_value_near(yaw, 90) then
                return 90
            end

            return nil
        end

        local function get_side()
            local me = entity.get_local_player()

            if me == nil then
                return nil
            end

            local entity_data = c_entity(me)

            if entity_data == nil then
                return nil
            end

            local animstate = entity_data:get_anim_state()

            if animstate == nil then
                return nil
            end

            local target_yaw = get_target_yaw(me)

            if target_yaw == nil then
                return nil
            end

            return get_approximated_side(
                utils.normalize(animstate.eye_angles_y - target_yaw, -180, 180)
            )
        end

        local function get_state()
            if not localplayer.is_onground then
                return 'Air'
            end

            if localplayer.is_crouched then
                return 'Crouched'
            end

            if localplayer.is_moving then
                if software.is_slow_motion() then
                    return 'Slow Walk'
                end

                return 'Moving'
            end

            return 'Standing'
        end

        local function is_disabled()
            return ref.disablers:get(
                get_state()
            )
        end

        local function is_enabled()
            if ui.is_menu_open() then
                return false
            end

            if not ref.enabled:get() then
                return false
            end

            if not ref.hotkey:get() then
                return false
            end

            return not is_disabled()
        end

        local function update_freestanding_options(cmd, team)
            local items = builder:get(
                'Freestanding', team
            )

            if items ~= nil and items.override ~= nil and not items.override:get() then
                items = nil
            end

            if freestanding_side ~= nil then
                buffer.pitch = 'Default'

                if items ~= nil then
                    builder:apply_ex(items)
                end
            end

            if localplayer.is_vulnerable then
                if items ~= nil and items.defensive ~= nil then
                    if defensive:apply(cmd, items.defensive) then
                        local yaw_offset = buffer.defensive.yaw_offset

                        if yaw_offset ~= nil and last_ack_defensive_side ~= nil then
                            buffer.defensive.yaw_offset = yaw_offset + last_ack_defensive_side
                        end
                    else
                        if freestanding_side ~= nil then
                            last_ack_defensive_side = freestanding_side
                        end
                    end
                end
            end
        end

        function freestanding:update(cmd, team)
            if not is_enabled() then
                freestanding_side = nil
                return
            end

            if cmd.chokedcommands == 0 then
                freestanding_side = get_side()
            end

            buffer.freestanding = true
            update_freestanding_options(cmd, team)
        end
    end

    local antiaim_on_use = { } do
        local is_interact_traced = false

        local function should_update(cmd, items)
            local me = entity.get_local_player()

            if me == nil then
                return false
            end

            local weapon = entity.get_player_weapon(me)

            if weapon == nil then
                return false
            end

            local weapon_info = csgo_weapons(weapon)

            if weapon_info == nil then
                return false
            end

            local team = entity.get_prop(me, 'm_iTeamNum')
            local my_origin = vector(entity.get_origin(me))

            local is_weapon_bomb = weapon_info.idx == 49

            local is_defusing = entity.get_prop(me, 'm_bIsDefusing') == 1
            local is_rescuing = entity.get_prop(me, 'm_bIsGrabbingHostage') == 1

            local in_bomb_site = entity.get_prop(me, 'm_bInBombZone') == 1

            if is_defusing or is_rescuing then
                return false
            end

            if in_bomb_site then
                local angles = items.angles

                if not angles.bomb_e_fix:get() or is_weapon_bomb then
                    return false
                end
            end

            if team == 3 and cmd.pitch > 15 then
                local bombs = entity.get_all 'CPlantedC4'

                for i = 1, #bombs do
                    local bomb = bombs[i]

                    local origin = vector(
                        entity.get_origin(bomb)
                    )

                    local delta = origin - my_origin
                    local distancesqr = delta:lengthsqr()

                    if distancesqr < (62 * 62) then
                        return false
                    end
                end
            end

            local camera = vector(client.camera_angles())
            local forward = vector():init_from_angles(camera:unpack())

            local eye_pos = vector(client.eye_position())
            local end_pos = eye_pos + forward * 128

            local fraction, entindex = client.trace_line(
                me, eye_pos.x, eye_pos.y, eye_pos.z, end_pos.x, end_pos.y, end_pos.z
            )

            if fraction ~= 1 then
                if entindex == -1 then
                    return true
                end

                local classname = entity.get_classname(entindex)

                if classname == 'CWorld' then
                    return true
                end

                if classname == 'CFuncBrush' then
                    return true
                end

                if classname == 'CCSPlayer' then
                    return true
                end

                if classname == 'CHostage' then
                    local origin = vector(entity.get_origin(entindex))
                    local distance = eye_pos:distsqr(origin)

                    if distance < (84 * 84) then
                        return false
                    end
                end

                if not is_interact_traced then
                    is_interact_traced = true
                    return false
                end
            end

            return true
        end

        function antiaim_on_use:update(cmd, team)
            if cmd.in_use == 0 then
                is_interact_traced = false

                return false
            end

            local items = builder:get(
                'Legit AA', team
            )

            if items == nil then
                return false
            end

            local angles = items.angles

            if angles == nil then
                return false
            end

            if angles.enabled ~= nil and not angles.enabled:get() then
                return false
            end

            if not should_update(cmd, items) then
                return false
            end

            buffer.yaw_base = 'Local view'

            builder:apply_ex(items)

            buffer.pitch = 'Custom'
            buffer.pitch_offset = cmd.pitch

            if items ~= nil and items.defensive ~= nil then
                defensive:apply(cmd, items.defensive)
            end

            buffer.yaw_offset = buffer.yaw_offset + 180
            buffer.freestanding = false

            cmd.in_use = 0

            return true
        end
    end

    local roll_aa = { } do
        local ref = resource.antiaim.hotkeys.roll_aa

        function roll_aa:apply(cmd)
            if not ref.enabled:get() then
                return false
            end

            cmd.roll = ref.value:get()

            return true
        end

        function roll_aa:update(cmd, team)
            if not ref.enabled:get() then
                return false
            end

            if not ref.hotkey:get() then
                return
            end

            cmd.roll = ref.value:get()

            builder:apply('Roll AA', team)
        end
    end

    local manual_yaw = { } do
        local ref = resource.antiaim.hotkeys.manual_yaw

        local current_dir = nil
        local hotkey_data = { }

        local dir_rotations = {
            ['left'] = -90,
            ['right'] = 90,
            ['forward'] = 180,
            ['backward'] = 0
        }

        local function get_hotkey_state(old_state, state, mode)
            if mode == 1 or mode == 2 then
                return old_state ~= state
            end

            return false
        end

        local function update_hotkey_state(data, state, mode)
            local active = get_hotkey_state(
                data.state, state, mode
            )

            data.state = state

            return active
        end

        local function update_hotkey_data(id, dir)
            local state, mode = ui.get(id)

            if hotkey_data[id] == nil then
                hotkey_data[id] = {
                    state = state
                }
            end

            local changed = update_hotkey_state(
                hotkey_data[id], state, mode
            )

            if not changed then
                return
            end

            if current_dir == dir then
                current_dir = nil
            else
                current_dir = dir
            end
        end

        local function on_paint_ui()
            update_hotkey_data(ref.left_hotkey.ref, 'left')
            update_hotkey_data(ref.right_hotkey.ref, 'right')
            update_hotkey_data(ref.forward_hotkey.ref, 'forward')
            update_hotkey_data(ref.backward_hotkey.ref, 'backward')

            update_hotkey_data(ref.reset_hotkey.ref, nil)
        end

        function manual_yaw:get()
            return current_dir
        end

        function manual_yaw:update(cmd, team)
            local angle = dir_rotations[
                current_dir
            ]

            if angle == nil then
                return false
            end

            local yaw = buffer.yaw_offset or 0

            buffer.enabled = true

            buffer.yaw_offset = yaw + angle

            buffer.edge_yaw = false
            buffer.freestanding = false

            buffer.roll = 0

            buffer.defensive = nil

            if ref.options:get 'Disable yaw modifiers' then
                buffer.yaw_offset = yaw + angle

                buffer.yaw_left = 0
                buffer.yaw_right = 0

                buffer.yaw_jitter = 'Off'
                buffer.jitter_offset = 0
            end

            if ref.options:get 'Freestanding body' then
                buffer.body_yaw = 'Static'
                buffer.body_yaw_offset = 180
                buffer.freestanding_body_yaw = true
            end

            local state, items = builder:apply(
                'Manual AA', team
            )

            roll_aa:apply(cmd)

            if state and items ~= nil then
                if items.defensive ~= nil then
                    local applied = defensive:apply(
                        cmd, items.defensive
                    )

                    if not applied then
                        goto continue
                    end

                    local defensive_buffer = buffer.defensive

                    if defensive_buffer ~= nil and defensive_buffer.yaw_offset ~= nil then
                        defensive_buffer.yaw_offset = defensive_buffer.yaw_offset + angle
                    end

                    ::continue::
                end

                buffer.yaw_offset = buffer.yaw_offset + angle
            end

            buffer.yaw_base = 'Local view'

            return true
        end

        local callbacks do
            local function update_event_callbacks(value)
                if not value then
                    current_dir = nil
                end

                utils.event_callback(
                    'paint_ui',
                    on_paint_ui,
                    value
                )
            end

            local function on_enabled(item)
                update_event_callbacks(item:get())
            end

            ref.enabled:set_callback(
                on_enabled, true
            )
        end

        antiaim.manual_yaw = manual_yaw
    end

    local avoid_backstab = { } do
        local ref = resource.antiaim.features.avoid_backstab

        local function is_weapon_knife(weapon)
            local weapon_info = csgo_weapons(weapon)

            if weapon_info == nil then
                return false
            end

            -- is weapon taser
            if weapon_info.idx == 31 then
                return false
            end

            if weapon_info.type ~= 'knife' then
                return false
            end

            return true
        end

        local function is_player_weapon_knife(player)
            local weapon = entity.get_player_weapon(player)

            if weapon == nil then
                return false
            end

            return is_weapon_knife(weapon)
        end

        local function get_targets(player)
            local targets = { }

            local player_team = entity.get_prop(player, 'm_iTeamNum')
            local player_resource = entity.get_player_resource()

            for i = 1, globals.maxplayers() do
                local is_connected = entity.get_prop(
                    player_resource, 'm_bConnected', i
                )

                if is_connected ~= 1 then
                    goto continue
                end

                local team = entity.get_prop(
                    player_resource, 'm_iTeam', i
                )

                if player == i or player_team == team then
                    goto continue
                end

                local is_alive = entity.get_prop(
                    player_resource, 'm_bAlive', i
                )

                if is_alive then
                    table.insert(targets, i)
                end

                ::continue::
            end

            return targets
        end

        local function get_backstab_angle(player)
            local best_delta = nil
            local best_target = nil
            local best_distancesqr = math.huge

            local origin = vector(
                entity.get_origin(player)
            )

            local me = entity.get_local_player()

            if me == nil then
                return false
            end

            local enemies = get_targets(me)

            for i = 1, #enemies do
                local enemy = enemies[i]

                if not is_player_weapon_knife(enemy) then
                    goto continue
                end

                local enemy_origin = vector(
                    entity.get_origin(enemy)
                )

                local delta = enemy_origin - origin
                local distancesqr = delta:lengthsqr()

                if distancesqr < best_distancesqr then
                    best_distancesqr = distancesqr

                    best_delta = delta
                    best_target = enemy
                end

                ::continue::
            end

            return best_target, best_distancesqr, best_delta
        end

        function avoid_backstab:update()
            if not ref.enabled:get() then
                return
            end

            local me = entity.get_local_player()

            if me == nil then
                return false
            end

            local target, distancesqr, delta = get_backstab_angle(me)

            local max_distance = ref.distance:get()
            local max_distance_sqr = max_distance * max_distance

            if target == nil or distancesqr > max_distance_sqr then
                return false
            end

            local angle = vector(
                delta:angles()
            )

            buffer.enabled = true
            buffer.yaw_base = 'Local view'

            buffer.yaw = 'Static'
            buffer.yaw_offset = angle.y

            buffer.freestanding_body_yaw = false

            buffer.edge_yaw = false
            buffer.freestanding = false

            buffer.roll = 0

            return true
        end
    end

    local backtrack_disruptor = { } do
        local ref = resource.antiaim.features.backtrack_disruptor
        local next_pulse_command = 0

        local function is_exploit_ready()
            if not software.is_double_tap_active() and not software.is_on_shot_antiaim_active() then
                return false
            end

            if software.is_duck_peek_assist() then
                return false
            end

            return true
        end

        local function is_builder_defensive_enabled(items)
            return items ~= nil
                and items.defensive ~= nil
                and items.defensive.enabled ~= nil
                and items.defensive.enabled:get()
        end

        local function get_state()
            if not localplayer.is_onground then
                if localplayer.is_crouched then
                    return 'Air-Crouch'
                end

                return 'Air'
            end

            if localplayer.is_crouched then
                if localplayer.is_moving then
                    return 'Move-Crouch'
                end

                return 'Crouch'
            end

            if localplayer.is_moving then
                if software.is_slow_motion() then
                    return 'Slow Walk'
                end

                return 'Moving'
            end

            return 'Standing'
        end

        local function is_state_active()
            return ref.mode:get(
                get_state()
            )
        end

        local function schedule_next(cmd)
            local delay_min = ref.delay_min:get()
            local delay_max = ref.delay_max:get()

            if delay_min > delay_max then
                delay_min, delay_max = delay_max, delay_min
            end

            next_pulse_command = cmd.command_number + utils.random_int(delay_min, delay_max)
        end

        function backtrack_disruptor:update(cmd, items)
            if not ref.enabled:get() then
                next_pulse_command = 0
                return
            end

            if is_builder_defensive_enabled(items) then
                next_pulse_command = 0
                return
            end

            if not is_exploit_ready() then
                next_pulse_command = 0
                return
            end

            if cmd.force_defensive == 1 or cmd.in_attack == 1 or cmd.in_attack2 == 1 then
                return
            end

            local exploit_data = exploit.get()

            if exploit_data.defensive.left > 0 then
                return
            end

            if not is_state_active() then
                next_pulse_command = 0
                return
            end

            if next_pulse_command == 0 then
                schedule_next(cmd)
                return
            end

            if cmd.command_number < next_pulse_command then
                return
            end

            cmd.force_defensive = 1
            schedule_next(cmd)
        end
    end

    local warmup_round_end = { } do
        local ref = resource.antiaim.features.warmup_round_end

        local function are_enemies_dead()
            local me = entity.get_local_player()

            if me == nil then
                return false
            end

            local my_team = entity.get_prop(me, 'm_iTeamNum')
            local player_resource = entity.get_player_resource()

            for i = 1, globals.maxplayers() do
                local is_connected = entity.get_prop(
                    player_resource, 'm_bConnected', i
                )

                if is_connected ~= 1 then
                    goto continue
                end

                local player_team = entity.get_prop(
                    player_resource, 'm_iTeam', i
                )

                if me == i or player_team == my_team then
                    goto continue
                end

                local is_alive = entity.get_prop(
                    player_resource, 'm_bAlive', i
                )

                if is_alive == 1 then
                    return false
                end

                ::continue::
            end

            return true
        end

        local function should_update()
            local game_rules = entity.get_game_rules()

            if game_rules == nil then
                return false
            end

            local warmup_period = entity.get_prop(
                game_rules, 'm_bWarmupPeriod'
            )

            if warmup_period == 1 then
                return true
            end

            if are_enemies_dead() then
                return true
            end

            return false
        end

        function warmup_round_end:update()
            if not ref.enabled:get() then
                return false
            end

            if not should_update() then
                return false
            end

            buffer.enabled = true

            buffer.pitch = 'Custom'
            buffer.pitch_offset = 0

            buffer.yaw = 'Spin'
            buffer.yaw_offset = 100

            buffer.yaw_jitter = 'Off'
            buffer.jitter_offset = 0

            buffer.body_yaw = 'Static'
            buffer.body_yaw_offset = 1

            buffer.freestanding_body_yaw = false

            buffer.defensive = nil

            buffer.edge_yaw = false
            buffer.freestanding = false

            return true
        end
    end

    local flick_exploit = { } do
        local ref = resource.antiaim.features.flick_exploit

        local pitch_inverted = false
        local generated_pitch = 0

        local freestand_side = -1

        local function get_state()
            if not localplayer.is_onground then
                if localplayer.is_crouched then
                    return 'Air-Crouch'
                end

                return 'Air'
            end

            if localplayer.is_crouched then
                if localplayer.is_moving then
                    return 'Move-Crouch'
                end

                return 'Crouch'
            end

            if localplayer.is_moving then
                if software.is_slow_motion() then
                    return 'Slow Walk'
                end

                return 'Moving'
            end

            return 'Standing'
        end

        local function should_update()
            local exp_data = exploit.get()

            if not exp_data.shift then
                return false
            end

            local me = entity.get_local_player()

            if me == nil then
                return false
            end

            local weapon = entity.get_player_weapon(me)

            if weapon == nil then
                return false
            end

            local weapon_info = csgo_weapons(weapon)

            if weapon_info == nil or weapon_info.is_revolver then
                return false
            end

            local state = get_state()

            if state == nil then
                return false
            end

            return ref.states:get(state)
        end

        local function get_angles(player, target)
            local player_origin = vector(entity.get_origin(player))
            local target_origin = vector(entity.get_origin(target))

            return vector((target_origin - player_origin):angles())
        end

        local function update_freestand(cmd)
            local me = entity.get_local_player()

            if me == nil then
                return
            end

            local threat = client.current_threat()

            if threat == nil then
                return
            end

            local angles = get_angles(me, threat)

            local eye_pos = vector(utils.get_eye_position(me))
            local stomach = vector(entity.hitbox_position(threat, 3))

            local forward_left = vector():init_from_angles(0, angles.y + 90)
            local forward_right = vector():init_from_angles(0, angles.y - 90)

            local point_left = eye_pos + forward_left * 31
            local point_right = eye_pos + forward_right * 31

            local ent_left, damage_left = client.trace_bullet(
                me, point_left.x, point_left.y, point_left.z,
                stomach.x, stomach.y, stomach.z, false
            )

            local ent_right, damage_right = client.trace_bullet(
                me, point_right.x, point_right.y, point_right.z,
                stomach.x, stomach.y, stomach.z, false
            )

            if ent_left ~= threat then
                damage_left = 0
            end

            if ent_right ~= threat then
                damage_right = 0
            end

            local should_update = (
                (damage_left > 0 or damage_right > 0)
                and damage_left ~= damage_right
            )

            if should_update then
                freestand_side = (damage_left > damage_right) and -1 or 1
            end
        end

        local function update_pitch(buffer, items)
            local value = items.pitch:get()

            local pitch_offset_1 = items.pitch_offset_1:get()
            local pitch_offset_2 = items.pitch_offset_2:get()

            local speed = items.pitch_speed:get()

            if value == 'Off' then
                return
            end

            if value == 'Static' then
                buffer.pitch = 'Custom'
                buffer.pitch_offset = pitch_offset_1

                return
            end

            if value == 'Sway' then
                local time = globals.curtime() * speed * 0.1

                local offset = utils.lerp(
                    pitch_offset_1,
                    pitch_offset_2,
                    time % 1
                )

                buffer.pitch = 'Custom'
                buffer.pitch_offset = offset
            end

            if value == 'Switch' then
                local offset = pitch_inverted
                    and pitch_offset_2
                    or pitch_offset_1

                buffer.pitch = 'Custom'
                buffer.pitch_offset = offset

                return
            end

            if value == 'Random' then
                buffer.pitch = 'Custom'

                buffer.pitch_offset = utils.random_int(
                    pitch_offset_1, pitch_offset_2
                )

                return
            end

            if value == 'Generated' then
                local exploit_data = exploit.get()
                local defensive_data = exploit_data.defensive

                if defensive_data.left <= 0 then
                    generated_pitch = nil
                elseif generated_pitch == nil then
                    generated_pitch = utils.random_int(
                        pitch_offset_1, pitch_offset_2
                    )
                end

                buffer.pitch = 'Custom'
                buffer.pitch_offset = generated_pitch or 0

                return
            end

            if value == 'Static Random' then
                local exp_data = exploit.get()
                local def_data = exp_data.defensive

                if def_data.left == def_data.max then
                    generated_pitch = utils.random_int(
                        pitch_offset_1, pitch_offset_2
                    )
                end

                buffer.pitch = 'Custom'
                buffer.pitch_offset = generated_pitch
            end
        end

        function flick_exploit:update(cmd)
            if not ref.enabled:get() then
                return false
            end

            if not should_update() then
                return false
            end

            update_freestand(cmd)

            local inverter = freestand_side == -1
            local defensive = exploit.get().defensive

            local is_defensive_active = defensive.left ~= 0
            cmd.force_defensive = cmd.command_number % 7 == 0

            local buffer_ctx = { }

            buffer_ctx.pitch = is_defensive_active and 'Custom' or 'Default'
            buffer_ctx.pitch_offset = 0

            buffer_ctx.yaw_base = 'At targets'

            buffer_ctx.yaw = '180'
            buffer_ctx.yaw_offset = is_defensive_active and 90 or 0

            buffer_ctx.yaw_left = 0
            buffer_ctx.yaw_right = 0

            buffer_ctx.yaw_jitter = 'Off'
            buffer_ctx.jitter_offset = 0

            buffer_ctx.body_yaw = 'Static'
            buffer_ctx.body_yaw_offset = is_defensive_active and -1 or 1

            buffer_ctx.freestanding_body_yaw = false

            buffer_ctx.edge_yaw = false
            buffer_ctx.freestanding = false

            buffer_ctx.roll = 0

            if cmd.chokedcommands == 0 then
                pitch_inverted = not pitch_inverted
            end

            update_pitch(buffer_ctx, ref)

            if inverter then
                buffer_ctx.yaw_offset = -buffer_ctx.yaw_offset
                -- buffer_ctx.body_yaw_offset = -buffer_ctx.body_yaw_offset
            end

            buffer.defensive = buffer_ctx
        end
    end

    local function update_antiaims(cmd)
        fakelag_clone:update()

        local me = entity.get_local_player()

        if me == nil then
            return
        end

        local team = builder.get_team(me)

        if team == nil then
            return
        end

        local active, items, state = builder:update(cmd, team)

        defensive:update(cmd)
        backtrack_disruptor:update(cmd, active and items or nil)

        if antiaim_on_use:update(cmd, team) then
            return
        end

        if manual_yaw:update(cmd, team) then
            return
        end

        if avoid_backstab:update() then
            return
        end

        roll_aa:update(cmd, team)

        if active and items ~= nil and items.defensive ~= nil then
            defensive:apply(cmd, items.defensive)
        end

        edge_yaw:update(cmd)
        freestanding:update(cmd, team)

        if not safe_head:update(cmd) then
            flick_exploit:update(cmd)
        end

        warmup_round_end:update()
    end

    local function update_defensive(cmd)
        local list = buffer.defensive

        local is_exploit_active = (
            software.is_double_tap_active()
            or software.is_on_shot_antiaim_active()
        )

        if software.is_duck_peek_assist() then
            is_exploit_active = false
        end

        if not is_exploit_active then
            return false
        end

        local exp_data = exploit.get()
        local defensive = exp_data.defensive

        local is_valid = (
            list ~= nil and
            defensive.left > 0
        )

        if not is_valid then
            return
        end

        buffer:copy(list)
    end

    local function update_inverter()
        local delay = math.max(
            1, buffer.delay or 1
        )

        local is_delay_body_yaw = (
            buffer.body_yaw == 'Jitter'
            or buffer.body_yaw == 'Jitter Random'
        )

        if is_delay_body_yaw then
            delay_ticks = delay_ticks + 1

            if delay_ticks < delay then
                return
            end
        else
            delay_ticks = 0
        end

        local should_invert = true

        if buffer.body_yaw == 'Jitter Random' then
            should_invert = utils.random_int(0, 1) == 0
        end

        inverts = inverts + 1

        if should_invert then
            inverted = not inverted
        end

        delay_ticks = 0

            if is_delay_body_yaw then
                delay_state.needs_update = true
            end
        end

    local function update_yaw_offset()
        if buffer.body_yaw_offset == nil then
            return
        end

        if buffer.yaw_left ~= nil and buffer.yaw_right ~= nil then
            local yaw = buffer.yaw_offset or 0

            if buffer.body_yaw_offset < 0 then
                buffer.yaw_offset = yaw + buffer.yaw_left
            end

            if buffer.body_yaw_offset > 0 then
                buffer.yaw_offset = yaw + buffer.yaw_right
            end

            return
        end
    end

    local function update_yaw_jitter()
        if buffer.yaw_jitter == 'Offset' then
            local yaw = buffer.yaw_offset or 0
            local offset = buffer.jitter_offset

            buffer.yaw_jitter = 'Off'
            buffer.jitter_offset = 0

            buffer.yaw_offset = yaw + (inverted and offset or 0)

            return
        end

        if buffer.yaw_jitter == 'Center' then
            local yaw = buffer.yaw_offset or 0
            local offset = buffer.jitter_offset

            if not inverted then
                offset = -offset
            end

            buffer.yaw_jitter = 'Off'
            buffer.jitter_offset = 0

            buffer.yaw_offset = yaw + offset / 2

            return
        end

        if buffer.yaw_jitter == 'Skitter' then
            local multiplier = preset_runtime:get_skitter_multiplier(inverts)

            local yaw = buffer.yaw_offset or 0
            local offset = buffer.jitter_offset

            buffer.yaw_jitter = 'Off'
            buffer.jitter_offset = 0

            buffer.yaw_offset = yaw + (offset * multiplier)

            return
        end

        if buffer.yaw_jitter == 'Spin' then
            local time = globals.curtime() * 3

            local yaw = buffer.yaw_offset or 0
            local offset = buffer.jitter_offset

            buffer.yaw_jitter = 'Off'
            buffer.jitter_offset = 0

            buffer.yaw_offset = yaw + utils.lerp(
                -offset, offset, time % 1
            )

            return
        end
    end

    local function update_body_yaw()
        if buffer.body_yaw == 'Jitter' then
            local offset = buffer.body_yaw_offset

            if offset == 0 then
                offset = 1
            end

            if not inverted then
                offset = -offset
            end

            buffer.body_yaw = 'Static'
            buffer.body_yaw_offset = offset
        end

        if buffer.body_yaw == 'Jitter Random' then
            local offset = buffer.body_yaw_offset

            if offset == 0 then
                offset = 1
            end

            buffer.body_yaw = 'Static'
            buffer.body_yaw_offset = inverted and offset or -offset
        end
    end

    local function update_buffer(cmd)
        update_defensive(cmd)

        if cmd.chokedcommands == 0 then
            update_inverter()
        end

        update_body_yaw()
        update_yaw_jitter()
        update_yaw_offset()
    end

    local function on_shutdown()
        fakelag_clone:shutdown()
        buffer:unset()
    end

    local function on_pre_config_save()
        fakelag_clone:shutdown()
        buffer:unset()
    end

    local function on_setup_command(cmd)
        buffer:clear()
        buffer:unset()

        update_antiaims(cmd)
        update_buffer(cmd)

        buffer:set()
    end

    utils.event_callback(
        'shutdown',
        on_shutdown
    )

    utils.event_callback(
        'pre_config_save',
        on_pre_config_save
    )

    utils.event_callback(
        'setup_command',
        on_setup_command
    )
end





    return antiaim
end

function M.health()
    return true
end

return M
