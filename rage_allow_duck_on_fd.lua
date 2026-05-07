local M = {}

function M.start(deps)
    local resource = assert(deps.resource, 'rage_allow_duck_on_fd: resource dependency is required')
    local ui = assert(deps.ui, 'rage_allow_duck_on_fd: ui dependency is required')
    local entity = assert(deps.entity, 'rage_allow_duck_on_fd: entity dependency is required')
    local localplayer = assert(deps.localplayer, 'rage_allow_duck_on_fd: localplayer dependency is required')
    local override = assert(deps.override, 'rage_allow_duck_on_fd: override dependency is required')
    local utils = assert(deps.utils, 'rage_allow_duck_on_fd: utils dependency is required')

    local ref = resource.main.ragebot.allow_duck_on_fd

    local ref_duck_peek_assist = ui.reference(
        'Rage', 'Other', 'Duck peek assist'
    )

    local should_override = false

    local function on_shutdown()
        override.unset(ref_duck_peek_assist)
    end

    local function on_setup_command(cmd)
        local me = entity.get_local_player()

        if me == nil then
            return
        end

        local duck_amount = entity.get_prop(me, 'm_flDuckAmount')

        local should_unoverride = (
            ui.is_menu_open() or
            cmd.in_duck == 0 or
            not localplayer.is_onground
        )

        if should_unoverride then
            should_override = false
        elseif duck_amount > 0.75 then
            should_override = true
        end

        if should_override then
            override.set(ref_duck_peek_assist, 'On hotkey', 0)
        else
            override.unset(ref_duck_peek_assist)
        end
    end

    local function on_enabled(item)
        local value = item:get()

        if not value then
            override.unset(ref_duck_peek_assist)
        end

        utils.event_callback('shutdown', on_shutdown, value)
        utils.event_callback('setup_command', on_setup_command, value)
    end

    ref.enabled:set_callback(on_enabled, true)
end

return M
