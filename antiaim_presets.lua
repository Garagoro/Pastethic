local M = {}

local SKITTER_PATTERN = {
    -1, 1, 0,
    -1, 1, 0,
    -1, 0, 1,
    -1, 0, 1
}

local Runtime = {}
Runtime.__index = Runtime

local function make_sway_manager()
    return {
        data = {},
        get = function(self, key, from, to, delay, speed, tick)
            local min = math.min(from, to)
            local max = math.max(from, to)

            if self.data[key] == nil
                or self.data[key].min ~= min
                or self.data[key].max ~= max
                or self.data[key].delay ~= delay
                or self.data[key].speed ~= speed
            then
                self.data[key] = {
                    forward = true,
                    value = min,
                    min = min,
                    max = max,
                    delay = delay,
                    speed = speed,
                    last_tick = tick
                }
            end

            local data = self.data[key]

            if tick - data.last_tick >= data.delay then
                for _ = 1, data.speed do
                    if data.forward then
                        if data.value < data.max then
                            data.value = data.value + 1
                        else
                            data.forward = false
                        end
                    else
                        if data.value > data.min then
                            data.value = data.value - 1
                        else
                            data.forward = true
                        end
                    end
                end

                data.last_tick = tick
            end

            return data.value
        end
    }
end

local function make_flick_manager()
    return {
        data = {},
        get = function(self, key, from, to, delay, tick)
            local min = math.min(from, to)
            local max = math.max(from, to)

            if self.data[key] == nil
                or self.data[key].min ~= min
                or self.data[key].max ~= max
                or self.data[key].delay ~= delay
            then
                self.data[key] = {
                    flicked = false,
                    min = min,
                    max = max,
                    delay = delay,
                    last_tick = tick
                }
            end

            local data = self.data[key]

            if tick - data.last_tick >= data.delay then
                data.flicked = not data.flicked
                data.last_tick = tick
            end

            return data.flicked and max or min
        end
    }
end

local function make_randomized_jitter(utils)
    return {
        data = {},
        get = function(self, key, from, to, delay, tick)
            local min = math.min(from, to)
            local max = math.max(from, to)

            if self.data[key] == nil
                or self.data[key].min ~= min
                or self.data[key].max ~= max
            then
                self.data[key] = {
                    value = utils.random_int(min, max),
                    min = min,
                    max = max,
                    delay = delay,
                    last_tick = tick
                }
            end

            local data = self.data[key]
            data.delay = delay

            if tick - data.last_tick >= data.delay then
                data.value = utils.random_int(min, max)
                data.last_tick = tick
            end

            return data.value
        end
    }
end

function M.new(deps)
    local utils = assert(deps.utils, 'antiaim_presets: utils dependency is required')

    return setmetatable({
        utils = utils,
        sway = make_sway_manager(),
        flick = make_flick_manager(),
        randomized = make_randomized_jitter(utils)
    }, Runtime)
end

function Runtime:get_sway(key, from, to, delay, speed, tick)
    return self.sway:get(key, from, to, delay, speed, tick)
end

function Runtime:get_flick(key, from, to, delay, tick)
    return self.flick:get(key, from, to, delay, tick)
end

function Runtime:get_randomized(key, from, to, delay, tick)
    return self.randomized:get(key, from, to, delay, tick)
end

function Runtime:get_skitter_multiplier(inverts)
    local index = inverts % #SKITTER_PATTERN
    return SKITTER_PATTERN[index + 1]
end

function Runtime:pick_delay(state, items, max_delay)
    local delay_from = items.delay_from:get()
    local delay_to = items.delay_to:get()
    local delay_chaos = items.delay_chaos ~= nil and items.delay_chaos:get() or 0

    if delay_from <= 1 and delay_to <= 1 then
        state.last = 1
        return 1
    end

    local delay = self.utils.random_int(delay_from, delay_to)

    if delay_chaos > 0 then
        delay = delay + self.utils.random_int(-delay_chaos, delay_chaos)
    end

    delay = self.utils.clamp(math.floor(delay + 0.5), 1, max_delay)

    if state.last ~= nil and delay == state.last and delay_from ~= delay_to then
        local reroll = self.utils.random_int(delay_from, delay_to)

        if delay_chaos > 0 then
            reroll = reroll + self.utils.random_int(-delay_chaos, delay_chaos)
        end

        delay = self.utils.clamp(math.floor(reroll + 0.5), 1, max_delay)
    end

    state.last = delay

    return delay
end

function M.health()
    return type(M.new) == 'function'
end

return M
