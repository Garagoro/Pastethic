local M = {}

function M.new(deps)
    deps = deps or {}

    local menu = deps.menu
    local event_system = deps.event_system
    local logging = deps.logging or {}
    local ui_debug = deps.ui_debug
    local menu_logic = {}

    local item_data = {}
    local item_list = {}
    local logic_events = event_system:new()
    local init_count = 0
    local force_update_count = 0

    local function is_debug_enabled()
        return ui_debug ~= nil and type(ui_debug.is_enabled) == 'function' and ui_debug:is_enabled()
    end

    function menu_logic.get_event_bus()
        return logic_events
    end

    function menu_logic.set(item, value)
        if item == nil or item.ref == nil then
            return
        end

        item_data[item.ref] = value
    end

    function menu_logic.register_external(item)
        if item == nil or item.ref == nil then
            return
        end

        item_data[item.ref] = false
        item:set_visible(false)
        table.insert(item_list, item)
    end

    if is_debug_enabled() then
        function menu_logic.debug_snapshot()
            local visible_true = 0
            local visible_false = 0
            local pending = 0

            for i = 1, #item_list do
                local item = item_list[i]
                local value = item ~= nil and item.ref ~= nil and item_data[item.ref] or nil

                if value ~= nil then
                    pending = pending + 1

                    if value then
                        visible_true = visible_true + 1
                    else
                        visible_false = visible_false + 1
                    end
                end
            end

            return {
                total = #item_list,
                pending = pending,
                visible_true = visible_true,
                visible_false = visible_false
            }
        end
    end

    function menu_logic.force_update()
        force_update_count = force_update_count + 1

        local applied_true = 0
        local applied_false = 0
        local skipped = 0
        local failed = 0

        for i = 1, #item_list do
            local item = item_list[i]

            if item == nil then
                skipped = skipped + 1
                goto continue
            end

            local ref = item.ref

            if ref == nil then
                skipped = skipped + 1
                goto continue
            end

            local value = item_data[ref]

            if value == nil then
                skipped = skipped + 1
                goto continue
            end

            local ok, result = pcall(item.set_visible, item, value)

            if ok then
                if value then
                    applied_true = applied_true + 1
                else
                    applied_false = applied_false + 1
                end
            else
                failed = failed + 1

                if type(logging.error) == 'function' then
                    logging.error(string.format('menu visibility error: %s', tostring(result)))
                end
            end

            item_data[ref] = false

            ::continue::
        end

        if is_debug_enabled() and type(ui_debug.force_update) == 'function' then
            ui_debug:force_update(force_update_count, #item_list, applied_true, applied_false, skipped, failed)
        end
    end

    function menu_logic.update(...)
        logic_events.update:fire(...)
        menu_logic.force_update()
    end

    local menu_events = menu.get_event_bus()

    local function on_item_init(item)
        init_count = init_count + 1
        item_data[item.ref] = false
        item:set_visible(false)

        table.insert(item_list, item)

        if is_debug_enabled() and type(ui_debug.item_init) == 'function' then
            ui_debug:item_init(init_count, item.type, #item_list)
        end
    end

    local function on_item_changed(...)
        if is_debug_enabled() and type(ui_debug.item_changed) == 'function' then
            ui_debug:item_changed(force_update_count)
        end

        menu_logic.update(...)
    end

    menu_events.item_init:set(on_item_init)
    menu_events.item_changed:set(on_item_changed)

    return menu_logic
end

return M
