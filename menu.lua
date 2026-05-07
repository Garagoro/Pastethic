local M = {}

local function contains(list, value)
    for i = 1, #list do
        if list[i] == value then
            return i
        end
    end

    return nil
end

local function dummy(...)
    return ...
end

function M.new(deps)
    local ui = assert(deps.ui, 'menu: ui dependency is required')
    local event_system = assert(deps.event_system, 'menu: event_system dependency is required')
    local unpack = deps.unpack or unpack

    local menu = {}
    local event_bus = event_system:new()
    local Item = {}

    Item.__index = Item

    local function pack(ok, ...)
        if not ok then
            return nil
        end

        return ...
    end

    local function get_value_array(ref)
        return { pack(pcall(ui.get, ref)) }
    end

    local function get_key_values(arr)
        local list = {}

        for i = 1, #arr do
            list[arr[i]] = i
        end

        return list
    end

    local function update_item_values(item, initial)
        local value = get_value_array(item.ref)

        item.value = value

        if initial then
            item.default = value
        end

        if item.type == 'multiselect' then
            item.key_values = get_key_values(unpack(value))
        end
    end

    function Item:new(ref)
        return setmetatable({
            ref = ref,
            type = nil,

            list = {},
            value = {},
            default = {},
            key_values = {},

            callbacks = {}
        }, self)
    end

    function Item:init(...)
        local function callback()
            update_item_values(self, false)
            self:fire_events()

            event_bus.item_changed:fire(self)
        end

        self.type = ui.type(self.ref)

        local can_have_callback = (
            self.type ~= 'label' and
            self.type ~= 'unknown'
        )

        if can_have_callback then
            update_item_values(self, true)
            pcall(ui.set_callback, self.ref, callback)
        end

        if self.type == 'multiselect' or self.type == 'list' then
            self.list = select(4, ...)
        end

        if self.type == 'button' then
            local fn = select(4, ...)

            if fn ~= nil then
                self:set_callback(fn)
            end
        end

        event_bus.item_init:fire(self)
    end

    function Item:get(key)
        local have_update_callback = (
            self.type ~= 'hotkey' and
            self.type ~= 'textbox' and
            self.type ~= 'unknown'
        )

        if not have_update_callback then
            return ui.get(self.ref)
        end

        if key ~= nil then
            return self.key_values[key] ~= nil
        end

        return unpack(self.value)
    end

    function Item:set(...)
        ui.set(self.ref, ...)
        update_item_values(self, false)
    end

    function Item:update(...)
        ui.update(self.ref, ...)
    end

    function Item:reset()
        pcall(ui.set, self.ref, unpack(self.default))
    end

    function Item:set_enabled(value)
        return ui.set_enabled(self.ref, value)
    end

    function Item:set_visible(value)
        return ui.set_visible(self.ref, value)
    end

    function Item:set_callback(callback, force_call)
        local index = contains(self.callbacks, callback)

        if index == nil then
            table.insert(self.callbacks, callback)
        end

        if force_call then
            callback(self)
        end

        return self
    end

    function Item:unset_callback(callback)
        local index = contains(self.callbacks, callback)

        if index ~= nil then
            table.remove(self.callbacks, index)
        end

        return self
    end

    function Item:fire_events()
        local list = self.callbacks

        for i = 1, #list do
            list[i](self)
        end
    end

    function menu.new(fn, ...)
        local argv, argc = {}, select('#', ...)

        for i = 1, argc do
            argv[i] = select(i, ...)
        end

        if fn == ui.new_button and type(argv[4]) ~= 'function' then
            argv[4] = dummy
            argc = 4
        end

        local ref = fn(unpack(argv, 1, argc))
        local item = Item:new(ref)

        item:init(...)

        return item
    end

    function menu.get_event_bus()
        return event_bus
    end

    return menu
end

return M
