local M = {}

function M.new(deps)
    deps = deps or {}

    local resource = assert(deps.resource, 'antiaim_predicted_at_targets: resource dependency is required')
    local entity = assert(deps.entity, 'antiaim_predicted_at_targets: entity dependency is required')
    local client = assert(deps.client, 'antiaim_predicted_at_targets: client dependency is required')
    local globals = assert(deps.globals, 'antiaim_predicted_at_targets: globals dependency is required')
    local vector = assert(deps.vector, 'antiaim_predicted_at_targets: vector dependency is required')
    local utils = assert(deps.utils, 'antiaim_predicted_at_targets: utils dependency is required')
    local bit = assert(deps.bit, 'antiaim_predicted_at_targets: bit dependency is required')
    local toticks = assert(deps.toticks, 'antiaim_predicted_at_targets: toticks dependency is required')
    local cvar = deps.cvar or cvar

    local predicted_at_targets = {}
    local ref = resource.antiaim.features.predicted_at_targets
    local records = {}

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

    local function get_simulation_tick(player)
        local simulation_time = entity.get_prop(player, 'm_flSimulationTime') or 0

        return toticks(simulation_time)
    end

    local function get_speed2d(velocity)
        return math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
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

    local function get_lc_context(origin, previous, tick_delta, speed, airborne)
        local distance_delta = math.sqrt((origin - previous.origin):lengthsqr())
        local break_distance = utils.clamp(44 + speed * 0.06, 48, 72)

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

        local is_signal = tick_delta < 0 or (
            tick_delta > 1
            and tick_delta <= 64
            and confidence >= 0.34
            and distance_delta > 18
            and speed > 15
        )

        return {
            airborne = airborne,
            break_distance = break_distance,
            confidence = confidence,
            distance_delta = distance_delta,
            is_signal = is_signal,
            speed = speed
        }
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

    local function is_onground(player)
        local flags = entity.get_prop(player, 'm_fFlags') or 0

        return bit.band(flags, 1) == 1
    end

    local function get_yaw(from, to)
        local delta = to - from
        local _, yaw = delta:angles()

        return yaw
    end

    local function extrapolate(player, origin, ticks)
        local tickinterval = globals.tickinterval()
        local velocity = get_velocity(player)
        local position = vector(origin.x, origin.y, origin.z)
        local gravity = 800

        if cvar ~= nil and cvar.sv_gravity ~= nil then
            gravity = cvar.sv_gravity:get_float()
        end

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
            local active_until = previous and previous.active_until or 0
            local predicted_origin = previous and previous.predicted_origin or nil
            local predict_ticks = previous and previous.predict_ticks or 0
            local tick_delta = 0

            if previous ~= nil and previous.origin ~= nil then
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
                    predict_ticks = get_predict_ticks(tick_delta, context)
                    predicted_origin = extrapolate(
                        player,
                        origin,
                        predict_ticks
                    )

                    active_until = tickcount + get_adaptive_hold_ticks(
                        context.confidence,
                        context.airborne,
                        get_latency_ticks()
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

    local function get_active_record(player)
        local record = records[player]

        if record == nil or record.predicted_origin == nil then
            return nil
        end

        if record.active_until < globals.tickcount() then
            return nil
        end

        if entity.is_dormant(player) or not entity.is_alive(player) then
            return nil
        end

        return record
    end

    function predicted_at_targets:update(buffer)
        if not ref.enabled:get() then
            return false
        end

        if buffer == nil or buffer.yaw_base ~= 'At targets' then
            return false
        end

        local me = entity.get_local_player()

        if me == nil or not entity.is_alive(me) then
            return false
        end

        local threat = client.current_threat()

        if threat == nil then
            return false
        end

        local record = get_active_record(threat)

        if record == nil then
            return false
        end

        local my_origin = get_origin(me)
        local threat_origin = get_origin(threat)

        if my_origin == nil or threat_origin == nil then
            return false
        end

        local current_yaw = get_yaw(my_origin, threat_origin)
        local predicted_yaw = get_yaw(my_origin, record.predicted_origin)
        local correction = utils.normalize(
            predicted_yaw - current_yaw,
            -180,
            180
        )

        buffer.yaw_offset = (buffer.yaw_offset or 0) + correction

        return true
    end

    local function on_enabled(item)
        local value = item:get()

        if not value then
            records = {}
        end

        utils.event_callback('net_update_end', update_records, value)
    end

    ref.enabled:set_callback(on_enabled, true)

    return predicted_at_targets
end

function M.health()
    return true
end

return M
