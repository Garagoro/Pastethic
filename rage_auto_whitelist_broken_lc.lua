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
        local x = entity.get_prop(player, 'm_vecVelocity[0]') or 0
        local y = entity.get_prop(player, 'm_vecVelocity[1]') or 0

        return math.sqrt(x * x + y * y)
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

    local function can_hit_position(me, origin)
        if me == nil or origin == nil then
            return false
        end

        local ex, ey, ez = client.eye_position()

        if ex == nil then
            return false
        end

        local heights = { 62, 52, 40 }

        for i = 1, #heights do
            local _, damage = client.trace_bullet(
                me,
                ex, ey, ez,
                origin.x, origin.y, origin.z + heights[i],
                true
            )

            if damage ~= nil and damage > 0 then
                return true
            end
        end

        return false
    end

    local function update_records()
        local tickcount = globals.tickcount()
        local distance_limit = ref.distance:get()
        local distance_limit_sqr = distance_limit * distance_limit
        local players = entity.get_players(true)

        for i = 1, #players do
            local player = players[i]
            local origin = get_origin(player)
            local simulation_tick = get_simulation_tick(player)
            local previous = records[player]
            local pre_lag_origin = previous and previous.pre_lag_origin or nil
            local broken_until = previous and previous.broken_until or 0

            if origin ~= nil and previous ~= nil and previous.origin ~= nil then
                local tick_delta = simulation_tick - previous.simulation_tick
                local distance_delta_sqr = (origin - previous.origin):lengthsqr()

                if tick_delta < 0 or (tick_delta > 1 and tick_delta <= 64 and distance_delta_sqr > distance_limit_sqr) then
                    pre_lag_origin = previous.origin
                    broken_until = tickcount + ref.hold_ticks:get()
                end
            end

            records[player] = {
                origin = origin,
                simulation_tick = simulation_tick,
                pre_lag_origin = pre_lag_origin,
                broken_until = broken_until
            }
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

            if record ~= nil and record.broken_until >= tickcount then
                should_whitelist = (
                    not entity.is_dormant(player)
                    and entity.is_alive(player)
                    and get_velocity(player) > min_velocity
                    and not can_hit_position(me, record.pre_lag_origin)
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
