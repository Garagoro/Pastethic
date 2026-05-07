local M = {}

-- Patch the external colorskins bundle so it cooperates with Pasthetic configs/runtime.
-- Keep this module data-only: no UI, callbacks, or globals are created here.
function M.patch_colorskins(source)
    return source
end

function M._patch_colorskins_legacy(source)
    source = source:gsub('\r\n', '\n')

    source = source:gsub(
        'last_weapon_ent = nil,\n',
        'last_weapon_ent = nil,\n    last_skin_key = nil,\n    refresh_token = 0,\n',
        1
    )

    source = source:gsub(
        'local force_update = function%(%)[\r\n]+%s*ui%.set%(ctx%.refs%.skins_enabled, false%)[\r\n]+%s*client%.delay_call%(0%.6, ui%.set, ctx%.refs%.skins_enabled, true%)[\r\n]+end',
        'local ensure_skinchanger_enabled = function()\n    if not ui.get(ctx.refs.skins_enabled) then\n        ui.set(ctx.refs.skins_enabled, true)\n    end\nend\n\nlocal force_update = function()\n    ui.set(ctx.refs.skins_enabled, false)\n    client.delay_call(0.8, ensure_skinchanger_enabled)\nend\n\nlocal fast_force_update = function()\n    ctx.refresh_token = (ctx.refresh_token or 0) + 1\n    ui.set(ctx.refs.skins_enabled, false)\n    client.delay_call(0.8, ensure_skinchanger_enabled)\nend',
        1
    )

    source = source:gsub(
        'local set_paintkit_colors = function%( paintkit %)',
        [[local schedule_apply_config = function(should_force_update)
    local delays = { 0.8 }

    for i = 1, #delays do
        client.delay_call(delays[i], function()
            apply_saved_skin_for_current_weapon()
            local applied = apply_config_for_current_skin(false)
            if should_force_update and i <= 3 and applied then
                fast_force_update()
            end
end

local refresh_active_weapon_skin = function()
    local player = entity.get_local_player()
    if player == nil then return end

    local weapon = entity.get_player_weapon(player)
    if weapon == nil then return end

    apply_saved_skin_for_current_weapon()
    local team_weapon_key = get_weapon_team_key()
    local key, paintkit, weapon_id, team, legacy_key = get_skin_key()
    if weapon == ctx.last_weapon_ent and key == ctx.last_skin_key and team_weapon_key == ctx.last_weapon_team_key then return end

    ctx.last_weapon_ent = weapon
    ctx.last_skin_key = key
    ctx.last_weapon_team_key = team_weapon_key

    local has_saved_colors = (
        key ~= nil
        and (
            ctx.skin_color_config[key] ~= nil
            or (legacy_key ~= nil and ctx.skin_color_config[legacy_key] ~= nil)
        )
    )

    if has_saved_colors and paintkit ~= nil then
        ctx.applied_skins[key] = nil
        ctx.paintkit_owner[paintkit] = nil
        ensure_skinchanger_enabled()
    end

    if apply_config_for_current_skin(false) then
        fast_force_update()
    end

    if has_saved_colors then
        client.delay_call(0.8, ensure_skinchanger_enabled)
    end

    schedule_apply_config(true)
end

local set_paintkit_colors = function( paintkit )]],
        1
    )

    source = source:gsub(
        [[    force_update()
end

local weapon_skin_cb = function()]],
        [[    force_update()
    client.delay_call(0.8, function() set_paintkit_colors(ctx.current_paintkit); apply_config_for_current_skin(true) end)
end

local weapon_skin_cb = function()]],
        1
    )

    source = source:gsub(
        [[local startup_skin_refresh = function()
    client.delay_call(0.2, function() apply_config_for_current_skin(true) end)
    client.delay_call(0.8, function() apply_config_for_current_skin(true) end)
    client.delay_call(1.4, function() apply_config_for_current_skin(true) end)
end]],
        [[local startup_skin_refresh = function()
    client.delay_call(0.05, refresh_active_weapon_skin)
    client.delay_call(0.8, function() schedule_apply_config(true) end)
end]],
        1
    )

    source = source:gsub(
        [[local startup_skin_refresh = function()
    client.delay_call(0.2, function() apply_saved_skin_for_current_weapon(); apply_config_for_current_skin(true) end)
    client.delay_call(0.8, function() apply_saved_skin_for_current_weapon(); apply_config_for_current_skin(true) end)
    client.delay_call(1.4, function() apply_saved_skin_for_current_weapon(); apply_config_for_current_skin(true) end)
end]],
        [[local startup_skin_refresh = function()
    client.delay_call(0.05, refresh_active_weapon_skin)
    client.delay_call(0.8, function() schedule_apply_config(true) end)
end]],
        1
    )

    source = source:gsub(
        [[startup_skin_refresh()
client.set_event_callback("paint", function()
    local player = entity.get_local_player()
    if player == nil then return end

    local weapon = entity.get_player_weapon(player)
    if weapon == nil or weapon == ctx.last_weapon_ent then return end

    ctx.last_weapon_ent = weapon
    client.delay_call(0.1, function() apply_config_for_current_skin(true) end)
    client.delay_call(0.5, function() apply_config_for_current_skin(true) end)
end)]],
        [[startup_skin_refresh()
client.set_event_callback("setup_command", refresh_active_weapon_skin)
client.set_event_callback("item_equip", function(event)
    if client.userid_to_entindex(event.userid) ~= entity.get_local_player() then return end

    ctx.last_weapon_ent = nil
    ctx.last_skin_key = nil
    ctx.last_weapon_team_key = nil
    schedule_apply_config(true)
end)
client.set_event_callback("paint", function()
    refresh_active_weapon_skin()
end)]],
        1
    )

    source = source:gsub(
        [[startup_skin_refresh()
client.set_event_callback("paint", function()
    local player = entity.get_local_player()
    if player == nil then return end

    local weapon = entity.get_player_weapon(player)
    local team_weapon_key = get_weapon_team_key()
    if weapon == nil or (weapon == ctx.last_weapon_ent and team_weapon_key == ctx.last_weapon_team_key) then return end

    ctx.last_weapon_ent = weapon
    ctx.last_weapon_team_key = team_weapon_key
    client.delay_call(0.1, function() apply_saved_skin_for_current_weapon(); apply_config_for_current_skin(true) end)
    client.delay_call(0.5, function() apply_saved_skin_for_current_weapon(); apply_config_for_current_skin(true) end)
end)]],
        [[startup_skin_refresh()
client.set_event_callback("setup_command", refresh_active_weapon_skin)
client.set_event_callback("item_equip", function(event)
    if client.userid_to_entindex(event.userid) ~= entity.get_local_player() then return end

    ctx.last_weapon_ent = nil
    ctx.last_skin_key = nil
    ctx.last_weapon_team_key = nil
    schedule_apply_config(true)
end)
client.set_event_callback("paint", function()
    refresh_active_weapon_skin()
end)]],
        1
    )

    return source
end



return M
