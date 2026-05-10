local M = {}

function M.start(deps)
    local resource = assert(deps.resource, 'rage_auto_whitelist_broken_lc: resource dependency is required')
    local entity = assert(deps.entity, 'rage_auto_whitelist_broken_lc: entity dependency is required')
    local client = assert(deps.client, 'rage_auto_whitelist_broken_lc: client dependency is required')
    local globals = assert(deps.globals, 'rage_auto_whitelist_broken_lc: globals dependency is required')
    local vector = assert(deps.vector, 'rage_auto_whitelist_broken_lc: vector dependency is required')
    local plist = assert(deps.plist, 'rage_auto_whitelist_broken_lc: plist dependency is required')
    local utils = assert(deps.utils, 'rage_auto_whitelist_broken_lc: utils dependency is required')
    local toticks = assert(deps.toticks, 'rage_auto_whitelist_broken_lc: toticks dependency is required')
    local software = assert(deps.software, 'rage_auto_whitelist_broken_lc: software dependency is required')

    local ref = resource.main.ragebot.auto_whitelist_broken_lc
    local records = {}
    local whitelist_state = {}

    local function get_origin(player)
        local x, y, z = entity.get_origin(player)

        if x == nil then
            return nil
        end

        return vector(x, y, z)
    end

    local function get_velocity(player)
        local x, y, z = entity.get_prop(player, 'm_vecVelocity')

        return vector(x or 0, y or 0, z or 0)
    end

    local function get_speed2d(velocity)
        return math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
    end

    local function get_simulation_tick(player)
        local simulation_time = entity.get_prop(player, 'm_flSimulationTime') or 0

        return toticks(simulation_time)
    end

    local function set_whitelist(player, value)
        if player == nil then
            return
        end

        local state = whitelist_state[player]

        if state == nil then
            state = {
                original = plist.get(player, 'Add to whitelist'),
                applied = false
            }

            whitelist_state[player] = state
        end

        if state.applied == value then
            return
        end

        plist.set(player, 'Add to whitelist', value)
        state.applied = value
    end

    local function restore_whitelist(player)
        local state = whitelist_state[player]

        if state == nil then
            return
        end

        plist.set(player, 'Add to whitelist', state.original)
        whitelist_state[player] = nil
    end

    local function restore_all_whitelists()
        for player in pairs(whitelist_state) do
            restore_whitelist(player)
        end
    end

    local function clamp01(value)
        return utils.clamp(value, 0, 1)
    end

    local function get_latency_ticks()
        if client.latency == nil then
            return 0
        end

        return utils.clamp(
            math.floor(client.latency() / globals.tickinterval() + 0.5),
            0,
            16
        )
    end

    local function is_onground(player)
        local flags = entity.get_prop(player, 'm_fFlags') or 0

        return flags % 2 == 1
    end

    local function get_lc_context(origin, previous, tick_delta, speed, airborne)
        local distance_delta = math.sqrt((origin - previous.origin):lengthsqr())
        local distance_limit = ref.distance:get()
        local break_distance = utils.clamp(44 + speed * 0.06, distance_limit, 96)

        if airborne then
            break_distance = break_distance * 0.85
        end

        local sim_gap = math.abs(tick_delta)
        local sim_score = clamp01((sim_gap - 1) / 12)
        local distance_score = clamp01(
            (distance_delta - break_distance * 0.55) / math.max(1, break_distance)
        )
        local speed_score = clamp01((speed - 35) / 230)
        local confidence

        if tick_delta < 0 then
            confidence = 0.86 + speed_score * 0.14
        else
            confidence = sim_score * 0.45
                + distance_score * 0.40
                + speed_score * 0.25
                + (airborne and 0.15 or 0)
        end

        confidence = clamp01(confidence)

        return {
            airborne = airborne,
            break_distance = break_distance,
            confidence = confidence,
            distance_delta = distance_delta,
            is_signal = tick_delta < 0 or (
                tick_delta > 1
                and tick_delta <= 64
                and confidence >= 0.34
                and distance_delta > math.max(18, distance_limit * 0.45)
                and speed > 15
            ),
            speed = speed
        }
    end

    local function get_adaptive_max_ticks(airborne, speed)
        local max_time = airborne and 0.25 or 0.20
        local ticks = math.floor(max_time / globals.tickinterval() + 0.5)

        if speed > 280 then
            ticks = ticks + 2
        elseif speed > 220 then
            ticks = ticks + 1
        end

        return utils.clamp(ticks, 8, 22)
    end

    local function get_predict_ticks(tick_delta, context)
        local latency_ticks = get_latency_ticks()
        local base_ticks = tick_delta < 0
            and math.abs(tick_delta)
            or math.max(1, tick_delta - 1)

        local lead_ticks = 1
            + math.floor(context.confidence * 3 + 0.5)
            + utils.clamp(math.floor(latency_ticks * 0.20 + 0.5), 0, 2)

        if context.airborne then
            lead_ticks = lead_ticks + 1 + math.floor(context.confidence * 2 + 0.5)
        elseif context.distance_delta > context.break_distance * 1.4 then
            lead_ticks = lead_ticks + 1
        end

        return utils.clamp(
            base_ticks + lead_ticks,
            1,
            get_adaptive_max_ticks(context.airborne, context.speed)
        )
    end

    local function get_adaptive_hold_ticks(confidence, airborne, latency_ticks)
        local hold_time = 0.13 + confidence * 0.07

        if airborne then
            hold_time = hold_time + 0.04
        end

        return utils.clamp(
            math.floor(hold_time / globals.tickinterval() + 0.5)
                + math.floor(latency_ticks * 0.25),
            6,
            24
        )
    end

    local function extrapolate(player, origin, ticks)
        local tickinterval = globals.tickinterval()
        local velocity = get_velocity(player)
        local position = vector(origin.x, origin.y, origin.z)
        local gravity = 800
        local grounded = is_onground(player)

        for i = 1, ticks do
            local previous = position

            if not grounded then
                velocity.z = velocity.z - gravity * tickinterval
            end

            local predicted = vector(
                position.x + velocity.x * tickinterval,
                position.y + velocity.y * tickinterval,
                position.z + velocity.z * tickinterval
            )

            local fraction = client.trace_line(
                -1,
                previous.x, previous.y, previous.z,
                predicted.x, predicted.y, predicted.z
            )

            if fraction ~= nil and fraction <= 0.99 then
                return previous
            end

            position = predicted
        end

        return position
    end

    local function can_enemy_fire_after_lag(player, predict_ticks)
        local weapon = entity.get_player_weapon(player)

        if weapon == nil then
            return false
        end

        local clip = entity.get_prop(weapon, 'm_iClip1')

        if clip ~= nil and clip <= 0 then
            return false
        end

        local fire_time = globals.curtime() + predict_ticks * globals.tickinterval()
        local next_attack = entity.get_prop(player, 'm_flNextAttack') or 0
        local next_primary_attack = entity.get_prop(weapon, 'm_flNextPrimaryAttack') or 0
        local postpone_ready = entity.get_prop(weapon, 'm_flPostponeFireReadyTime') or 0

        return next_attack <= fire_time
            and next_primary_attack <= fire_time
            and postpone_ready <= fire_time
    end

    local function get_predicted_eye(player, predicted_origin)
        local ox, oy, oz = entity.get_prop(player, 'm_vecViewOffset')

        return vector(
            predicted_origin.x + (ox or 0),
            predicted_origin.y + (oy or 0),
            predicted_origin.z + (oz or 64)
        )
    end

    local function get_local_target_points(me)
        local points = {}
        local hitboxes = { 0, 2, 3, 4 }

        for i = 1, #hitboxes do
            local x, y, z = entity.hitbox_position(me, hitboxes[i])

            if x ~= nil then
                points[#points + 1] = vector(x, y, z)
            end
        end

        if #points == 0 then
            local origin = get_origin(me)

            if origin ~= nil then
                points[#points + 1] = origin + vector(0, 0, 62)
                points[#points + 1] = origin + vector(0, 0, 52)
                points[#points + 1] = origin + vector(0, 0, 40)
            end
        end

        return points
    end

    local function get_danger_damage_threshold(me)
        local health = entity.get_prop(me, 'm_iHealth') or 100

        return utils.clamp(math.floor(health * 0.18 + 0.5), 10, 35)
    end

    local function can_enemy_hit_local_after_lag(player, me, predicted_origin, predict_ticks)
        if predicted_origin == nil or not can_enemy_fire_after_lag(player, predict_ticks) then
            return false
        end

        local source = get_predicted_eye(player, predicted_origin)
        local points = get_local_target_points(me)
        local threshold = get_danger_damage_threshold(me)

        for i = 1, #points do
            local point = points[i]
            local _, damage = client.trace_bullet(
                player,
                source.x, source.y, source.z,
                point.x, point.y, point.z,
                true
            )

            if damage ~= nil and damage >= threshold then
                return true
            end
        end

        return false
    end

    local function update_records()
        local tickcount = globals.tickcount()
        local players = entity.get_players(true)
        local seen = {}

        for i = 1, #players do
            local player = players[i]
            seen[player] = true

            if entity.is_dormant(player) or not entity.is_alive(player) then
                records[player] = nil
                goto continue
            end

            local origin = get_origin(player)

            if origin == nil then
                records[player] = nil
                goto continue
            end

            local simulation_tick = get_simulation_tick(player)
            local previous = records[player]
            local predicted_origin = previous and previous.predicted_origin or nil
            local active_until = previous and previous.active_until or 0
            local confidence = previous and previous.confidence or 0
            local predict_ticks = previous and previous.predict_ticks or 0
            local tick_delta = 0

            if origin ~= nil and previous ~= nil and previous.origin ~= nil then
                tick_delta = simulation_tick - previous.simulation_tick

                local velocity = get_velocity(player)
                local speed = get_speed2d(velocity)
                local airborne = not is_onground(player)
                local context = get_lc_context(
                    origin,
                    previous,
                    tick_delta,
                    speed,
                    airborne
                )

                if context.is_signal then
                    confidence = context.confidence
                    predict_ticks = get_predict_ticks(tick_delta, context)
                    predicted_origin = extrapolate(player, origin, predict_ticks)
                    active_until = tickcount + math.max(
                        ref.hold_ticks:get(),
                        get_adaptive_hold_ticks(
                            confidence,
                            airborne,
                            get_latency_ticks()
                        )
                    )
                elseif active_until < tickcount then
                    predicted_origin = nil
                    predict_ticks = 0
                end
            end

            records[player] = {
                origin = origin,
                simulation_tick = simulation_tick,
                predicted_origin = predicted_origin,
                active_until = active_until,
                confidence = confidence,
                predict_ticks = predict_ticks,
                tick_delta = tick_delta
            }

            ::continue::
        end

        for player, record in pairs(records) do
            if not seen[player] and record.active_until < tickcount then
                records[player] = nil
            end
        end
    end

    local function on_net_update_end()
        update_records()
    end

    local function on_setup_command()
        local me = entity.get_local_player()

        if me == nil or not entity.is_alive(me) then
            restore_all_whitelists()
            return
        end

        local tickcount = globals.tickcount()
        local min_velocity = ref.min_velocity:get()
        local players = entity.get_players(true)

        for i = 1, #players do
            local player = players[i]
            local record = records[player]
            local should_whitelist = false

            if record ~= nil and record.active_until >= tickcount then
                local velocity = get_velocity(player)
                local speed = get_speed2d(velocity)

                should_whitelist = (
                    not entity.is_dormant(player)
                    and entity.is_alive(player)
                    and speed > min_velocity
                    and can_enemy_hit_local_after_lag(
                        player,
                        me,
                        record.predicted_origin,
                        record.predict_ticks or 1
                    )
                )
            end

            if should_whitelist then
                set_whitelist(player, true)
            else
                restore_whitelist(player)
            end
        end
    end

    local function on_shutdown()
        restore_all_whitelists()
        records = {}
    end

    local function on_enabled(item)
        local value = item:get()

        if not value then
            on_shutdown()
        end

        utils.event_callback('shutdown', on_shutdown, value)
        utils.event_callback('net_update_end', on_net_update_end, value)
        utils.event_callback('setup_command', on_setup_command, value)
    end

    ref.enabled:set_callback(on_enabled, true)
end

return M
