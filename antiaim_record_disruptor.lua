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
    local MAX_FOV = 26
    local MIN_LOCAL_SPEED = 35
    local MIN_THREAT_DAMAGE = 5
    local MIN_THREAT_SCORE = 0.58
    local FULL_LOCAL_SPEED = 180
    local MIN_LOCAL_SPEED_SCALE = 0.18
    local PULSE_COOLDOWN_MIN = 8
    local PULSE_COOLDOWN_MAX = 16

    local state = {
        pulse_left = 0,
        cooldown = 0,
        side = 1,
        strength = 0,
        velocity_scale = 1,
        last_threat = nil
    }

    local function reset()
        state.pulse_left = 0
        state.cooldown = 0
        state.side = 1
        state.strength = 0
        state.velocity_scale = 1
        state.last_threat = nil
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

    local function get_local_damage_points(me, local_head)
        local points = {}

        if local_head ~= nil then
            points[#points + 1] = local_head
        end

        local hitboxes = { 2, 3, 4, 5, 6 }

        for i = 1, #hitboxes do
            local x, y, z = entity.hitbox_position(me, hitboxes[i])

            if x ~= nil then
                points[#points + 1] = vector(x, y, z)
            end
        end

        return points
    end

    local function can_threat_damage_local(me, threat, local_head)
        local eye = get_eye_position(threat)

        if eye == nil or local_head == nil then
            return false, 0
        end

        local points = get_local_damage_points(me, local_head)
        local best_damage = 0

        for i = 1, #points do
            local point = points[i]
            local entindex, damage = client.trace_bullet(
                threat,
                eye.x, eye.y, eye.z,
                point.x, point.y, point.z,
                false
            )

            if entindex == me and damage ~= nil then
                best_damage = math.max(best_damage, damage)
            end
        end

        return best_damage > MIN_THREAT_DAMAGE, best_damage
    end

    local function get_best_threat(me)
        local eye = get_eye_position(me)
        local local_head = get_head_position(me)
        local my_origin = get_origin(me)
        local view_pitch, view_yaw = client.camera_angles()
        local local_speed = get_speed2d(me)
        local velocity_scale = get_local_velocity_scale(me)

        if eye == nil or local_head == nil or my_origin == nil or view_pitch == nil then
            return nil
        end

        if local_speed < MIN_LOCAL_SPEED then
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
            local can_damage, damage = can_threat_damage_local(me, player, local_head)

            if not can_damage then
                goto continue
            end

            local damage_score = utils.clamp(damage / 80, 0, 1)
            local score = fov_score * 0.42
                + distance_score * 0.16
                + speed_score * 0.12
                + damage_score * 0.30

            if get_esp_flag(player, 11) then
                score = score + 0.08
            end

            if score > best_score then
                best_score = score
                best_threat = player
            end

            ::continue::
        end

        if best_score < MIN_THREAT_SCORE then
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

        buffer.yaw_offset = utils.normalize(
            (buffer.yaw_offset or 0) + offset,
            -180,
            180
        )

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
