local M = {}

function M.new(deps)
    deps = deps or {}

    local resource = assert(deps.resource, 'antiaim_record_disruptor: resource dependency is required')
    local entity = assert(deps.entity, 'antiaim_record_disruptor: entity dependency is required')
    local client = assert(deps.client, 'antiaim_record_disruptor: client dependency is required')
    local globals = assert(deps.globals, 'antiaim_record_disruptor: globals dependency is required')
    local vector = assert(deps.vector, 'antiaim_record_disruptor: vector dependency is required')
    local utils = assert(deps.utils, 'antiaim_record_disruptor: utils dependency is required')
    local bit = assert(deps.bit, 'antiaim_record_disruptor: bit dependency is required')
    local software = assert(deps.software, 'antiaim_record_disruptor: software dependency is required')

    local ref = resource.antiaim.features.record_disruptor
    local record_disruptor = {}

    local MAX_DISTANCE = 1100
    local MAX_FOV = 32
    local FULL_LOCAL_SPEED = 180
    local MIN_LOCAL_SPEED_SCALE = 0.18
    local PULSE_COOLDOWN_MIN = 2
    local PULSE_COOLDOWN_MAX = 5
    local HISTORY_MAX_TICKS = 24
    local SCAN_STEP = 4

    local state = {
        pulse_left = 0,
        cooldown = 0,
        side = 1,
        strength = 0,
        velocity_scale = 1,
        last_threat = nil,
        history = {}
    }

    local function reset()
        state.pulse_left = 0
        state.cooldown = 0
        state.side = 1
        state.strength = 0
        state.velocity_scale = 1
        state.last_threat = nil
        state.history = {}
    end

    local function get_eye_position(player)
        local x, y, z = utils.get_eye_position(player)

        if x == nil then
            return nil
        end

        return vector(x, y, z)
    end

    local function get_head_position(player)
        local x, y, z = entity.hitbox_position(player, 0)

        if x ~= nil then
            return vector(x, y, z)
        end

        return get_eye_position(player)
    end

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

    local function get_speed2d(player)
        local velocity = get_velocity(player)

        return math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
    end

    local function get_local_velocity_scale(player)
        local speed = get_speed2d(player)
        local scale = utils.clamp(speed / FULL_LOCAL_SPEED, 0, 1)

        return MIN_LOCAL_SPEED_SCALE + (1 - MIN_LOCAL_SPEED_SCALE) * scale
    end

    local function get_distance2d(a, b)
        local dx = a.x - b.x
        local dy = a.y - b.y

        return math.sqrt(dx * dx + dy * dy)
    end

    local function is_shift_exploit_active()
        return software.is_double_tap_active()
            or software.is_on_shot_antiaim_active()
    end

    local function get_esp_flag(entindex, bit_index)
        local esp_data = entity.get_esp_data(entindex)

        if esp_data == nil or esp_data.flags == nil then
            return false
        end

        return bit.band(esp_data.flags, bit.lshift(1, bit_index)) ~= 0
    end

    local function get_crosshair_fov(from, target, view_pitch, view_yaw)
        local delta = target - from
        local pitch, yaw = delta:angles()
        local pitch_delta = utils.normalize(pitch - view_pitch, -180, 180)
        local yaw_delta = utils.normalize(yaw - view_yaw, -180, 180)

        return math.sqrt(pitch_delta * pitch_delta + yaw_delta * yaw_delta)
    end

    local function can_threat_damage_local(me, threat, local_head)
        local eye = get_eye_position(threat)

        if eye == nil or local_head == nil then
            return false
        end

        local entindex, damage = client.trace_bullet(
            threat,
            eye.x, eye.y, eye.z,
            local_head.x, local_head.y, local_head.z,
            false
        )

        return entindex == me and damage ~= nil and damage > 1
    end

    local function get_best_threat(me)
        local eye = get_eye_position(me)
        local local_head = get_head_position(me)
        local my_origin = get_origin(me)
        local view_pitch, view_yaw = client.camera_angles()
        local velocity_scale = get_local_velocity_scale(me)

        if eye == nil or local_head == nil or my_origin == nil or view_pitch == nil then
            return nil
        end

        local best_threat = nil
        local best_score = 0

        local players = entity.get_players(true)

        for i = 1, #players do
            local player = players[i]

            if entity.is_dormant(player) or not entity.is_alive(player) then
                goto continue
            end

            local head = get_head_position(player)
            local origin = get_origin(player)

            if head == nil or origin == nil then
                goto continue
            end

            local distance = get_distance2d(my_origin, origin)

            if distance > MAX_DISTANCE then
                goto continue
            end

            local fov = get_crosshair_fov(eye, head, view_pitch, view_yaw)

            if fov > MAX_FOV then
                goto continue
            end

            local fov_score = 1 - utils.clamp(fov / MAX_FOV, 0, 1)
            local distance_score = 1 - utils.clamp(distance / MAX_DISTANCE, 0, 1)
            local speed_score = utils.clamp(get_speed2d(player) / 260, 0, 1)
            local score = fov_score * 0.55 + distance_score * 0.20 + speed_score * 0.15

            if get_esp_flag(player, 11) then
                score = score + 0.18
            end

            if get_esp_flag(me, 11) or can_threat_damage_local(me, player, local_head) then
                score = score + 0.22
            end

            if score > best_score then
                best_score = score
                best_threat = player
            end

            ::continue::
        end

        if best_score < 0.48 then
            return nil
        end

        return best_threat, utils.clamp(best_score, 0, 1), velocity_scale
    end

    local function get_backtrack_ticks()
        return utils.clamp(
            math.floor(0.25 / globals.tickinterval() + 0.5),
            12,
            24
        )
    end

    local function get_angle_distance(a, b)
        return math.abs(utils.normalize(a - b, -180, 180))
    end

    local function prune_history()
        local tickcount = globals.tickcount()
        local max_ticks = math.min(HISTORY_MAX_TICKS, get_backtrack_ticks())

        for i = #state.history, 1, -1 do
            local record = state.history[i]

            if record == nil or tickcount - record.tick > max_ticks then
                table.remove(state.history, i)
            end
        end
    end

    local function get_history_gap(candidate, threat)
        prune_history()

        local closest = 180

        for i = 1, #state.history do
            local record = state.history[i]
            local distance = get_angle_distance(candidate, record.yaw)

            if record.threat == threat then
                closest = math.min(closest, distance)
            else
                closest = math.min(closest, distance * 1.25)
            end
        end

        return closest
    end

    local function remember_yaw(yaw, threat)
        prune_history()

        state.history[#state.history + 1] = {
            tick = globals.tickcount(),
            yaw = utils.normalize(yaw, -180, 180),
            threat = threat
        }

        while #state.history > 18 do
            table.remove(state.history, 1)
        end
    end

    local function scan_best_yaw(base_yaw, preferred_delta, threat)
        local preferred_yaw = utils.normalize(base_yaw + preferred_delta, -180, 180)
        local max_delta = utils.clamp(
            math.abs(preferred_delta) + 14 + state.strength * 12,
            16,
            64
        )
        local desired_gap = utils.clamp(
            18 + state.strength * 20 + state.velocity_scale * 8,
            20,
            48
        )

        local best_yaw = preferred_yaw
        local best_score = -1

        for delta = -max_delta, max_delta, SCAN_STEP do
            local candidate = utils.normalize(base_yaw + delta, -180, 180)
            local gap = get_history_gap(candidate, threat)
            local gap_score = utils.clamp(gap / desired_gap, 0, 1)
            local prefer_score = 1 - utils.clamp(
                get_angle_distance(candidate, preferred_yaw) / math.max(1, max_delta),
                0,
                1
            )
            local side_score = delta * preferred_delta >= 0 and 1 or 0.65
            local score = gap_score * 0.62 + prefer_score * 0.28 + side_score * 0.10

            if gap < desired_gap * 0.55 then
                score = score - 0.35
            end

            if score > best_score then
                best_score = score
                best_yaw = candidate
            end
        end

        return best_yaw
    end

    local function start_pulse(threat, score, velocity_scale)
        local max_ticks = get_backtrack_ticks()
        local pulse_score = score * (0.55 + velocity_scale * 0.45)
        local pulse = utils.clamp(
            math.floor(4 + pulse_score * 8 + utils.random_int(0, 3)),
            4,
            max_ticks
        )

        if state.last_threat == threat then
            state.side = -state.side
        else
            state.side = utils.random_int(0, 1) == 0 and -1 or 1
        end

        state.last_threat = threat
        state.strength = score
        state.velocity_scale = velocity_scale
        state.pulse_left = pulse
    end

    local function update_pulse(cmd)
        if state.pulse_left > 0 then
            state.pulse_left = state.pulse_left - 1

            if state.pulse_left <= 0 then
                state.cooldown = utils.random_int(PULSE_COOLDOWN_MIN, PULSE_COOLDOWN_MAX)
            end

            return true
        end

        if state.cooldown > 0 then
            state.cooldown = state.cooldown - 1
            return false
        end

        local me = entity.get_local_player()

        if me == nil or not entity.is_alive(me) then
            reset()
            return false
        end

        if cmd.in_attack == 1 or cmd.in_attack2 == 1 then
            return false
        end

        local threat, score, velocity_scale = get_best_threat(me)

        if threat == nil then
            state.last_threat = nil
            return false
        end

        start_pulse(threat, score, velocity_scale)

        return true
    end

    function record_disruptor:update(cmd, buffer)
        if ref == nil or not ref.enabled:get() then
            reset()
            return false
        end

        if not is_shift_exploit_active() then
            reset()
            return false
        end

        if buffer == nil or cmd == nil then
            return false
        end

        if cmd.force_defensive == 1 then
            return false
        end

        if not update_pulse(cmd) then
            return false
        end

        local base = (18 + state.strength * 28) * state.velocity_scale
        local wobble = utils.random_int(-4, 4)
        local offset = state.side * math.floor(base + wobble + 0.5)
        local base_yaw = buffer.yaw_offset or 0
        local threat = state.last_threat
        local final_yaw = scan_best_yaw(base_yaw, offset, threat)

        buffer.yaw_offset = final_yaw
        remember_yaw(final_yaw, threat)

        return true
    end

    function record_disruptor:reset()
        reset()
    end

    return record_disruptor
end

function M.health()
    return true
end

return M
