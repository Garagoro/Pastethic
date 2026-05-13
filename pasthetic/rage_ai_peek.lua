local M = {}

function M.start(deps)
    deps = deps or {}

    local resource = assert(deps.resource, 'rage_ai_peek: resource dependency is required')
    local ui = assert(deps.ui, 'rage_ai_peek: ui dependency is required')
    local entity = assert(deps.entity, 'rage_ai_peek: entity dependency is required')
    local client = assert(deps.client, 'rage_ai_peek: client dependency is required')
    local globals = assert(deps.globals, 'rage_ai_peek: globals dependency is required')
    local vector = assert(deps.vector, 'rage_ai_peek: vector dependency is required')
    local renderer = deps.renderer or renderer
    local utils = assert(deps.utils, 'rage_ai_peek: utils dependency is required')
    local trace = deps.trace or require 'gamesense/trace'
    local weapons = deps.csgo_weapons or require 'gamesense/csgo_weapons'
    local bit = deps.bit or bit

    local ref = resource.main.ragebot.ai_peek
    local rage_min_damage = { ui.reference('Rage', 'Aimbot', 'Minimum damage') }
    local rage_damage_override = { ui.reference('Rage', 'Aimbot', 'Minimum damage override') }
    local ref_quick_peek = { ui.reference('Rage', 'Other', 'Quick peek assist') }
    local ref_target_selection = ui.reference('Rage', 'Aimbot', 'Target selection')

    local hitbox_names = {
        'Head',
        'Neck',
        'Pelvis',
        'Stomach',
        'Lower chest',
        'Chest',
        'Upper chest',
        'Left thigh',
        'Right thigh',
        'Left calf',
        'Right calf',
        'Left foot',
        'Right foot',
        'Left hand',
        'Right hand',
        'Left upper arm',
        'Left forearm',
        'Right upper arm',
        'Right forearm'
    }

    local aipeek = {
        data = nil
    }
    local records = {}

    local SERVER_TELEPORT_DISTANCE = 64
    local SERVER_TELEPORT_DISTANCE_SQR = SERVER_TELEPORT_DISTANCE * SERVER_TELEPORT_DISTANCE
    local STALL_UPDATES_MIN = 2
    local STALL_SPEED_MIN = 36
    local ROLLBACK_HOLD_TICKS = 12
    local COMMIT_EXPOSURE_DAMAGE = 5
    local COMMIT_LOCK_TICKS = 6
    local COMMIT_DISTANCE = 8
    local SAFE_RESCAN_TICKS = 4
    local RETURN_RESUME_SPEED = 55
    local MANUAL_RESET_DISTANCE_MIN = 160
    local AI_PEEK_TARGET_SELECTION = 'Best hit chance'

    local function safe_get(item, fallback)
        if item == nil then
            return fallback
        end

        local ok, value = pcall(ui.get, item)

        if not ok or value == nil then
            return fallback
        end

        return value
    end

    local function vector_copy(vec)
        if vec == nil then
            return nil
        end

        return vector(vec.x, vec.y, vec.z)
    end

    local function make_vec(x, y, z)
        if x == nil then
            return nil
        end

        return vector(x, y or 0, z or 0)
    end

    local function get_origin(player)
        return make_vec(entity.get_origin(player))
    end

    local function get_velocity(player)
        return make_vec(entity.get_prop(player, 'm_vecVelocity')) or vector()
    end

    local function get_eye_position(player)
        local eye = make_vec(entity.hitbox_position(player, 0))

        if eye ~= nil then
            return eye
        end

        local origin = get_origin(player)

        if origin == nil then
            return nil
        end

        return origin + vector(0, 0, 64)
    end

    local function get_speed2d(velocity)
        return math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
    end

    local function get_simulation_tick(player)
        local simulation_time = entity.get_prop(player, 'm_flSimulationTime') or 0

        return math.floor(simulation_time / globals.tickinterval() + 0.5)
    end

    local function is_onground(player)
        local flags = entity.get_prop(player, 'm_fFlags') or 0

        return bit.band(flags, 1) == 1
    end

    local function clamp01(value)
        return utils.clamp(value, 0, 1)
    end

    local function get_trace_end(tr)
        if tr == nil or tr.end_pos == nil then
            return nil
        end

        return vector_copy(tr.end_pos)
    end

    local function clamp(min, num, max)
        if min == nil or num == nil or max == nil then
            return false
        end

        if num < min then
            return min
        end

        if num > max then
            return max
        end

        return num
    end

    local function extrapolate(pos, vel, ticks)
        return vel * ticks * globals.tickinterval() + pos
    end

    local function build_record_context(origin, previous, simulation_tick, tick_delta, speed, airborne, tickcount)
        local origin_delta_sqr = (origin - previous.origin):lengthsqr()
        local origin_delta = math.sqrt(origin_delta_sqr)
        local stale_updates = tick_delta == 0
            and (previous.stale_updates or 0) + 1
            or 0
        local rollback_until = previous.rollback_until or 0
        local rollback = tick_delta < 0

        if rollback then
            stale_updates = math.max(stale_updates, STALL_UPDATES_MIN)
            rollback_until = tickcount + ROLLBACK_HOLD_TICKS
        end

        local teleported = origin_delta_sqr > SERVER_TELEPORT_DISTANCE_SQR
        local stale_threat = tick_delta == 0
            and stale_updates >= STALL_UPDATES_MIN
            and (speed > STALL_SPEED_MIN or airborne)
        local rollback_threat = rollback_until >= tickcount
            and (speed > 12 or airborne or origin_delta > 8)
        local speed_score = clamp01((speed - 24) / 240)
        local stale_score = clamp01((stale_updates - 1) / 6)
        local delta_score = clamp01((origin_delta - 12) / SERVER_TELEPORT_DISTANCE)
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

        confidence = clamp01(confidence)

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
            local garbage_until = previous and previous.garbage_until or 0
            local stale_updates = previous and previous.stale_updates or 0
            local rollback_until = previous and previous.rollback_until or 0
            local garbage = false
            local defensive_like = false
            local origin_delta = 0
            local tick_delta = 0
            local velocity = get_velocity(player)
            local speed = get_speed2d(velocity)
            local airborne = not is_onground(player)

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

    local function is_garbage_record(player)
        local record = records[player]

        if record == nil then
            return false
        end

        return record.garbage == true
            or record.defensive_like == true
            or record.garbage_until >= globals.tickcount()
    end

    local function get_active_hitboxes()
        local active = {}

        for i = 1, #hitbox_names do
            local name = hitbox_names[i]

            if ref.hitboxes:get(name) then
                active[i - 1] = name
            end
        end

        if next(active) == nil then
            active[0] = 'Head'
            active[3] = 'Stomach'
        end

        return active
    end

    local function get_targets(exclude)
        local players = {}

        if ref.scan_all:get() or exclude then
            local list = entity.get_players(exclude and false or true)

            for i = 1, #list do
                local ent = list[i]

                if ent ~= exclude and ent ~= nil and entity.is_alive(ent) and not entity.is_dormant(ent) then
                    players[#players + 1] = ent
                end
            end
        else
            local ent = client.current_threat()

            if ent ~= nil and entity.is_alive(ent) and not entity.is_dormant(ent) then
                players[#players + 1] = ent
            end
        end

        if #players == 0 then
            local list = entity.get_players(true)

            for i = 1, #list do
                local ent = list[i]

                if ent ~= nil and entity.is_alive(ent) and not entity.is_dormant(ent) then
                    players[#players + 1] = ent
                end
            end
        end

        return players
    end

    local function get_threats()
        local players = {}
        local list = entity.get_players(true)

        for i = 1, #list do
            local ent = list[i]

            if ent ~= nil and entity.is_alive(ent) and not entity.is_dormant(ent) then
                players[#players + 1] = ent
            end
        end

        return players
    end

    local function get_local_damage_points_at(pos)
        return {
            pos + vector(0, 0, 64),
            pos + vector(0, 0, 54),
            pos + vector(0, 0, 42),
            pos + vector(0, 0, 34)
        }
    end

    local function evaluate_position_safety(me, pos)
        local max_damage = 0
        local exposure_count = 0
        local bad_record_exposure = 0
        local threats = get_threats()
        local local_points = get_local_damage_points_at(pos)

        for i = 1, #threats do
            local threat = threats[i]
            local eye = get_eye_position(threat)
            local threat_damage = 0

            if eye ~= nil then
                for j = 1, #local_points do
                    local point = local_points[j]
                    local hit_ent, damage = client.trace_bullet(
                        threat,
                        eye.x, eye.y, eye.z,
                        point.x, point.y, point.z,
                        false
                    )

                    if hit_ent == me and damage ~= nil then
                        threat_damage = math.max(threat_damage, damage)
                    end
                end
            end

            if threat_damage > 5 then
                exposure_count = exposure_count + 1
                max_damage = math.max(max_damage, threat_damage)

                if is_garbage_record(threat) then
                    bad_record_exposure = bad_record_exposure + 1
                end
            end
        end

        return {
            incoming_damage = max_damage,
            exposure_count = exposure_count,
            bad_record_exposure = bad_record_exposure
        }
    end

    local function is_position_hittable(safety)
        return safety ~= nil
            and ((safety.incoming_damage or 0) > COMMIT_EXPOSURE_DAMAGE
                or (safety.exposure_count or 0) > 0)
    end

    local function is_full_safe(safety)
        return safety ~= nil
            and (safety.incoming_damage or 0) <= 0
            and (safety.exposure_count or 0) <= 0
            and (safety.bad_record_exposure or 0) <= 0
    end

    local function is_commit_candidate_safe(candidate, current_safety)
        if candidate == nil or candidate.start == nil then
            return false
        end

        if (candidate.bad_record_exposure or 0) > 0 then
            return false
        end

        local current_exposure = current_safety ~= nil and (current_safety.exposure_count or 0) or 0
        local current_damage = current_safety ~= nil and (current_safety.incoming_damage or 0) or 0

        if (candidate.exposure_count or 0) > math.max(1, current_exposure) then
            return false
        end

        if (candidate.incoming_damage or 0) > math.max(COMMIT_EXPOSURE_DAMAGE, current_damage + 5) then
            return false
        end

        return true
    end

    local function clear_commit()
        if aipeek.data ~= nil then
            aipeek.data.commit = nil
        end
    end

    local function set_target_selection_override()
        if aipeek.data == nil or ref_target_selection == nil then
            return
        end

        if aipeek.data.target_selection_before == nil then
            aipeek.data.target_selection_before = safe_get(ref_target_selection, nil)
        end

        pcall(ui.set, ref_target_selection, AI_PEEK_TARGET_SELECTION)
    end

    local function restore_target_selection()
        if aipeek.data == nil or aipeek.data.target_selection_before == nil or ref_target_selection == nil then
            return
        end

        pcall(ui.set, ref_target_selection, aipeek.data.target_selection_before)
        aipeek.data.target_selection_before = nil
    end

    local function start_native_return()
        if aipeek.data == nil then
            return
        end

        aipeek.data.native_return = true
        aipeek.data.safe_rescan_ticks = 0
        clear_commit()
        restore_target_selection()
    end

    local function move_to(cmd, pos)
        local me = entity.get_local_player()

        if me == nil or not entity.is_alive(me) or pos == nil then
            return
        end

        local origin = get_origin(me)
        local angles = vector(client.camera_angles())

        if origin == nil or angles == nil then
            return
        end

        local dx = origin.x - pos.x
        local dy = origin.y - pos.y
        local yaw = math.rad(angles.y)
        local forward = clamp(-450, -20 * (dx * math.cos(yaw) + dy * math.sin(yaw)), 450)
        local side = clamp(-450, 20 * (dy * math.cos(yaw) - dx * math.sin(yaw)), 450)

        if forward and side then
            cmd.forwardmove = forward
            cmd.sidemove = side

            cmd.in_forward = forward > 1 and 1 or 0
            cmd.in_back = forward < -1 and 1 or 0
            cmd.in_moveright = side > 1 and 1 or 0
            cmd.in_moveleft = side < -1 and 1 or 0
        end
    end

    local function ready_shot_local()
        local me = entity.get_local_player()

        if me == nil or not entity.is_alive(me) then
            return false
        end

        local weapon_index = entity.get_player_weapon(me)
        local weapon = weapons(weapon_index)

        if weapon == nil or weapon.weapon_type_int == 0 or weapon.weapon_type_int == 9 then
            return false
        end

        local next_attack = entity.get_prop(me, 'm_flNextAttack') or 0
        local next_weapon_attack = entity.get_prop(weapon_index, 'm_flNextPrimaryAttack') or 0
        local now = globals.curtime()

        return next_attack <= now and next_weapon_attack <= now
    end

    local function get_min_damage()
        if ref.min_damage_override:get() then
            return safe_get(rage_damage_override[3], safe_get(rage_min_damage[1], 1))
        end

        return safe_get(rage_min_damage[1], 1)
    end

    local function build_positions()
        if aipeek.data == nil or aipeek.data.positions == nil then
            return
        end

        aipeek.data.positions.other = {}

        local me = entity.get_local_player()
        local previous = get_origin(me)

        if previous == nil then
            return
        end

        local previous_id = nil
        local angles = vector(client.camera_angles())
        local distance = ref.distance:get()
        local count = ref.count:get()
        local interval = distance / count
        local separation = ref.separation:get()

        for side = 1, separation do
            for dist = interval, distance, interval do
                local angle = math.rad(angles.y + 90 + (side - 1) * 360 / separation)
                local x = aipeek.data.eye.x + dist * math.cos(angle)
                local y = aipeek.data.eye.y + dist * math.sin(angle)
                local lateral = trace.line(
                    aipeek.data.eye,
                    vector(x, y, aipeek.data.eye.z),
                    { skip = entity.get_players() }
                )
                local lateral_end = get_trace_end(lateral)

                if lateral_end == nil then
                    goto continue
                end

                local down = trace.line(
                    lateral_end,
                    lateral_end - vector(0, 0, 96),
                    { skip = entity.get_players() }
                )
                local down_end = get_trace_end(down)
                local id = dist .. ':' .. side

                if down_end ~= nil and lateral_end:dist2d(previous) > interval * 0.5 then
                    if down_end.z - lateral_end.z ~= -96 then
                        aipeek.data.positions.other[id] = {
                            position = down_end,
                            {
                                hitbox = {},
                                damage = 0
                            },
                            angle = angle
                        }
                    else
                        local hull = trace.hull(
                            lateral_end - vector(0, 0, 64),
                            lateral_end - vector(0, 0, 128),
                            vector(-16, -16, 0),
                            vector(16, 16, 72),
                            { skip = entity.get_players() }
                        )
                        local hull_end = get_trace_end(hull)

                        if hull_end ~= nil and hull_end.z - lateral_end.z ~= -128 then
                            aipeek.data.positions.other[id] = {
                                position = hull_end,
                                {
                                    hitbox = {},
                                    damage = 0
                                },
                                angle = angle
                            }
                        end
                    end
                elseif previous_id ~= nil and previous:dist2d(lateral_end) > interval * 0.25 and down_end ~= nil then
                    aipeek.data.positions.other[previous_id] = {
                        position = down_end,
                        {
                            hitbox = {},
                            damage = 0
                        },
                        angle = angle
                    }
                end

                previous_id = id
                previous = lateral_end

                ::continue::
            end
        end
    end

    local function reset()
        restore_target_selection()
        aipeek.data = nil
        records = {}
    end

    local function is_active()
        return ref.enabled:get()
            and safe_get(ref_quick_peek[1], false) == true
            and safe_get(ref_quick_peek[2], false) == true
    end

    local function update_data()
        local bind_active = is_active()

        if not bind_active then
            reset()
            return
        end

        local me = entity.get_local_player()

        if me == nil or not entity.is_alive(me) then
            reset()
            return
        end

        if aipeek.data == nil then
            aipeek.data = {}
        end

        if aipeek.data.stored == nil then
            aipeek.data.stored = {}
        end

        if aipeek.data.stored.pos ~= true then
            local position = get_origin(me)
            local eye = make_vec(client.eye_position())

            if position == nil or eye == nil then
                return
            end

            aipeek.data.positions = {
                center = position,
                other = {}
            }
            aipeek.data.eye = eye
        end

        if aipeek.data.stored.ang ~= true then
            build_positions()
        end

        aipeek.data.stored = {
            pos = true,
            ang = true
        }

        if ref.live_scan:get() then
            aipeek.data.stored.ang = false
        end
    end

    local function on_setup_command(cmd)
        local me = entity.get_local_player()

        if me == nil or not entity.is_alive(me) then
            return
        end

        if aipeek.data == nil then
            return
        end

        aipeek.data.aim = {}

        local origin = get_origin(me)

        if origin == nil or aipeek.data.positions == nil then
            return
        end

        local is_move = cmd.in_forward == 1
            or cmd.in_back == 1
            or cmd.in_moveleft == 1
            or cmd.in_moveright == 1

        if cmd.in_attack == 1 or cmd.in_attack == true then
            start_native_return()
        end

        local center_distance = origin:dist2d(aipeek.data.positions.center)
        local tickcount = globals.tickcount()

        if not aipeek.data.native_return and aipeek.data.commit == nil then
            local reset_distance = math.max(ref.distance:get() * 2.25, MANUAL_RESET_DISTANCE_MIN)

            if center_distance > reset_distance then
                reset()
                return
            end
        end

        if aipeek.data.native_return then
            local current_safety = evaluate_position_safety(me, origin)
            local stable_speed = get_speed2d(get_velocity(me)) <= RETURN_RESUME_SPEED

            if is_full_safe(current_safety) and stable_speed then
                aipeek.data.safe_rescan_ticks = (aipeek.data.safe_rescan_ticks or 0) + 1
            else
                aipeek.data.safe_rescan_ticks = 0
            end

            if (aipeek.data.safe_rescan_ticks or 0) >= SAFE_RESCAN_TICKS then
                aipeek.data.native_return = false
                aipeek.data.safe_rescan_ticks = 0
                clear_commit()
                restore_target_selection()
            end

            return
        end

        local active_commit = aipeek.data.commit

        if active_commit ~= nil and active_commit.until_tick < tickcount then
            if center_distance > COMMIT_DISTANCE then
                start_native_return()
                return
            end

            clear_commit()
        end

        if not ready_shot_local() then
            aipeek.data.safe_rescan_ticks = 0

            if center_distance > COMMIT_DISTANCE then
                start_native_return()
                return
            end

            clear_commit()
            return
        end

        if not aipeek.data.native_return then
            set_target_selection_override()

            for _, point in next, aipeek.data.positions.other do
                local total_damage = 0
                point[1] = {
                    hitbox = {},
                    damage = 0
                }

                local start = vector_copy(point.position) + vector(0, 0, 64)
                local targets = get_targets()
                local hitboxes = get_active_hitboxes()
                local min_damage = get_min_damage()
                local safety = nil

                for _, target in next, targets do
                    if is_garbage_record(target) then
                        goto skip_target
                    end

                    local health = entity.get_prop(target, 'm_iHealth') or 0

                    for hitbox_id in next, hitboxes do
                        local velocity = get_velocity(target)
                        local hitbox_pos = make_vec(entity.hitbox_position(target, hitbox_id))

                        if hitbox_pos ~= nil then
                            local predicted = extrapolate(
                                hitbox_pos,
                                velocity,
                                ref.prediction:get()
                            )
                            local hit_ent, damage = client.trace_bullet(
                                me,
                                start.x, start.y, start.z,
                                predicted.x, predicted.y, predicted.z
                            )
                            local trace_damage = damage or 0

                            if not hit_ent then
                                point[1].damage = total_damage
                            elseif target == hit_ent then
                                point[1].damage = total_damage < trace_damage and trace_damage or total_damage
                            end

                            total_damage = point[1].damage

                            if (hit_ent == nil or target == hit_ent)
                                and (trace_damage >= min_damage or health <= trace_damage)
                            then
                                if safety == nil then
                                    safety = evaluate_position_safety(me, point.position)
                                end

                                local target_origin = get_origin(target)

                                if target_origin ~= nil then
                                    aipeek.data.aim[#aipeek.data.aim + 1] = {
                                        start = start,
                                        ['end'] = target_origin,
                                        damage = trace_damage,
                                        lethal = health <= trace_damage,
                                        move_distance = origin:dist2d(point.position),
                                        target_distance = start:dist(target_origin),
                                        incoming_damage = safety.incoming_damage,
                                        exposure_count = safety.exposure_count,
                                        bad_record_exposure = safety.bad_record_exposure
                                    }
                                end

                                point[1].hitbox[hitbox_id] = predicted
                            end
                        end
                    end

                    ::skip_target::
                end
            end
        end

        table.sort(aipeek.data.aim, function(a, b)
            if a.bad_record_exposure ~= b.bad_record_exposure then
                return (a.bad_record_exposure or 0) < (b.bad_record_exposure or 0)
            end

            if a.exposure_count ~= b.exposure_count then
                return (a.exposure_count or 0) < (b.exposure_count or 0)
            end

            if a.incoming_damage ~= b.incoming_damage then
                return (a.incoming_damage or 0) < (b.incoming_damage or 0)
            end

            if a.lethal ~= b.lethal then
                return a.lethal == true
            end

            if a.move_distance ~= b.move_distance then
                return (a.move_distance or 0) < (b.move_distance or 0)
            end

            if a.damage ~= b.damage then
                return (a.damage or 0) > (b.damage or 0)
            end

            return (a.target_distance or a.start:dist(a['end'])) < (b.target_distance or b.start:dist(b['end']))
        end)

        local move_to_pos = nil
        local best_aim = aipeek.data.aim[1]

        if not aipeek.data.native_return then
            local current_safety = center_distance > COMMIT_DISTANCE
                and evaluate_position_safety(me, origin)
                or nil
            local commit_point = is_position_hittable(current_safety)

            if commit_point then
                local commit = aipeek.data.commit

                if commit ~= nil and commit.until_tick >= tickcount then
                    move_to_pos = commit.position
                elseif is_commit_candidate_safe(best_aim, current_safety) then
                    aipeek.data.commit = {
                        position = vector_copy(best_aim.start),
                        until_tick = tickcount + COMMIT_LOCK_TICKS
                    }
                    move_to_pos = best_aim.start
                else
                    start_native_return()
                end
            elseif best_aim ~= nil and best_aim.start ~= nil then
                clear_commit()
                move_to_pos = best_aim.start
            else
                clear_commit()
            end
        else
            clear_commit()
        end

        if move_to_pos ~= nil and not is_move then
            move_to(cmd, move_to_pos)
        end
    end

    local function draw_circle(pos, radius, r, g, b, a)
        if renderer == nil or pos == nil then
            return
        end

        local old_x, old_y = nil, nil

        for rot = 0, 360, 12 do
            local rad = math.rad(rot)
            local x, y = renderer.world_to_screen(
                pos.x + radius * math.cos(rad),
                pos.y + radius * math.sin(rad),
                pos.z
            )

            if x ~= nil and old_x ~= nil then
                renderer.line(x, y, old_x, old_y, r, g, b, a)
            end

            old_x, old_y = x, y
        end
    end

    local function on_paint()
        if aipeek.data == nil or aipeek.data.positions == nil or not ref.debug:get() then
            return
        end

        for _, point in next, aipeek.data.positions.other do
            local damage = point[1] ~= nil and point[1].damage or 0

            if damage > 0 then
                draw_circle(point.position, 12, 90, 220, 115, 200)
            else
                draw_circle(point.position, 12, 235, 235, 235, 140)
            end
        end
    end

    local function on_aim_fire()
        if aipeek.data ~= nil then
            start_native_return()
        end
    end

    utils.event_callback('shutdown', reset, true)
    utils.event_callback('round_start', reset, true)
    utils.event_callback('level_init', reset, true)
    utils.event_callback('net_update_end', update_records, true)
    utils.event_callback('run_command', update_data, true)
    utils.event_callback('setup_command', on_setup_command, true)
    utils.event_callback('paint', on_paint, true)
    utils.event_callback('aim_fire', on_aim_fire, true)
end

function M.health()
    return true
end

return M
