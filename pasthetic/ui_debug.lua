-- UI debug helpers are intentionally NOT loaded by default.
-- Enable manually only when diagnosing menu visibility issues:
--   1. require this module in aes.lua
--   2. create ui_debug = pasthetic_ui_debug.new({ logging = logging, client = client, enabled = true })
--   3. pass ui_debug to pasthetic_menu_logic.new(...) and pasthetic_resource_builder.start(...)

local M = {}

local UiDebug = {}
UiDebug.__index = UiDebug

local function as_bool(value)
    return value and 'true' or 'false'
end

function M.new(deps)
    deps = deps or {}

    return setmetatable({
        enabled = deps.enabled == true,
        logging = deps.logging,
        client = deps.client,
        prefix = deps.prefix or '[ui-debug]',
        limit = deps.limit or 12
    }, UiDebug)
end

function M.disabled()
    return M.new({ enabled = false })
end

function UiDebug:is_enabled()
    return self.enabled == true
end

function UiDebug:log(message)
    if not self:is_enabled() then
        return
    end

    local text = self.prefix .. ' ' .. message

    if self.logging ~= nil and type(self.logging.log) == 'function' then
        self.logging.log(text)
        return
    end

    if self.client ~= nil and type(self.client.log) == 'function' then
        self.client.log('[Pasthetic] ' .. text)
    end
end

function UiDebug:item_init(count, item_type, total)
    if count <= 5 or count == 25 or count == 100 or count == 250 or count == 500 then
        self:log(string.format('item_init #%d: type=%s total=%d', count, tostring(item_type), total))
    end
end

function UiDebug:item_changed(force_update_count)
    if force_update_count <= self.limit then
        self:log('item_changed: firing visibility update')
    end
end

function UiDebug:force_update(count, total, applied_true, applied_false, skipped, failed)
    if count > self.limit then
        return
    end

    self:log(string.format(
        'force_update #%d: total=%d true=%d false=%d skipped=%d failed=%d',
        count, total, applied_true, applied_false, skipped, failed
    ))
end

function UiDebug:general_created(general)
    self:log(string.format(
        'general created: script_name=%s script_user=%s category=%s category_type=%s',
        as_bool(general ~= nil and general.script_name ~= nil),
        as_bool(general ~= nil and general.script_user ~= nil),
        as_bool(general ~= nil and general.category ~= nil),
        general ~= nil and general.category ~= nil and tostring(general.category.type) or 'nil'
    ))
end

function UiDebug:visibility_begin(reason, count, category)
    if count <= self.limit then
        self:log(string.format('visibility %s #%d: category=%s', reason, count, tostring(category)))
    end
end

function UiDebug:visibility_queued(reason, count, snapshot)
    if count > self.limit or snapshot == nil then
        return
    end

    self:log(string.format(
        'visibility %s #%d queued: total=%d pending=%d true=%d false=%d',
        reason,
        count,
        snapshot.total or 0,
        snapshot.pending or 0,
        snapshot.visible_true or 0,
        snapshot.visible_false or 0
    ))
end

function UiDebug:before_init_force_update(snapshot)
    if snapshot == nil then
        return
    end

    self:log(string.format(
        'before init force_update: total=%d pending=%d true=%d false=%d',
        snapshot.total or 0,
        snapshot.pending or 0,
        snapshot.visible_true or 0,
        snapshot.visible_false or 0
    ))
end

return M
