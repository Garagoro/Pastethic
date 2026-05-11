local M = {}

function M.start(deps)
    deps = deps or {}

    local client = assert(deps.client, 'antiaim_backtrack_poison: client dependency is required')
    local entity = assert(deps.entity, 'antiaim_backtrack_poison: entity dependency is required')
    local globals = assert(deps.globals, 'antiaim_backtrack_poison: globals dependency is required')
    local utils = assert(deps.utils, 'antiaim_backtrack_poison: utils dependency is required')
    local software = assert(deps.software, 'antiaim_backtrack_poison: software dependency is required')
    local exploit = assert(deps.exploit, 'antiaim_backtrack_poison: exploit dependency is required')
    local renderer = deps.renderer or renderer
    local bit = deps.bit or bit

    local TELEPORT_DISTANCE_SQR = 64 * 64
    local RELEASE_CHOKE_MIN = 5
    local RELEASE_BURST_TICKS = 12
    local RELEASE_BURST_PULSES = 4
    local LIGHT_SCAN_INTERVAL = 4

    local last_choked = 0
    local last_defensive_active = false
    local last_sim_tick = nil
    local last_origin = nil
    local stalled_origin = nil
    local sim_stalled = false

    local burst_until = 0
    local burst_left = 0
    local next_burst_pulse = 0
    local next_light_pulse = 0
    local next_light_scan = 0
    local cached_hittable = false
    local defensive_indicator = false

    local function reset()
        last_choked = 0
        last_defensive_active = false
        last_sim_tick = nil
        last_origin = nil
        stalled_origin = nil
        sim_stalled = false
        burst_until = 0
        burst_left = 0
        next_burst_pulse = 0
        next_light_pulse = 0
        next_light_scan = 0
        cached_hittable = false
        defensive_indicator = false
    end

    local function vec3(x, y, z)
        if x == nil then
            return nil
        end

        return { x = x, y = y or 0, z = z or 0 }
    end

    local function dist2d_sqr(a, b)
        if a == nil or b == nil then
            return 0
        end

        local dx = a.x - b.x
        local dy = a.y - b.y

        return dx * dx + dy * dy
    end

    local function get_origin(player)
        return vec3(entity.get_origin(player))
    end

    local function get_velocity(player)
        local x, y, z = entity.get_prop(player, 'm_vecVelocity')

        return x or 0, y or 0, z or 0
    end

    local function get_speed2d(player)
        local x, y = get_velocity(player)

        return math.sqrt(x * x + y * y)
    end

    local function is_shift_exploit_active()
        return software.is_double_tap_active()
            or software.is_on_shot_antiaim_active()
    end

    local function get_exploit_defensive()
        local data = exploit.get()

        if data == nil or data.defensive == nil then
            return nil
        end

        return data.defensive
    end

    local function is_defensive_active()
        local defensive = get_exploit_defensive()

        return defensive ~= nil and (defensive.left or 0) > 0
    end

    local function get_esp_flag(player, bit_index)
        if player == nil then
            return false
        end

        local data = entity.get_esp_data(player)

        if data == nil or data.flags == nil then
            return false
        end

        return bit.band(data.flags, bit.lshift(1, bit_index)) ~= 0
    end

    local function get_eye_position(player)
        local ox, oy, oz = entity.get_origin(player)
        local vx, vy, vz = entity.get_prop(player, 'm_vecViewOffset')

        if ox == nil or vx == nil then
            return nil
        end

        return {
            x = ox + vx,
            y = oy + vy,
            z = oz + vz
        }
    end

    local function get_local_points(me)
        local points = {}
        local hitboxes = { 0, 2, 3, 4 }

        for i = 1, #hitboxes do
            local x, y, z = entity.hitbox_position(me, hitboxes[i])

            if x ~= nil then
                points[#points + 1] = { x = x, y = y, z = z }
            end
        end

        if #points == 0 then
            local origin = get_origin(me)

            if origin ~= nil then
                points[1] = { x = origin.x, y = origin.y, z = origin.z + 62 }
                points[2] = { x = origin.x, y = origin.y, z = origin.z + 48 }
            end
        end

        return points
    end

    local function trace_enemy_to_local(enemy, me)
        local source = get_eye_position(enemy)

        if source == nil then
            return false
        end

        local points = get_local_points(me)

        for i = 1, #points do
            local point = points[i]
            local _, damage = client.trace_bullet(
                enemy,
                source.x, source.y, source.z,
                point.x, point.y, point.z,
                true
            )

            if damage ~= nil and damage > 8 then
                return true
            end
        end

        return false
    end

    local function is_local_hittable(me)
        local threat = client.current_threat()

        if threat ~= nil and entity.is_alive(threat) and not entity.is_dormant(threat) then
            if get_esp_flag(threat, 11) or trace_enemy_to_local(threat, me) then
                return true
            end
        end

        local enemies = entity.get_players(true)

        for i = 1, #enemies do
            local enemy = enemies[i]

            if not entity.is_dormant(enemy)
                and entity.is_alive(enemy)
                and trace_enemy_to_local(enemy, me)
            then
                return true
            end
        end

        return false
    end

    local function update_hittable_cache(me)
        local tick = globals.tickcount()

        if tick < next_light_scan then
            return cached_hittable
        end

        next_light_scan = tick + LIGHT_SCAN_INTERVAL
        cached_hittable = is_local_hittable(me)

        return cached_hittable
    end

    local function is_weapon_blocked(me)
        local weapon = entity.get_player_weapon(me)

        if weapon == nil then
            return true
        end

        if get_esp_flag(me, 5) then
            return true
        end

        local clip = entity.get_prop(weapon, 'm_iClip1')

        if clip ~= nil and clip <= 0 then
            return true
        end

        local time = globals.curtime() + globals.tickinterval()
        local next_attack = entity.get_prop(me, 'm_flNextAttack') or 0
        local next_primary_attack = entity.get_prop(weapon, 'm_flNextPrimaryAttack') or 0
        local postpone_fire = entity.get_prop(weapon, 'm_flPostponeFireReadyTime') or 0

        return next_attack > time
            or next_primary_attack > time
            or postpone_fire > time
    end

    local function start_release_burst(cmd)
        burst_left = math.max(burst_left, RELEASE_BURST_PULSES)
        burst_until = math.max(burst_until, cmd.command_number + RELEASE_BURST_TICKS)
        next_burst_pulse = math.min(next_burst_pulse == 0 and cmd.command_number or next_burst_pulse, cmd.command_number)
    end

    local function can_pulse(cmd, me)
        if cmd == nil or cmd.command_number == nil then
            return false
        end

        if cmd.force_defensive == 1
            or cmd.force_defensive == true
            or cmd.in_attack == 1
            or cmd.in_attack == true
            or cmd.in_attack2 == 1
            or cmd.in_attack2 == true
        then
            return false
        end

        if software.is_duck_peek_assist() or not is_shift_exploit_active() then
            return false
        end

        if is_defensive_active() then
            return false
        end

        return entity.is_alive(me)
    end

    local function update_sim_release(me)
        local simtime = entity.get_prop(me, 'm_flSimulationTime')
        local origin = get_origin(me)

        if simtime == nil or origin == nil then
            return false
        end

        local sim_tick = math.floor(simtime / globals.tickinterval() + 0.5)
        local released = false

        if last_sim_tick ~= nil then
            if sim_tick <= last_sim_tick then
                if not sim_stalled then
                    stalled_origin = last_origin or origin
                end

                sim_stalled = true
            elseif sim_stalled then
                released = dist2d_sqr(stalled_origin, origin) >= TELEPORT_DISTANCE_SQR * 0.5
                sim_stalled = false
                stalled_origin = nil
            end
        end

        if last_sim_tick == nil or sim_tick > last_sim_tick then
            last_sim_tick = sim_tick
            last_origin = origin
        end

        return released
    end

    local function update_release_triggers(cmd, me)
        local released = false
        local choked = cmd.chokedcommands or 0
        local defensive_active = is_defensive_active()

        if last_choked >= RELEASE_CHOKE_MIN and choked == 0 then
            released = true
        end

        if last_defensive_active and not defensive_active and get_speed2d(me) > 20 then
            released = true
        end

        if update_sim_release(me) then
            released = true
        end

        last_choked = choked
        last_defensive_active = defensive_active

        if released then
            start_release_burst(cmd)
        end
    end

    local function apply_release_burst(cmd, me)
        if burst_left <= 0 or cmd.command_number > burst_until then
            burst_left = 0
            burst_until = 0
            next_burst_pulse = 0
            return false
        end

        if not can_pulse(cmd, me) then
            return false
        end

        if cmd.command_number < next_burst_pulse then
            return false
        end

        cmd.force_defensive = 1
        defensive_indicator = true
        burst_left = burst_left - 1
        next_burst_pulse = cmd.command_number + utils.random_int(1, 2)

        return true
    end

    local function apply_light_pulse(cmd, me)
        if not can_pulse(cmd, me) then
            next_light_pulse = 0
            return false
        end

        if not is_weapon_blocked(me) or not update_hittable_cache(me) then
            next_light_pulse = 0
            return false
        end

        if next_light_pulse == 0 then
            local speed = get_speed2d(me)
            local min_delay = speed > 120 and 7 or 11
            local max_delay = speed > 120 and 14 or 22

            next_light_pulse = cmd.command_number + utils.random_int(min_delay, max_delay)
            return false
        end

        if cmd.command_number < next_light_pulse then
            return false
        end

        cmd.force_defensive = 1
        defensive_indicator = true
        next_light_pulse = cmd.command_number + utils.random_int(8, 18)

        return true
    end

    local function on_setup_command(cmd)
        local me = entity.get_local_player()

        if me == nil or not entity.is_alive(me) then
            reset()
            return
        end

        defensive_indicator = is_defensive_active()
        update_release_triggers(cmd, me)

        if apply_release_burst(cmd, me) then
            return
        end

        apply_light_pulse(cmd, me)
    end

    local function on_paint_ui()
        if renderer == nil then
            return
        end

        local me = entity.get_local_player()

        if me == nil or not entity.is_alive(me) then
            return
        end

        local active = defensive_indicator or is_defensive_active()
        local prefix = 'Defensive: '
        local value = active and 'True' or 'False'
        local screen_w, screen_h = client.screen_size()
        local prefix_w = renderer.measure_text('', prefix)
        local value_w = renderer.measure_text('', value)
        local x = screen_w * 0.5 - (prefix_w + value_w) * 0.5
        local y = screen_h - 110
        local r, g, b = 225, 75, 75

        if active then
            r, g, b = 90, 220, 115
        end

        renderer.text(x, y, 235, 235, 235, 230, '', nil, prefix)
        renderer.text(x + prefix_w, y, r, g, b, 235, '', nil, value)
    end

    utils.event_callback('shutdown', reset, true)
    utils.event_callback('player_death', function(e)
        local me = entity.get_local_player()

        if me ~= nil and client.userid_to_entindex(e.userid) == me then
            reset()
        end
    end, true)
    utils.event_callback('round_start', reset, true)
    utils.event_callback('level_init', reset, true)
    utils.event_callback('setup_command', on_setup_command, true)
    utils.event_callback('paint_ui', on_paint_ui, true)
end

function M.health()
    return true
end

return M
