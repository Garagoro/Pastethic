local M = {}

function M.start(deps)
    local resource = assert(deps.resource, 'rage_hideshots_fix: resource dependency is required')
    local ui = assert(deps.ui, 'rage_hideshots_fix: ui dependency is required')
    local software = assert(deps.software, 'rage_hideshots_fix: software dependency is required')
    local override = assert(deps.override, 'rage_hideshots_fix: override dependency is required')
    local utils = assert(deps.utils, 'rage_hideshots_fix: utils dependency is required')

    local ref = resource.main.ragebot.hideshots_fix

    local ref_fake_lag_enabled = {
        ui.reference('AA', 'Fake lag', 'Enabled')
    }

    local function restore_values()
        override.unset(ref_fake_lag_enabled[1])
    end

    local function update_values()
        override.set(ref_fake_lag_enabled[1], false)
    end

    local function on_shutdown()
        restore_values()
    end

    local function on_paint_ui()
        restore_values()
    end

    local function on_setup_command()
        local is_fake_duck = software.is_duck_peek_assist()
        local is_double_tap = software.is_double_tap_active()
        local is_on_shot_antiaim = software.is_on_shot_antiaim_active()

        local should_update = (
            is_on_shot_antiaim
            and not is_double_tap
            and not is_fake_duck
        )

        if should_update then
            update_values()
        else
            restore_values()
        end
    end

    local function update_event_callbacks(value)
        if not value then
            restore_values()
        end

        utils.event_callback('shutdown', on_shutdown, value)
        utils.event_callback('paint_ui', on_paint_ui, value)
        utils.event_callback('setup_command', on_setup_command, value)
    end

    local function on_enabled(item)
        update_event_callbacks(item:get())
    end

    ref.enabled:set_callback(on_enabled, true)
end

return M
