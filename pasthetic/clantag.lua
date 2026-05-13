local M = {}

function M.start(deps)
    local resource = assert(deps.resource, 'clantag: resource dependency is required')
    local client = assert(deps.client, 'clantag: client dependency is required')
    local globals = assert(deps.globals, 'clantag: globals dependency is required')
    local utils = assert(deps.utils, 'clantag: utils dependency is required')

    local ref = resource.main.miscellaneous.clantag
    local last_tag = nil
    local last_index = nil
    local frame_time = 0.25

    if type(client.set_clan_tag) ~= 'function' then
        return
    end

    local frames = {
        '[---------]',
        '[p--------]',
        '[pa-------]',
        '[pas------]',
        '[past-----]',
        '[pasth----]',
        '[pasthe---]',
        '[pasthet--]',
        '[pastheti-]',
        '[pasthetic]',
        '[p4sthetic]',
        '[p4$thetic]',
        '[p4$7hetic]',
        '[p4$7he7ic]',
        '[p4$7he71c]',
        '[pa$7he71c]',
        '[pas7he71c]',
        '[pasthe71c]',
        '[pasthet1c]',
        '[pasthetic]',
        '[pastheti<]',
        '[pasthet<c]',
        '[pasthe<ic]',
        '[pasth<tic]',
        '[past<etic]',
        '[pas<hetic]',
        '[pa<thetic]',
        '[p<sthetic]',
        '[<asthetic]',
        '[pasthetic]',
        '[pastheti-]',
        '[pasthet--]',
        '[pasthe---]',
        '[pasth----]',
        '[past-----]',
        '[pas------]',
        '[pa-------]',
        '[p--------]',
        '[---------]'
    }

    local function set_tag(tag)
        if tag == last_tag then
            return
        end

        client.set_clan_tag(tag)
        last_tag = tag
    end

    local function get_synced_time()
        if type(globals.tickcount) == 'function' and type(globals.tickinterval) == 'function' then
            return globals.tickcount() * globals.tickinterval()
        end

        if type(globals.curtime) == 'function' then
            return globals.curtime()
        end

        return globals.realtime()
    end

    local function get_frame()
        local index = math.floor(get_synced_time() / frame_time) % #frames + 1

        return frames[index], index
    end

    local function reset()
        last_tag = nil
        last_index = nil
        client.set_clan_tag('')
    end

    local function on_paint()
        if not ref.enabled:get() then
            if last_tag ~= nil then
                reset()
            end
            return
        end

        local tag, index = get_frame()
        if index == last_index then
            return
        end

        last_index = index
        set_tag(tag)
    end

    local function on_enabled(item)
        local enabled = item:get()

        if not enabled then
            reset()
        end

        utils.event_callback('shutdown', reset, enabled)
    end

    utils.event_callback('paint', on_paint, true)
    ref.enabled:set_callback(on_enabled, true)
end

return M
