local M = {}

function M.start(deps)
    local resource = assert(deps.resource, 'misc_fast_ladder: resource dependency is required')
    local entity = assert(deps.entity, 'misc_fast_ladder: entity dependency is required')
    local client = assert(deps.client, 'misc_fast_ladder: client dependency is required')
    local utils = assert(deps.utils, 'misc_fast_ladder: utils dependency is required')

    local ref = resource.main.miscellaneous.fast_ladder
    local MOVETYPE_LADDER = 9

    local function on_setup_command(cmd)
        local me = entity.get_local_player()

        if me == nil then
            return
        end

        local movetype = entity.get_prop(me, 'm_movetype')

        if movetype ~= MOVETYPE_LADDER then
            return
        end

        local pitch = client.camera_angles()

        cmd.yaw = math.floor(0.5 + cmd.yaw)
        cmd.roll = 0

        if cmd.forwardmove > 0 and pitch < 45 then
            cmd.pitch = 89
            cmd.in_moveleft = 0
            cmd.in_moveright = 1
            cmd.in_back = 1
            cmd.in_forward = 0

            if cmd.sidemove == 0 then
                cmd.yaw = cmd.yaw + 90
            end

            if cmd.sidemove < 0 then
                cmd.yaw = cmd.yaw + 150
            end

            if cmd.sidemove > 0 then
                cmd.yaw = cmd.yaw + 30
            end
        elseif cmd.forwardmove < 0 and pitch < 45 then
            cmd.pitch = 89
            cmd.in_moveleft = 1
            cmd.in_moveright = 0
            cmd.in_back = 0
            cmd.in_forward = 1

            if cmd.sidemove == 0 then
                cmd.yaw = cmd.yaw + 90
            end

            if cmd.sidemove > 0 then
                cmd.yaw = cmd.yaw + 150
            end

            if cmd.sidemove < 0 then
                cmd.yaw = cmd.yaw + 30
            end
        end
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
