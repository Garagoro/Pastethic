local M = {}

function M.new(deps)
    local vector = assert(deps.vector, 'windows: vector dependency is required')
    local client = assert(deps.client, 'windows: client dependency is required')
    local globals = assert(deps.globals, 'windows: globals dependency is required')
    local ui = assert(deps.ui, 'windows: ui dependency is required')
    local renderer = assert(deps.renderer, 'windows: renderer dependency is required')
    local menu = assert(deps.menu, 'windows: menu dependency is required')
    local utils = assert(deps.utils, 'windows: utils dependency is required')

    local windows = {}
    local data = {}
    local queue = {}

    local mouse_pos = vector()
    local mouse_pos_prev = vector()

    local mouse_down = false
    local mouse_clicked = false
    local mouse_down_duration = 0

    local mouse_delta = vector()
    local mouse_clicked_pos = vector()

    local hovered_window
    local foreground_window

    local c_window = {}

    function c_window:new(name)
        local window = {}

        window.name = name
        window.pos = vector()
        window.size = vector()
        window.anchor = vector(0.0, 0.0)
        window.updated = false
        window.dragging = false
        window.item_x = menu.new(ui.new_string, string.format('%s_x', name))
        window.item_y = menu.new(ui.new_string, string.format('%s_y', name))

        data[name] = window
        queue[#queue + 1] = window

        return setmetatable(window, self)
    end

    function c_window:set_pos(pos)
        local screen = vector(client.screen_size())
        local is_screen_invalid = (
            screen.x == 0 and
            screen.y == 0
        )

        if is_screen_invalid then
            return
        end

        local new_pos = pos:clone()

        new_pos.x = utils.clamp(new_pos.x, 0, screen.x - self.size.x)
        new_pos.y = utils.clamp(new_pos.y, 0, screen.y - self.size.y)

        self.pos = new_pos
    end

    function c_window:set_size(size)
        local screen = vector(client.screen_size())
        local is_screen_invalid = (
            screen.x == 0 and
            screen.y == 0
        )

        if is_screen_invalid then
            return
        end

        local size_delta = size - self.size

        self.size = size
        self:set_pos(self.pos - size_delta * self.anchor)
    end

    function c_window:set_anchor(anchor)
        self.anchor = anchor
    end

    function c_window:is_hovering()
        return self.hovering
    end

    function c_window:is_dragging()
        return self.dragging
    end

    function c_window:update()
        self.updated = true
    end

    c_window.__index = c_window

    local function is_collided(point, a, b)
        return point.x >= a.x and point.y >= a.y
            and point.x <= b.x and point.y <= b.y
    end

    local function update_mouse_inputs()
        local cursor = vector(ui.mouse_position())
        local is_down = client.key_state(0x01)
        local delta_time = globals.frametime()

        mouse_pos = cursor
        mouse_delta = mouse_pos - mouse_pos_prev
        mouse_pos_prev = mouse_pos

        mouse_down = is_down
        mouse_clicked = is_down and mouse_down_duration < 0
        mouse_down_duration = is_down and (mouse_down_duration < 0 and 0 or mouse_down_duration + delta_time) or -1

        if mouse_clicked then
            mouse_clicked_pos = mouse_pos
        end
    end

    local function appear_all_windows()
        for i = 1, #queue do
            local window = queue[i]
            local pos = window.pos
            local size = window.size

            renderer.rectangle(pos.x, pos.y, size.x, size.y, 0, 0, 0, 255)
        end
    end

    local function find_hovered_window()
        local found_window = nil

        if ui.is_menu_open() then
            for i = 1, #queue do
                local window = queue[i]
                local pos = window.pos
                local size = window.size

                if not window.updated then
                    goto continue
                end

                if not is_collided(mouse_pos, pos, pos + size) then
                    goto continue
                end

                found_window = window

                ::continue::
            end
        end

        hovered_window = found_window
    end

    local function find_foreground_window()
        if mouse_down then
            if mouse_clicked and hovered_window ~= nil then
                for i = 1, #queue do
                    local window = queue[i]

                    if window == hovered_window then
                        table.remove(queue, i)
                        table.insert(queue, window)
                        break
                    end
                end

                foreground_window = hovered_window
                return
            end

            return
        end

        foreground_window = nil
    end

    local function update_all_windows()
        for i = 1, #queue do
            local window = queue[i]

            window.updated = false
            window.hovering = false
            window.dragging = false
        end
    end

    local function update_hovered_window()
        if hovered_window == nil then
            return
        end

        hovered_window.hovering = true
    end

    local function update_foreground_window()
        if foreground_window == nil then
            return
        end

        local new_position = foreground_window.pos + mouse_delta

        foreground_window:set_pos(new_position)
        foreground_window.dragging = true
    end

    local function save_windows_settings()
        local screen = vector(client.screen_size())

        for i = 1, #queue do
            local window = queue[i]
            local x = window.pos.x / screen.x
            local y = window.pos.y / screen.y

            window.item_x:set(tostring(x))
            window.item_y:set(tostring(y))
        end
    end

    local function load_windows_settings()
        local screen = vector(client.screen_size())

        for i = 1, #queue do
            local window = queue[i]
            local x = tonumber(window.item_x:get())
            local y = tonumber(window.item_y:get())

            if x ~= nil and y ~= nil then
                window:set_pos(screen * vector(x, y))
            end
        end
    end

    local function on_paint_ui()
        if false then
            appear_all_windows()
        end

        update_mouse_inputs()
        find_hovered_window()
        find_foreground_window()
        update_all_windows()
        update_hovered_window()
        update_foreground_window()
    end

    local function on_setup_command(cmd)
        local should_update = (
            hovered_window ~= nil or
            foreground_window ~= nil
        )

        if should_update then
            cmd.in_attack = 0
            cmd.in_attack2 = 0
        end
    end

    function windows.new(name, x, y)
        local window = data[name] or c_window:new(name)
        local screen = vector(client.screen_size())

        window:set_pos(screen * vector(x, y))

        return window
    end

    function windows.save_settings()
        save_windows_settings()
    end

    function windows.load_settings()
        load_windows_settings()
    end

    client.delay_call(0, function()
        client.set_event_callback('paint_ui', on_paint_ui)
        client.set_event_callback('setup_command', on_setup_command)
        client.set_event_callback('pre_config_save', save_windows_settings)
        client.set_event_callback('post_config_load', load_windows_settings)
    end)

    return windows
end

return M
