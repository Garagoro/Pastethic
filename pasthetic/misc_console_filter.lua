local M = {}

function M.start(deps)
    local resource = assert(deps.resource, 'misc_console_filter: resource dependency is required')
    local cvar = assert(deps.cvar, 'misc_console_filter: cvar dependency is required')
    local client = assert(deps.client, 'misc_console_filter: client dependency is required')

    local ref = resource.main.miscellaneous.console_filter
    local con_filter_enable = cvar.con_filter_enable
    local con_filter_text = cvar.con_filter_text

    local function restore_values()
        con_filter_enable:set_int(tonumber(con_filter_enable:get_string()))
        con_filter_text:set_string('')
    end

    local function update_values()
        con_filter_enable:set_raw_int(1)
        con_filter_text:set_string('[gamesense]')
    end

    local function update_loop()
        if not ref.enabled:get() then
            return
        end

        update_values()
        client.delay_call(1, update_loop)
    end

    local function update_event_callbacks(value)
        if value then
            update_loop()
        else
            restore_values()
        end
    end

    local function on_enabled(item)
        update_event_callbacks(item:get())
    end

    ref.enabled:set_callback(on_enabled, true)
end

return M
