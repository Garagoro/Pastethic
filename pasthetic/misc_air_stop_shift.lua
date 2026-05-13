local M = {}

function M.start(deps)
    local resource = assert(deps.resource, 'misc_air_stop_shift: resource dependency is required')
    local entity = assert(deps.entity, 'misc_air_stop_shift: entity dependency is required')
    local client = assert(deps.client, 'misc_air_stop_shift: client dependency is required')
    local utils = assert(deps.utils, 'misc_air_stop_shift: utils dependency is required')
    local bit = deps.bit or bit

    local ref = resource.main.miscellaneous.air_stop_shift
    local FL_ONGROUND = 1
    local VK_SHIFT = 0x10
    local MAX_MOVE = 450
    local STOP_EPSILON = 2
    local SOFT_STOP_SPEED = 80
    local SOFT_STOP_SCALE = 4

    local function is_shift_pressed(cmd)
        return cmd.in_speed == 1
            or cmd.in_speed == true
            or (client.key_state ~= nil and client.key_state(VK_SHIFT) == true)
    end

    local function on_setup_command(cmd)
        if not is_shift_pressed(cmd) then
            return
        end

        local me = entity.get_local_player()

        if me == nil or not entity.is_alive(me) then
            return
        end

        local flags = entity.get_prop(me, 'm_fFlags') or 0

        if bit.band(flags, FL_ONGROUND) ~= 0 then
            return
        end

        local vx, vy = entity.get_prop(me, 'm_vecVelocity')
        vx = vx or 0
        vy = vy or 0

        local speed = math.sqrt(vx * vx + vy * vy)

        if speed <= STOP_EPSILON then
            cmd.forwardmove = 0
            cmd.sidemove = 0
            cmd.in_speed = 0
            return
        end

        local _, camera_yaw = client.camera_angles()
        local yaw = math.rad(camera_yaw or 0)
        local move_speed = speed < SOFT_STOP_SPEED and math.max(STOP_EPSILON, speed * SOFT_STOP_SCALE) or MAX_MOVE
        local desired_x = -vx / speed * move_speed
        local desired_y = -vy / speed * move_speed

        cmd.forwardmove = desired_x * math.cos(yaw) + desired_y * math.sin(yaw)
        cmd.sidemove = desired_x * math.sin(yaw) - desired_y * math.cos(yaw)
        cmd.in_speed = 0
        cmd.in_forward = 0
        cmd.in_back = 0
        cmd.in_moveleft = 0
        cmd.in_moveright = 0
    end

    local function update_event_callbacks(value)
        utils.event_callback('setup_command', on_setup_command, value)
    end

    local function on_enabled(item)
        update_event_callbacks(item:get())
    end

    ref.enabled:set_callback(on_enabled, true)
end

return M
