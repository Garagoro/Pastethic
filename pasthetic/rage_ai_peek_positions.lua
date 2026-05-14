local M = {}

function M.new(deps)
    deps = deps or {}

    local entity = assert(deps.entity, 'rage_ai_peek_positions: entity dependency is required')
    local client = assert(deps.client, 'rage_ai_peek_positions: client dependency is required')
    local vector = assert(deps.vector, 'rage_ai_peek_positions: vector dependency is required')
    local trace = assert(deps.trace, 'rage_ai_peek_positions: trace dependency is required')
    local ref = assert(deps.ref, 'rage_ai_peek_positions: ref dependency is required')
    local helpers = assert(deps.helpers, 'rage_ai_peek_positions: helpers dependency is required')

    local api = {}

    function api.build(data)
        if data == nil or data.positions == nil then
            return
        end

        data.positions.other = {}

        local me = entity.get_local_player()
        local previous = helpers.get_origin(me)

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
                local x = data.eye.x + dist * math.cos(angle)
                local y = data.eye.y + dist * math.sin(angle)
                local lateral = trace.line(
                    data.eye,
                    vector(x, y, data.eye.z),
                    { skip = entity.get_players() }
                )
                local lateral_end = helpers.get_trace_end(lateral)

                if lateral_end == nil then
                    goto continue
                end

                local down = trace.line(
                    lateral_end,
                    lateral_end - vector(0, 0, 96),
                    { skip = entity.get_players() }
                )
                local down_end = helpers.get_trace_end(down)
                local id = dist .. ':' .. side

                if down_end ~= nil and lateral_end:dist2d(previous) > interval * 0.5 then
                    if down_end.z - lateral_end.z ~= -96 then
                        data.positions.other[id] = {
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
                        local hull_end = helpers.get_trace_end(hull)

                        if hull_end ~= nil and hull_end.z - lateral_end.z ~= -128 then
                            data.positions.other[id] = {
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
                    data.positions.other[previous_id] = {
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

    return api
end

return M
