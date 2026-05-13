local M = {}

function M.new(deps)
    deps = deps or {}

    local ffi = deps.ffi or ffi
    local client = deps.client or client
    local entity = deps.entity or entity
    local globals = deps.globals or globals

    local utils = {}

    function utils.clamp(x, min, max)
        return math.max(min, math.min(x, max))
    end

    function utils.lerp(a, b, t)
        return a + t * (b - a)
    end

    function utils.inverse_lerp(a, b, x)
        return (x - a) / (b - a)
    end

    function utils.map(x, in_min, in_max, out_min, out_max, should_clamp)
        if should_clamp then
            x = utils.clamp(x, in_min, in_max)
        end

        local rel = utils.inverse_lerp(in_min, in_max, x)
        local value = utils.lerp(out_min, out_max, rel)

        return value
    end

    function utils.normalize(x, min, max)
        local d = max - min

        while x < min do
            x = x + d
        end

        while x > max do
            x = x - d
        end

        return x
    end

    function utils.trim(str)
        return str
    end

    function utils.from_hex(hex)
        hex = string.gsub(hex, '#', '')

        local r = tonumber(string.sub(hex, 1, 2), 16)
        local g = tonumber(string.sub(hex, 3, 4), 16)
        local b = tonumber(string.sub(hex, 5, 6), 16)
        local a = tonumber(string.sub(hex, 7, 8), 16)

        return r, g, b, a or 255
    end

    function utils.to_hex(r, g, b, a)
        return string.format('%02x%02x%02x%02x', r, g, b, a)
    end

    function utils.event_callback(event_name, callback, value)
        local fn = value == false
            and client.unset_event_callback
            or client.set_event_callback

        fn(event_name, callback)
    end

    function utils.get_eye_position(ent)
        local origin_x, origin_y, origin_z = entity.get_origin(ent)
        local offset_x, offset_y, offset_z = entity.get_prop(ent, 'm_vecViewOffset')

        if origin_x == nil or offset_x == nil then
            return nil
        end

        local eye_pos_x = origin_x + offset_x
        local eye_pos_y = origin_y + offset_y
        local eye_pos_z = origin_z + offset_z

        return eye_pos_x, eye_pos_y, eye_pos_z
    end

    function utils.get_player_weapons(ent)
        local weapons = {}

        for i = 0, 63 do
            local weapon = entity.get_prop(
                ent, 'm_hMyWeapons', i
            )

            if weapon == nil then
                goto continue
            end

            table.insert(weapons, weapon)
            ::continue::
        end

        return weapons
    end

    function utils.get_player_kd(player)
        if player == nil then
            return nil
        end

        local player_resource = entity.get_player_resource()

        if player_resource == nil then
            return nil
        end

        local kills = entity.get_prop(player_resource, 'm_iKills', player)
        local deaths = entity.get_prop(player_resource, 'm_iDeaths', player)

        if deaths > 0 then
            return kills / deaths
        end

        return kills
    end

    function utils.closest_ray_point(a, b, p, should_clamp)
        local ray_delta = p - a
        local line_delta = b - a

        local lengthsqr = line_delta.x * line_delta.x + line_delta.y * line_delta.y
        local dot_product = ray_delta.x * line_delta.x + ray_delta.y * line_delta.y

        local t = dot_product / lengthsqr

        if should_clamp then
            if t <= 0.0 then
                return a
            end

            if t >= 1.0 then
                return b
            end
        end

        return a + t * line_delta
    end

    function utils.extrapolate(pos, vel, ticks)
        return pos + vel * (ticks * globals.tickinterval())
    end

    function utils.random_int(min, max)
        if min > max then
            min, max = max, min
        end

        return client.random_int(min, max)
    end

    function utils.random_float(min, max)
        if min > max then
            min, max = max, min
        end

        return client.random_float(min, max)
    end

    function utils.find_signature(module_name, pattern, offset)
        local match = client.find_signature(module_name, pattern)

        if match == nil then
            return nil
        end

        if offset ~= nil then
            local address = ffi.cast('char*', match)
            address = address + offset

            return address
        end

        return match
    end

    return utils
end

return M
