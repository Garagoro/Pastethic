local event_system = {}

local function find(list, value)
    for i = 1, #list do
        if value == list[i] then
            return i
        end
    end

    return nil
end

local EventList = {}
EventList.__index = EventList

function EventList:new()
    return setmetatable({
        list = {},
        count = 0
    }, self)
end

function EventList:__len()
    return self.count
end

function EventList:set(callback)
    if not find(self.list, callback) then
        self.count = self.count + 1
        table.insert(self.list, callback)
    end

    return self
end

function EventList:unset(callback)
    local index = find(self.list, callback)

    if index ~= nil then
        self.count = self.count - 1
        table.remove(self.list, index)
    end

    return self
end

function EventList:fire(...)
    local list = self.list

    for i = 1, #list do
        list[i](...)
    end

    return self
end

local EventBus = {}

local function event_bus_index(list, k)
    local value = rawget(list, k)

    if value == nil then
        value = EventList:new()
        rawset(list, k, value)
    end

    return value
end

function EventBus:new()
    return setmetatable({}, {
        __index = event_bus_index
    })
end

function event_system:new()
    return EventBus:new()
end

return event_system
