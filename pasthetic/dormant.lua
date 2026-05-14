local M = {}
local started = false

function M.start()
    if started then
        return rawget(_G, 'pasthetic_dormant')
    end

    started = true
-- local variables for API functions. any changes to the line below will be lost on re-generation
local client_visible, client_eye_position, client_log, client_trace_bullet, entity_get_bounding_box, entity_get_local_player, entity_get_origin, entity_get_player_name, entity_get_player_resource, entity_get_player_weapon, entity_get_prop, entity_is_dormant, entity_is_enemy, globals_curtime, globals_maxplayers, globals_tickcount, math_max, renderer_indicator, string_format, ui_get, ui_new_checkbox, ui_new_hotkey, ui_reference, ui_set_callback, sqrt, unpack, entity_is_alive, plist_get = client.visible, client.eye_position, client.log, client.trace_bullet, entity.get_bounding_box, entity.get_local_player, entity.get_origin, entity.get_player_name, entity.get_player_resource, entity.get_player_weapon, entity.get_prop, entity.is_dormant, entity.is_enemy, globals.curtime, globals.maxplayers, globals.tickcount, math.max, renderer.indicator, string.format, ui.get, ui.new_checkbox, ui.new_hotkey, ui.reference, ui.set_callback, sqrt, unpack, entity.is_alive, plist.get

local ffi = require "ffi"
local vector = require "vector"
local weapons = require "gamesense/csgo_weapons"

local native_GetClientEntity = vtable_bind("client_panorama.dll", "VClientEntityList003", 3, "void*(__thiscall*)(void*,int)")
local native_IsWeapon = vtable_thunk(165, "bool(__thiscall*)(void*)")
local native_GetInaccuracy = vtable_thunk(482, "float(__thiscall*)(void*)")


local ref = {
    mindmg = ui_reference("RAGE", "Aimbot", "Minimum damage"),
    dormantEsp = ui_reference("VISUALS", "Player ESP", "Dormant"),
}

local menu = {
    dormant_switch = ui_new_checkbox("AA", "Anti-aimbot angles", "Dormant aimbot"),
    dormant_key = ui_new_hotkey("AA", "Anti-aimbot angles", "Dormant aimbot", true),
    dormant_mindmg = ui.new_slider("AA", "Anti-aimbot angles", "Dormant minimum damage", 0, 100, 10, true),
    dormant_indicator = ui_new_checkbox("AA", "Anti-aimbot angles", "Dormant indicator"),
}

local player_info_prev = {}
local position_memory = {}
local real_position_memory = {}
local roundStarted = 0
local dormant_esp_restore = nil
local callbacks_registered = false
local MAX_DORMANT_CACHE_TICKS = 128
local MAX_DORMANT_REAL_DISTANCE_SQR = 650 * 650
local MAX_DORMANT_REAL_Z_DELTA = 160
local MIN_DORMANT_ALPHA = 0.18
local MIN_DORMANT_ORIGIN_LENGTH_SQR = 64 * 64

local function modify_velocity(e, goalspeed)
    local minspeed = math.sqrt((e.forwardmove * e.forwardmove) + (e.sidemove * e.sidemove))
    if goalspeed <= 0 or minspeed <= 0 then
        return
    end

    if e.in_duck == 1 then
        goalspeed = goalspeed * 2.94117647
    end

    if minspeed <= goalspeed then
        return
    end

    local speedfactor = goalspeed / minspeed
    e.forwardmove = e.forwardmove * speedfactor
    e.sidemove = e.sidemove * speedfactor
end

local estimated_points = {
    { name = "stomach", z = 40, weight = 1.00, bonus_damage = 0 },
    { name = "chest", z = 52, weight = 0.82, bonus_damage = 0 },
    { name = "pelvis", z = 30, weight = 0.72, bonus_damage = 0 },
    { name = "head", z = 62, weight = 0.35, bonus_damage = 5 },
}

local function scan_estimated_points(lp, eyepos, origin, mindmg)
    local best_point, best_damage, best_name
    local best_score = -1

    for i = 1, #estimated_points do
        local data = estimated_points[i]
        local point = origin + vector(0, 0, data.z)
        local _, damage = client_trace_bullet(lp, eyepos.x, eyepos.y, eyepos.z, point.x, point.y, point.z, true)
        damage = damage or 0

        local hidden = not client_visible(point.x, point.y, point.z)
        if damage > (mindmg + data.bonus_damage) and hidden then
            local score = damage * data.weight
            if score > best_score then
                best_score = score
                best_point = point
                best_damage = damage
                best_name = data.name
            end
        end
    end

    return best_point, best_damage, best_name
end

local function is_origin_stable(origin, old_origin, alpha, old_alpha)
    if old_origin == nil or old_alpha == nil then
        return false
    end

    local dx = origin.x - old_origin.x
    local dy = origin.y - old_origin.y
    local dz = origin.z - old_origin.z

    return (dx * dx + dy * dy + dz * dz) <= 64 and alpha > 0.795 and old_alpha > 0.75
end

local function get_accuracy_limit(weapon)
    if weapon.type == "sniperrifle" then
        return 0.009
    end

    if weapon.is_revolver then
        return 0.0065
    end

    if weapon.type == "pistol" then
        return 0.0075
    end

    return 0.009
end

local function is_valid_origin(x, y, z)
    if x == nil or y == nil or z == nil then
        return false
    end

    if x ~= x or y ~= y or z ~= z then
        return false
    end

    if math.abs(x) > 32768 or math.abs(y) > 32768 or z < -4096 or z > 8192 then
        return false
    end

    return (x * x + y * y + z * z) > MIN_DORMANT_ORIGIN_LENGTH_SQR
end

local function is_valid_dormant_box(x1, y1, x2, y2, alpha)
    if x1 == nil or y1 == nil or x2 == nil or y2 == nil or alpha == nil then
        return false
    end

    if alpha < MIN_DORMANT_ALPHA or alpha > 1.05 then
        return false
    end

    return x2 > x1 and y2 > y1
end

local function remember_real_position(player, origin)
    real_position_memory[player] = origin
end

local function forget_position(player)
    position_memory[player] = nil
end

local function is_plausible_from_real_position(player, origin)
    local cached = real_position_memory[player]

    if cached == nil or origin == nil then
        return false
    end

    local dx = origin.x - cached.x
    local dy = origin.y - cached.y
    local dz = origin.z - cached.z

    return math.abs(dz) <= MAX_DORMANT_REAL_Z_DELTA and (dx * dx + dy * dy + dz * dz) <= MAX_DORMANT_REAL_DISTANCE_SQR
end

local function remember_position(player, origin, tickcount, alpha)
    position_memory[player] = {
        origin = origin,
        tick = tickcount,
        alpha = alpha or 1
    }
end

local function get_remembered_position(player, tickcount)
    local cached = position_memory[player]
    if cached == nil then
        return nil
    end

    if tickcount - cached.tick > MAX_DORMANT_CACHE_TICKS then
        return nil
    end

    return cached.origin, cached.alpha
end

local function get_weapon_pointer(lp, weapon_index)
    local weapon_handle = entity_get_prop(lp, "m_hActiveWeapon")
    local weapon_ptr = weapon_handle ~= nil and native_GetClientEntity(bit.band(weapon_handle, 0xFFF)) or nil

    if weapon_ptr ~= nil and native_IsWeapon(weapon_ptr) then
        return weapon_ptr
    end

    weapon_ptr = weapon_index ~= nil and native_GetClientEntity(weapon_index) or nil
    if weapon_ptr ~= nil and native_IsWeapon(weapon_ptr) then
        return weapon_ptr
    end

    return nil
end

local function on_setup_command(cmd)
    if not ui_get(menu.dormant_switch) then
        return
    end

    local lp = entity_get_local_player()
    if lp == nil or not entity_is_alive(lp) then
        player_info_prev = {}
        position_memory = {}
        real_position_memory = {}
        return
    end

    local my_weapon = entity_get_player_weapon(lp)
    if not my_weapon then
        return
    end

    local ent = get_weapon_pointer(lp, my_weapon)
    local inaccuracy = 0
    if ent ~= nil and native_IsWeapon(ent) then
        inaccuracy = native_GetInaccuracy(ent) or 0
    else
        inaccuracy = entity_get_prop(my_weapon, "m_fAccuracyPenalty") or 0
    end

    local tickcount = globals_tickcount()
    local player_resource = entity_get_player_resource()
    if player_resource == nil then
        return
    end

    local eye_x, eye_y, eye_z = client_eye_position()
    if eye_x == nil then
        return
    end

    local eyepos = vector(eye_x, eye_y, eye_z)
    local simtime = entity_get_prop(lp, "m_flSimulationTime") or globals_curtime()
    local weapon = weapons(my_weapon)
    if weapon == nil then
        return
    end

    local scoped = entity_get_prop(lp, "m_bIsScoped") == 1
    local flags = entity_get_prop(lp, 'm_fFlags') or 0
    local onground = bit.band(flags, bit.lshift(1, 0))
    if tickcount < roundStarted then return end -- to prevent shooting at ghost dormant esp @ the beginning of round

    local can_shoot
    if weapon.is_revolver then -- for some reason can_shoot returns always false with r8 despite all 3 props being true, no idea why
        can_shoot = simtime > (entity_get_prop(my_weapon, "m_flNextPrimaryAttack") or math.huge) -- doing this fixes it ><
    elseif weapon.is_melee_weapon then
        can_shoot = false
    else
        can_shoot = simtime > math_max(
            entity_get_prop(lp, "m_flNextAttack") or math.huge,
            entity_get_prop(my_weapon, "m_flNextPrimaryAttack") or math.huge,
            entity_get_prop(my_weapon, "m_flNextSecondaryAttack") or 0
        )
    end

    -- new player info
    local player_info = {}

    -- loop through all players and continue if they're connected
    for player=1, globals_maxplayers() do
        if entity_get_prop(player_resource, "m_bConnected", player) == 1 then
            if plist_get(player, "Add to whitelist") then goto skip end
            if entity_is_enemy(player) and entity_is_alive(player) then
                local can_hit

                local origin_x, origin_y, origin_z = entity_get_origin(player)
                local x1, y1, x2, y2, alpha_multiplier = entity_get_bounding_box(player) -- grab alpha of the dormant esp
                local has_dormant_snapshot = origin_x ~= nil or origin_y ~= nil or origin_z ~= nil or alpha_multiplier ~= nil
                local current_origin = is_valid_origin(origin_x, origin_y, origin_z) and vector(origin_x, origin_y, origin_z) or nil

                if not entity_is_dormant(player) then
                    if current_origin ~= nil then
                        remember_position(player, current_origin, tickcount, 1)
                        remember_real_position(player, current_origin)
                        player_info[player] = {current_origin, 1, false, 0}
                    end
                    goto skip
                end

                local origin = nil
                local origin_alpha = alpha_multiplier
                if has_dormant_snapshot then
                    if current_origin ~= nil
                        and is_valid_dormant_box(x1, y1, x2, y2, alpha_multiplier)
                        and is_plausible_from_real_position(player, current_origin)
                    then
                        origin = current_origin
                        remember_position(player, origin, tickcount, alpha_multiplier)
                    else
                        forget_position(player)
                    end
                else
                    origin, origin_alpha = get_remembered_position(player, tickcount)
                end

                if origin ~= nil then
                    local previous = player_info_prev[player]
                    local old_origin, old_alpha, old_hittable, old_stable_ticks = nil, nil, nil, 0
                    if previous ~= nil then
                        old_origin, old_alpha, old_hittable, old_stable_ticks = unpack(previous)
                    end

                    -- update check
                    local dormant_accurate = origin_alpha == nil or origin_alpha >= MIN_DORMANT_ALPHA

                    if dormant_accurate then
                        local target, dmg = scan_estimated_points(lp, eyepos, origin, ui_get(menu.dormant_mindmg))
                        local stable_ticks = is_origin_stable(origin, old_origin, origin_alpha or 1, old_alpha or 1) and ((old_stable_ticks or 0) + 1) or 0
                        if stable_ticks > 6 then
                            stable_ticks = 6
                        end

                        can_hit = target ~= nil and stable_ticks > 0
                        if can_shoot and can_hit and ui_get(menu.dormant_key) then
                            local pitch, yaw = eyepos:to(target):angles()
                            local max_speed = scoped and weapon.max_player_speed_alt or weapon.max_player_speed
                            if max_speed ~= nil then
                                modify_velocity(cmd, max_speed * 0.33)
                            end

                            -- autoscope
                            if not scoped and weapon.type == "sniperrifle" and cmd.in_jump == 0 and onground == 1 then
                                cmd.in_attack2 = 1
                            end
                            
                            local waiting_for_scope = weapon.type == "sniperrifle" and not scoped
                            if not waiting_for_scope and inaccuracy < get_accuracy_limit(weapon) and cmd.chokedcommands == 0 then
                                cmd.pitch = pitch
                                cmd.yaw = yaw
                                cmd.in_attack = 1

                                -- dont shoot again
                                can_shoot = false
                            end
                        end
                    end

                    local stable_ticks = is_origin_stable(origin, old_origin, origin_alpha or 1, old_alpha or 1) and ((old_stable_ticks or 0) + 1) or 0
                    if stable_ticks > 6 then
                        stable_ticks = 6
                    end

                    player_info[player] = {origin, origin_alpha or 1, can_hit, stable_ticks}
                end
            end
        end
        ::skip::
    end
    player_info_prev = player_info
end

client.register_esp_flag("DA", 255, 255, 255, function(player)
    if ui.get(menu.dormant_switch) and entity.is_enemy(player) and player_info_prev[player] ~= nil and entity.is_alive(entity_get_local_player()) then
        local _, _, can_hit = unpack(player_info_prev[player])

        return can_hit
    end
end)
local function painter()
    if not entity_is_alive(entity_get_local_player()) then return end -- dont draw if dead :lowiqq:
    if ui_get(menu.dormant_switch) and ui_get(menu.dormant_key) and ui_get(menu.dormant_indicator) then
        local colors = {132,196,20,245}
        for k, v in pairs(player_info_prev) do
            if k ~= nil then
                if v[3] == true then
                    colors = {252,222,30,245}
                    break
                end
            end
        end
        renderer_indicator(colors[1],colors[2],colors[3],colors[4], "DA")
    end
end
local function resetter()
    local freezetime = (cvar.mp_freezetime:get_float()+1) / globals.tickinterval() -- get freezetime plus 1 second and disable dormantbob for that amount of ticks
    roundStarted = globals_tickcount() + freezetime
    player_info_prev = {}
    position_memory = {}
    real_position_memory = {}
end

local function update_state()
    local czechbox = ui_get(menu.dormant_switch)

    if czechbox then
        if dormant_esp_restore == nil then
            dormant_esp_restore = ui_get(ref.dormantEsp)
        end

        ui.set(ref.dormantEsp, true)

        if not callbacks_registered then
            client.set_event_callback("setup_command", on_setup_command)
            client.set_event_callback("paint", painter)
            client.set_event_callback("round_prestart", resetter)
            callbacks_registered = true
        end
    elseif dormant_esp_restore ~= nil then
        ui.set(ref.dormantEsp, dormant_esp_restore)
        dormant_esp_restore = nil
        player_info_prev = {}
    end

    if not czechbox and callbacks_registered then
        client.unset_event_callback("setup_command", on_setup_command)
        client.unset_event_callback("paint", painter)
        client.unset_event_callback("round_prestart", resetter)
        callbacks_registered = false
    end

end

_G.pasthetic_dormant = {
    refs = menu,
    update_state = update_state
}
_G.aesthetic_dormant = _G.pasthetic_dormant

ui_set_callback(menu.dormant_switch, update_state)
update_state()
ui.set(menu.dormant_indicator, true)

client.set_event_callback("shutdown", function()
    if callbacks_registered then
        client.unset_event_callback("setup_command", on_setup_command)
        client.unset_event_callback("paint", painter)
        client.unset_event_callback("round_prestart", resetter)
        callbacks_registered = false
    end

    if dormant_esp_restore ~= nil then
        ui.set(ref.dormantEsp, dormant_esp_restore)
        dormant_esp_restore = nil
    end
end)

    return rawget(_G, 'pasthetic_dormant')
end

return M