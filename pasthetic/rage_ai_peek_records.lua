local M = {}

function M.new(deps)
    deps = deps or {}

    local entity = assert(deps.entity, 'rage_ai_peek_records: entity dependency is required')
    local globals = assert(deps.globals, 'rage_ai_peek_records: globals dependency is required')
    local helpers = assert(deps.helpers, 'rage_ai_peek_records: helpers dependency is required')
    local constants = assert(deps.constants, 'rage_ai_peek_records: constants dependency is required')

    local records = {}
    local api = {}

    local function build_record_context(origin, previous, simulation_tick, tick_delta, speed, airborne, tickcount)
        local origin_delta_sqr = (origin - previous.origin):lengthsqr()
        local origin_delta = math.sqrt(origin_delta_sqr)
        local stale_updates = tick_delta == 0
            and (previous.stale_updates or 0) + 1
            or 0
        local rollback_until = previous.rollback_until or 0
        local rollback = tick_delta < 0

        if rollback then
            stale_updates = math.max(stale_updates, constants.STALL_UPDATES_MIN)
            rollback_until = tickcount + constants.ROLLBACK_HOLD_TICKS
        end

        local teleported = origin_delta_sqr > constants.SERVER_TELEPORT_DISTANCE_SQR
        local stale_threat = tick_delta == 0
            and stale_updates >= constants.STALL_UPDATES_MIN
            and (speed > constants.STALL_SPEED_MIN or airborne)
        local rollback_threat = rollback_until >= tickcount
            and (speed > 12 or airborne or origin_delta > 8)
        local speed_score = helpers.clamp01((speed - 24) / 240)
        local stale_score = helpers.clamp01((stale_updates - 1) / 6)
        local delta_score = helpers.clamp01((origin_delta - 12) / constants.SERVER_TELEPORT_DISTANCE)
        local confidence = 0

        if teleported then
            confidence = math.max(confidence, 0.88 + delta_score * 0.12)
        end

        if rollback then
            confidence = math.max(confidence, 0.78 + speed_score * 0.08)
        elseif rollback_threat then
            confidence = math.max(confidence, 0.58 + speed_score * 0.18 + delta_score * 0.12)
        end

        if stale_threat then
            confidence = math.max(confidence, 0.42 + stale_score * 0.26 + speed_score * 0.20 + (airborne and 0.10 or 0))
        end

        confidence = helpers.clamp01(confidence)

        return {
            confidence = confidence,
            defensive_like = rollback or rollback_threat or stale_threat,
            garbage = teleported
                or rollback
                or rollback_threat
                or (stale_threat and confidence >= 0.48),
            origin_delta = origin_delta,
            rollback_until = rollback_until,
            stale_updates = stale_updates,
            tick_delta = tick_delta
        }
    end

    function api.update()
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

            local origin = helpers.get_origin(player)

            if origin == nil then
                records[player] = nil
                goto continue
            end

            local simulation_tick = helpers.get_simulation_tick(player)
            local previous = records[player]
            local garbage_until = previous and previous.garbage_until or 0
            local stale_updates = previous and previous.stale_updates or 0
            local rollback_until = previous and previous.rollback_until or 0
            local garbage = false
            local defensive_like = false
            local origin_delta = 0
            local tick_delta = 0
            local velocity = helpers.get_velocity(player)
            local speed = helpers.get_speed2d(velocity)
            local airborne = not helpers.is_onground(player)

            if previous ~= nil and previous.origin ~= nil then
                tick_delta = simulation_tick - previous.simulation_tick

                local context = build_record_context(
                    origin,
                    previous,
                    simulation_tick,
                    tick_delta,
                    speed,
                    airborne,
                    tickcount
                )

                stale_updates = context.stale_updates
                rollback_until = context.rollback_until
                defensive_like = context.defensive_like
                origin_delta = context.origin_delta

                if context.garbage then
                    garbage = true
                    garbage_until = tickcount + 4
                elseif garbage_until >= tickcount then
                    garbage = true
                else
                    garbage_until = 0
                end
            end

            records[player] = {
                origin = origin,
                simulation_tick = simulation_tick,
                stale_updates = stale_updates,
                rollback_until = rollback_until,
                garbage_until = garbage_until,
                garbage = garbage,
                defensive_like = defensive_like,
                origin_delta = origin_delta,
                tick_delta = tick_delta,
                speed = speed,
                airborne = airborne
            }

            ::continue::
        end

        for player in pairs(records) do
            if not seen[player] then
                records[player] = nil
            end
        end
    end

    function api.is_garbage(player)
        local record = records[player]

        if record == nil then
            return false
        end

        return record.garbage == true
            or record.defensive_like == true
            or record.garbage_until >= globals.tickcount()
    end

    function api.reset()
        records = {}
    end

    return api
end

return M
