local M = {}

function M.new(deps)
    deps = deps or {}

    local client = deps.client or client
    local localplayer = deps.localplayer
    local software = deps.software
    local statement = {}
    local list = {}
    local count = 0

    local function add(state)
        count = count + 1
        list[count] = state
    end

    local function clear_list()
        for i = 1, count do
            list[i] = nil
        end

        count = 0
    end

    local function update_onground()
        if not localplayer.is_onground then
            return
        end

        if localplayer.is_moving then
            add 'Moving'

            if localplayer.is_crouched then
                return
            end

            if software.is_slow_motion() then
                add 'Slow Walk'
            end

            return
        end

        add 'Standing'
    end

    local function update_crouched()
        if not localplayer.is_crouched then
            return
        end

        add 'Crouch'

        if localplayer.is_moving then
            add 'Move-Crouch'
        end
    end

    local function update_in_air()
        if localplayer.is_onground then
            return
        end

        add 'Air'

        if localplayer.is_crouched then
            add 'Air-Crouch'
        end
    end

    function statement.get()
        return list
    end

    local function on_setup_command()
        clear_list()

        update_onground()
        update_crouched()
        update_in_air()
    end

    client.set_event_callback(
        'setup_command',
        on_setup_command
    )

    return statement
end

return M
