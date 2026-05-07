local M = {}

function M.new(deps)
    deps = deps or {}

    local bit = deps.bit or bit
    local client = deps.client or client
    local entity = deps.entity or entity
    local vector = deps.vector or vector
    local c_entity = deps.c_entity
    local utils = deps.utils

    local localplayer = {}
    local pre_flags = 0
    local post_flags = 0

    localplayer.is_moving = false
    localplayer.is_onground = false
    localplayer.is_crouched = false

    localplayer.body_yaw = 0
    localplayer.sent_packets = 0

    localplayer.duck_amount = 0.0

    localplayer.velocity = vector()
    localplayer.velocity2d_sqr = 0

    localplayer.move_dir = vector()
    localplayer.peek_threat = nil

    -- from @enq
    local function is_peeking(player)
        local should, vulnerable, threat = false, false, nil
        local velocity = vector(entity.get_prop(player, 'm_vecVelocity'))

        local eye = vector(client.eye_position())
        local peye = utils.extrapolate(eye, velocity, 14)

        local enemies = entity.get_players(true)

        for i = 1, #enemies do
            local enemy = enemies[i]

            local esp_data = entity.get_esp_data(enemy)

            if esp_data == nil then
                goto continue
            end

            if bit.band(esp_data.flags, bit.lshift(1, 11)) ~= 0 then
                vulnerable = true
                goto continue
            end

            local hx, hy, hz = entity.hitbox_position(enemy, 0)

            if hx == nil then
                goto continue
            end

            local enemy_velocity = vector(entity.get_prop(enemy, 'm_vecVelocity'))
            local head = vector(hx, hy, hz)
            local phead = utils.extrapolate(head, enemy_velocity, 4)

            local entindex, damage = client.trace_bullet(player, peye.x, peye.y, peye.z, phead.x, phead.y, phead.z)

            if damage ~= nil and damage > 5 then
                should = true
                threat = enemy
                break
            end

            ::continue::
        end

        return should, vulnerable, threat
    end

    local function get_body_yaw(player)
        local entity_info = c_entity(player)

        if entity_info == nil then
            return
        end

        local anim_state = entity_info:get_anim_state()

        if anim_state == nil then
            return
        end

        local eye_angles_y = anim_state.eye_angles_y
        local goal_feet_yaw = anim_state.goal_feet_yaw

        return utils.normalize(
            eye_angles_y - goal_feet_yaw, -180, 180
        )
    end

    local function on_pre_predict_command(cmd)
        local me = entity.get_local_player()

        if me == nil then
            return
        end

        pre_flags = entity.get_prop(me, 'm_fFlags')
    end

    local function on_predict_command(cmd)
        local me = entity.get_local_player()

        if me == nil then
            return
        end

        post_flags = entity.get_prop(me, 'm_fFlags')
    end

    local function on_setup_command(cmd)
        local me = entity.get_local_player()

        if me == nil then
            return
        end

        local peeking, vulnerable, peek_threat = is_peeking(me)

        local is_onground = bit.band(pre_flags, 1) ~= 0
            and bit.band(post_flags, 1) ~= 0

        local velocity = vector(entity.get_prop(me, 'm_vecVelocity'))
        local duck_amount = entity.get_prop(me, 'm_flDuckAmount')

        local velocity2d_sqr = velocity:length2dsqr()

        localplayer.is_moving = velocity2d_sqr > 5 * 5
        localplayer.is_onground = is_onground

        localplayer.is_peeking = peeking
        localplayer.is_vulnerable = vulnerable
        localplayer.peek_threat = peek_threat

        if cmd.chokedcommands == 0 then
            localplayer.body_yaw = get_body_yaw(me)

            localplayer.sent_packets = (
                localplayer.sent_packets + 1
            )

            localplayer.is_crouched = duck_amount > 0.5
            localplayer.duck_amount = duck_amount
        end

        localplayer.velocity = velocity
        localplayer.velocity2d_sqr = velocity2d_sqr

        localplayer.move_dir = vector(
            cmd.forwardmove, cmd.sidemove, 0
        )
    end

    client.set_event_callback('pre_predict_command', on_pre_predict_command)
    client.set_event_callback('predict_command', on_predict_command)
    client.set_event_callback('setup_command', on_setup_command)

    return localplayer
end

return M
