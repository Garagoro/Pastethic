local M = {}

function M.new(deps)
    deps = deps or {}

    local utils = deps.utils
    local color = deps.color
    local text_anims = {}

    local function u8(str)
        local chars = {}
        local count = 0

        for c in string.gmatch(str, '.[\128-\191]*') do
            count = count + 1
            chars[count] = c
        end

        return chars, count
    end

    function text_anims.gradient(str, time, r1, g1, b1, a1, r2, g2, b2, a2)
        local list = {}

        local strbuf, strlen = u8(str)
        local div = 1 / (strlen - 1)

        local delta_r = r2 - r1
        local delta_g = g2 - g1
        local delta_b = b2 - b1
        local delta_a = a2 - a1

        for i = 1, strlen do
            local char = strbuf[i]

            local t = time do
                t = t % 2

                if t > 1 then
                    t = 2 - t
                end
            end

            local r = r1 + t * delta_r
            local g = g1 + t * delta_g
            local b = b1 + t * delta_b
            local a = a1 + t * delta_a

            local hex = utils.to_hex(r, g, b, a)

            table.insert(list, '\a')
            table.insert(list, hex)
            table.insert(list, char)

            time = time + div
        end

        return table.concat(list)
    end

    function text_anims.astolfo(str, time, h, s, v, scale)
        local list = {}

        local strbuf, strlen = u8(str)
        local div = 1 / (strlen - 1)

        local col = color()

        for i = 1, strlen do
            local char = strbuf[i]

            local angle = (time - math.floor(time)) % 1.0

            if angle > 0.5 then
                angle = 1.0 - angle
            end

            col:hsv(h + angle, s, v)

            local hex = col:to_hex()

            table.insert(list, '\a')
            table.insert(list, hex)
            table.insert(list, char)

            time = time + div * scale
        end

        return table.concat(list)
    end

    return text_anims
end

return M
