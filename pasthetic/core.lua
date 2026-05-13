local M = {}

M.constants = {
    SCRIPT_NAME = 'Pasthetic',
    LEGACY_SCRIPT_NAME = 'Aesthetic',
    LOCALDB_FILE = 'pasthetic_new.dat',
    LEGACY_LOCALDB_FILE = 'aesthetic_new.dat',
    CONFIG_PREFIX = 'pasthetic',
    LEGACY_CONFIG_PREFIX = 'aesthetic',
    SKIN_CONFIG_MARKER = '__pasthetic_skin_config',
    LEGACY_SKIN_CONFIG_MARKER = '__aesthetic_skin_config',
    ALL_CONFIGS_MARKER = '__pasthetic_all_configs',
    DB = {
        CONFIG = '##PASTHETIC_DB',
        SKIN_CONFIGS = '##PASTHETIC_SKIN_CONFIGS'
    },
    LEGACY_DB = {
        CONFIG = '##AESTHETIC_DB',
        SKIN_CONFIGS = '##AESTHETIC_SKIN_CONFIGS'
    }
}

M.static_data = {
    teams = {
        'Terrorist',
        'Counter-Terrorist'
    },

    crouch_dirs = {
        'Forward',
        'Forward-Left',
        'Forward-Right',
        'Backward',
        'Backward-Left',
        'Backward-Right',
        'Left',
        'Right'
    },

    states = {
        'Default',
        'Standing',
        'Moving',
        'Slow Walk',
        'Air',
        'Air-Crouch',
        'Crouch',
        'Move-Crouch',
        'Legit AA',
        'Manual AA',
        'Freestanding',
        'Roll AA'
    }
}

function M.contains(list, value)
    for i = 1, #list do
        if list[i] == value then
            return i
        end
    end

    return nil
end

function M.new_script(deps)
    deps = deps or {}

    return {
        name = M.constants.SCRIPT_NAME,
        build = 'gs',
        user = deps.user_name or 'nicpronichev'
    }
end

function M.new_session()
    return {
        hitchance = {
            updated_hotkey = false,
            updated_this_tick = false
        },

        force_lethal = {
            updated_division = false,
            updated_this_tick = false
        }
    }
end

function M.new_color(deps)
    deps = deps or {}

    local ffi = deps.ffi or ffi
    local color = ffi.typeof [[
        struct {
            unsigned char r;
            unsigned char g;
            unsigned char b;
            unsigned char a;
        }
    ]]

    local mt = {}
    mt.__index = mt

    function mt:__tostring()
        return string.format('%i, %i, %i, %i', self:unpack())
    end

    function mt.lerp(a, b, t)
        return color(
            a.r + t * (b.r - a.r),
            a.g + t * (b.g - a.g),
            a.b + t * (b.b - a.b),
            a.a + t * (b.a - a.a)
        )
    end

    function mt:unpack()
        return self.r, self.g, self.b, self.a
    end

    function mt:clone()
        return color(self:unpack())
    end

    function mt:to_hex()
        return string.format('%02x%02x%02x%02x', self:unpack())
    end

    function mt:hsv(h, s, v)
        local r, g, b

        h = (h % 1.0) * 360
        s = math.max(0, math.min(s, 1))
        v = math.max(0, math.min(v, 1))

        local c = v * s
        local x = c * (1 - math.abs((h / 60) % 2 - 1))
        local m = v - c

        if h < 60 then
            r, g, b = c, x, 0
        elseif h < 120 then
            r, g, b = x, c, 0
        elseif h < 180 then
            r, g, b = 0, c, x
        elseif h < 240 then
            r, g, b = 0, x, c
        elseif h < 300 then
            r, g, b = x, 0, c
        else
            r, g, b = c, 0, x
        end

        self.r = (r + m) * 255
        self.g = (g + m) * 255
        self.b = (b + m) * 255
        self.a = 255

        return self
    end

    ffi.metatype(color, mt)

    return color
end

function M.new_motion(deps)
    deps = deps or {}

    local globals = deps.globals or globals
    local motion = {}

    local function linear(t, b, c, d)
        return c * t / d + b
    end

    local function solve(easing_fn, prev, new, clock, duration)
        if clock <= 0 then return new end
        if clock >= duration then return new end

        prev = easing_fn(clock, prev, new - prev, duration)

        if type(prev) == 'number' then
            if math.abs(new - prev) < 0.001 then
                return new
            end

            local remainder = prev % 1.0

            if remainder < 0.001 then
                return math.floor(prev)
            end

            if remainder > 0.999 then
                return math.ceil(prev)
            end
        end

        return prev
    end

    function motion.interp(a, b, t, easing_fn)
        easing_fn = easing_fn or linear

        if type(b) == 'boolean' then
            b = b and 1 or 0
        end

        return solve(easing_fn, a, b, globals.frametime(), t)
    end

    return motion
end

function M.new_logging(deps)
    deps = deps or {}

    local client = deps.client or client
    local cvar = deps.cvar or cvar
    local logging = {}
    local script_name = M.constants.SCRIPT_NAME
    local play = cvar.play

    local function display_tag(r, g, b)
        client.color_log(r, g, b, '[', script_name, '] \0')
    end

    function logging.log(msg)
        display_tag(180, 100, 255)
        client.color_log(255, 255, 255, msg)
    end

    function logging.success(msg)
        display_tag(180, 100, 255)
        client.color_log(255, 255, 255, msg)
        play:invoke_callback('ui\\beepclear.wav')
    end

    function logging.error(msg)
        display_tag(250, 50, 75)
        client.color_log(255, 255, 255, msg)
        play:invoke_callback('resource\\warning.wav')
    end

    function logging.script_loaded()
        client.color_log(180, 100, 255, '[' .. script_name .. '] \0')
        client.color_log(255, 255, 255, 'Script loaded')
    end

    return logging
end

local text_fmt = {}

local function decompose_colored_text(str)
    local result, len = {}, #str
    local i, j = str:find('\a', 1)

    if i == nil then
        table.insert(result, { str, nil })
    end

    if i ~= nil and i > 1 then
        table.insert(result, { str:sub(1, i - 1), nil })
    end

    while i ~= nil do
        local hex = nil

        if str:sub(j + 1, j + 7) == 'DEFAULT' then
            j = j + 8
        else
            hex = str:sub(j + 1, j + 8)
            j = j + 9
        end

        local m, n = str:find('\a', j)

        if m == nil then
            if j <= len then
                table.insert(result, { str:sub(j), hex })
            end

            break
        end

        table.insert(result, { str:sub(j, m - 1), hex })
        i, j = m, n
    end

    return result
end

function text_fmt.color(str)
    local list = decompose_colored_text(str)

    return list, #list
end

M.text_fmt = text_fmt

function M.new_ui_callback(deps)
    deps = deps or {}

    local ui = deps.ui or ui
    local contains = deps.contains or M.contains
    local ui_callback = {}
    local lookup = {}

    function ui_callback.set(item, callback, force_call)
        if lookup[item] == nil then
            local list = {}

            ui.set_callback(item, function()
                for i = 1, #list do
                    list[i](item)
                end
            end)

            lookup[item] = list
        end

        local index = contains(lookup[item], callback)

        if index == nil then
            table.insert(lookup[item], callback)
        end

        if force_call then
            callback(item)
        end

        return item
    end

    function ui_callback.unset(item, callback)
        local list = lookup[item]

        if list == nil then
            return
        end

        local index = contains(list, callback)

        if index ~= nil then
            table.remove(list, index)
        end

        return item
    end

    return ui_callback
end

return M
