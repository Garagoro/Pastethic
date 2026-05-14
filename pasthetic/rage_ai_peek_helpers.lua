local M = {}

function M.new(deps)
    deps = deps or {}

    local ui = assert(deps.ui, 'rage_ai_peek_helpers: ui dependency is required')
    local entity = assert(deps.entity, 'rage_ai_peek_helpers: entity dependency is required')
    local client = assert(deps.client, 'rage_ai_peek_helpers: client dependency is required')
    local vector = assert(deps.vector, 'rage_ai_peek_helpers: vector dependency is required')
    local globals = assert(deps.globals, 'rage_ai_peek_helpers: globals dependency is required')
    local renderer = deps.renderer
    local utils = assert(deps.utils, 'rage_ai_peek_helpers: utils dependency is required')
    local bit = deps.bit or bit

    local helpers = {}

    function helpers.safe_get(item, fallback)
        if item == nil then
            return fallback
        end

        local ok, value = pcall(ui.get, item)

        if not ok or value == nil then
            return fallback
        end

        return value
    end

    function helpers.vector_copy(vec)
        if vec == nil then
            return nil
        end

        return vector(vec.x, vec.y, vec.z)
    end

    function helpers.make_vec(x, y, z)
        if x == nil then
            return nil
        end

        return vector(x, y or 0, z or 0)
    end

    function helpers.get_origin(player)
        return helpers.make_vec(entity.get_origin(player))
    end

    function helpers.get_velocity(player)
        return helpers.make_vec(entity.get_prop(player, 'm_vecVelocity')) or vector()
    end

    function helpers.get_eye_position(player)
        local eye = helpers.make_vec(entity.hitbox_position(player, 0))

        if eye ~= nil then
            return eye
        end

        local origin = helpers.get_origin(player)

        if origin == nil then
            return nil
        end

        return origin + vector(0, 0, 64)
    end

    function helpers.get_speed2d(velocity)
        return math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
    end

    function helpers.get_simulation_tick(player)
        local simulation_time = entity.get_prop(player, 'm_flSimulationTime') or 0

        return math.floor(simulation_time / globals.tickinterval() + 0.5)
    end

    function helpers.is_onground(player)
        local flags = entity.get_prop(player, 'm_fFlags') or 0

        return bit.band(flags, 1) == 1
    end

    function helpers.clamp01(value)
        return utils.clamp(value, 0, 1)
    end

    function helpers.get_trace_end(tr)
        if tr == nil or tr.end_pos == nil then
            return nil
        end

        return helpers.vector_copy(tr.end_pos)
    end

    function helpers.clamp(min, num, max)
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

    function helpers.extrapolate(pos, vel, ticks)
        return vel * ticks * globals.tickinterval() + pos
    end

    function helpers.move_to(cmd, pos)
        local me = entity.get_local_player()

        if me == nil or not entity.is_alive(me) or pos == nil then
            return
        end

        local origin = helpers.get_origin(me)
        local angles = vector(client.camera_angles())

        if origin == nil or angles == nil then
            return
        end

        local dx = origin.x - pos.x
        local dy = origin.y - pos.y
        local yaw = math.rad(angles.y)
        local forward = helpers.clamp(-450, -20 * (dx * math.cos(yaw) + dy * math.sin(yaw)), 450)
        local side = helpers.clamp(-450, 20 * (dy * math.cos(yaw) - dx * math.sin(yaw)), 450)

        if forward and side then
            cmd.forwardmove = forward
            cmd.sidemove = side

            cmd.in_forward = forward > 1 and 1 or 0
            cmd.in_back = forward < -1 and 1 or 0
            cmd.in_moveright = side > 1 and 1 or 0
            cmd.in_moveleft = side < -1 and 1 or 0
        end
    end

    function helpers.draw_circle(pos, radius, r, g, b, a)
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

    return helpers
end

return M
