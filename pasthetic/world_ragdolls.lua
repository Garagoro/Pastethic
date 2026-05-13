local M = {}

function M.start(deps)
    local resource = assert(deps.resource, 'world_ragdolls: resource dependency is required')
    local entity = assert(deps.entity, 'world_ragdolls: entity dependency is required')
    local utils = assert(deps.utils, 'world_ragdolls: utils dependency is required')

    local ref = resource.render_we.world.ragdolls
    local hidden = {}

    local function is_ragdoll(ent)
        local ok, classname = pcall(entity.get_classname, ent)
        if not ok or type(classname) ~= 'string' then
            return false
        end

        classname = classname:lower()
        return classname:find('ragdoll', 1, true) ~= nil
    end

    local function set_hidden(ent, value)
        pcall(entity.set_prop, ent, 'm_nRenderMode', value and 10 or 0)
        pcall(entity.set_prop, ent, 'm_fEffects', value and 32 or 0)
        pcall(entity.set_prop, ent, 'm_clrRender', 255, 255, 255, value and 0 or 255)
    end

    local function restore()
        for ent in pairs(hidden) do
            set_hidden(ent, false)
            hidden[ent] = nil
        end
    end

    local function run()
        if not ref.remove:get() then
            restore()
            return
        end

        local ragdolls = entity.get_all('CCSRagdoll') or {}
        for i = 1, #ragdolls do
            local ent = ragdolls[i]
            set_hidden(ent, true)
            hidden[ent] = true
        end

        local all = entity.get_all() or {}
        for i = 1, #all do
            local ent = all[i]
            if hidden[ent] == nil and is_ragdoll(ent) then
                set_hidden(ent, true)
                hidden[ent] = true
            end
        end
    end

    ref.remove:set_callback(function(item)
        if not item:get() then
            restore()
        end
    end, true)

    utils.event_callback('paint', run, true)
    utils.event_callback('round_start', restore, true)
    utils.event_callback('player_spawn', restore, true)
    utils.event_callback('shutdown', restore, true)
end

return M
