local M = {}

function M.start(deps)
    local resource = assert(deps.resource, 'world_enhancer: resource dependency is required')
    local ui = deps.ui or ui
    local client = deps.client or client
    local entity = deps.entity or entity
    local globals = deps.globals or globals
    local renderer = deps.renderer or renderer
    local cvar = deps.cvar or cvar
    local materialsystem = deps.materialsystem or materialsystem
    local bit = deps.bit or bit
-- ============================================
-- WORLD ENHANCER + ADBLOCK RUNTIME
-- ============================================
do
local ffi = require("ffi")
local easing = require("gamesense/easing")

local client_set_cvar, client_get_cvar, client_exec, client_log =
    client.set_cvar, client.get_cvar, client.exec, client.log
local client_delay_call, client_color_log, client_trace_line, client_error_log =
    client.delay_call, client.color_log, client.trace_line, client.error_log
local client_eye_position, client_screen_size, client_userid_to_entindex =
    client.eye_position, client.screen_size, client.userid_to_entindex
local client_find_signature, client_create_interface =
    client.find_signature, client.create_interface
local entity_get_local_player, entity_get_all, entity_set_prop, entity_get_prop =
    entity.get_local_player, entity.get_all, entity.set_prop, entity.get_prop
local entity_get_origin, entity_get_classname, entity_get_game_rules, entity_get_player_weapon =
    entity.get_origin, entity.get_classname, entity.get_game_rules, entity.get_player_weapon
local entity_is_alive = entity.is_alive
local globals_mapname, globals_curtime, globals_tickcount, globals_frametime, globals_framecount =
    globals.mapname, globals.curtime, globals.tickcount, globals.frametime, globals.framecount
local renderer_world_to_screen, renderer_line, renderer_gradient, renderer_text =
    renderer.world_to_screen, renderer.line, renderer.gradient, renderer.text
local materialsystem_find_materials = materialsystem.find_materials
local ffi_cast, ffi_typeof = ffi.cast, ffi.typeof
local math_floor, math_max = math.floor, math.max
local bit_band = bit.band
local string_find, string_lower, string_format = string.find, string.lower, string.format
local table_insert, table_remove, table_sort = table.insert, table.remove, table.sort

ffi.cdef([[
    typedef struct we_con_command_base {
        void *vtable;
        void *next;
        bool registered;
        const char *name;
        const char *help_string;
        int flags;
        void *s_cmd_base;
        void *accessor;
    } we_con_command_base;

    typedef struct {
        float x, y, z;
    } we_Vector;

    typedef void*(*WE_CreateClass)(int, int);
    typedef void*(*WE_CreateEvent)();

    typedef struct {
        WE_CreateClass create_class;
        WE_CreateEvent create_event;
        char* network_name;
        void* recv_table;
        void* next;
        int class_id;
    } WE_ClientClass;



]])

-- reference to menu items
local rw = resource.render_we.world
local rm = resource.render_we.misc

local we_vars = {
    aspect_ratio = { old = client_get_cvar("r_aspectratio") },
    thirdperson  = { old_dist = client_get_cvar("cam_idealdist") },
    skybox = {
        old_skybox = client_get_cvar("sv_skyname"),
        load_name_sky = nil,
    },
    hidden_cvars = {
        v_engine_cvar = client_create_interface("vstdlib.dll", "VEngineCvar007"),
        cvars = {},
        ready = false,
    },
    viewmodel = {
        old_fov = client_get_cvar("viewmodel_fov"),
        old_x   = client_get_cvar("viewmodel_offset_x"),
        old_y   = client_get_cvar("viewmodel_offset_y"),
        old_z   = client_get_cvar("viewmodel_offset_z"),
    },
    effects = {
        bloom_default = nil,
        exposure_min_default = nil,
        exposure_max_default = nil,
        bloom_prev = nil,
        exposure_prev = nil,
    },
    weather = {
        enabled = false,
        style = 0,
        precipitation_class = nil,
        precipitation_entity_idx = nil,
        created = false,
        need_bounds_update = false,
        types = { ["Rain 1"] = 0, ["Rain 2"] = 1 },
    },
    sleeves = { materials = {}, original_alpha = {} },
    custom_scope = {
        scope_overlay = ui.reference("VISUALS", "Effects", "Remove scope overlay"),
        m_alpha = 0,
    },
    bullet_tracers = { to_draw = {} },
    hitbox_data    = { to_draw = {} },
}

-- ── Utils ──
local we_utils = {}

we_utils.reset_bloom = function(tmc)
    if we_vars.effects.bloom_default == -1 then
        entity_set_prop(tmc, "m_bUseCustomBloomScale", 0)
        entity_set_prop(tmc, "m_flCustomBloomScale", 0)
    elseif we_vars.effects.bloom_default then
        entity_set_prop(tmc, "m_bUseCustomBloomScale", 1)
        entity_set_prop(tmc, "m_flCustomBloomScale", we_vars.effects.bloom_default)
    end
end

we_utils.reset_exposure = function(tmc)
    if we_vars.effects.exposure_min_default == -1 then
        entity_set_prop(tmc, "m_bUseCustomAutoExposureMin", 0)
        entity_set_prop(tmc, "m_flCustomAutoExposureMin", 0)
    elseif we_vars.effects.exposure_min_default then
        entity_set_prop(tmc, "m_bUseCustomAutoExposureMin", 1)
        entity_set_prop(tmc, "m_flCustomAutoExposureMin", we_vars.effects.exposure_min_default)
    end
    if we_vars.effects.exposure_max_default == -1 then
        entity_set_prop(tmc, "m_bUseCustomAutoExposureMax", 0)
        entity_set_prop(tmc, "m_flCustomAutoExposureMax", 0)
    elseif we_vars.effects.exposure_max_default then
        entity_set_prop(tmc, "m_bUseCustomAutoExposureMax", 1)
        entity_set_prop(tmc, "m_flCustomAutoExposureMax", we_vars.effects.exposure_max_default)
    end
end

we_utils.get_all_client_classes = function()
    local raw = client_create_interface("client.dll", "VClient018")
    if not raw then return nil end
    local ci = ffi_cast("WE_ClientClass*(__thiscall*)(void*)",
        ffi_cast("void***", raw)[0][8])(raw)
    return ci
end

we_utils.get_client_networkable = function(idx)
    local raw = client_create_interface("client.dll", "VClientEntityList003")
    if not raw then return nil end
    return ffi_cast("void*(__thiscall*)(void*, int)",
        ffi_cast("void***", raw)[0][0])(raw, idx)
end

we_utils.find_precipitation_class = function()
    local cur = we_utils.get_all_client_classes()
    if not cur then return nil end
    while cur and cur ~= ffi.NULL do
        if cur.class_id == 138 then return cur end
        if not cur.next or cur.next == ffi.NULL then break end
        cur = ffi_cast("WE_ClientClass*", cur.next)
    end
    return nil
end

we_utils.create_precipitation = function()
    if we_vars.weather.created then return end
    local lp = entity_get_local_player()
    if not lp then return end
    if not we_vars.weather.precipitation_class then
        we_vars.weather.precipitation_class = we_utils.find_precipitation_class()
        if not we_vars.weather.precipitation_class then return end
    end
    local pc = we_vars.weather.precipitation_class
    if not (pc and pc.create_class) then return end
    local raw_ptr, ok
    for _, idx in ipairs({2047, 2046, 2045, 1024}) do
        ok = pcall(function() raw_ptr = pc.create_class(idx, 0) end)
        if ok and raw_ptr and raw_ptr ~= ffi.NULL then break end
    end
    if not ok or not raw_ptr or raw_ptr == ffi.NULL then return end
    local created_idx
    for i = 2047, 2045, -1 do
        local s, cn = pcall(entity_get_classname, i)
        if s and cn and (cn == "CPrecipitation" or cn == "env_precipitation") then
            created_idx = i; break
        end
    end
    if not created_idx then return end
    we_vars.weather.precipitation_entity_idx = created_idx
    local ok2 = pcall(function()
        local net = we_utils.get_client_networkable(created_idx)
        if not net or net == ffi.NULL then return end
        local nvt = ffi_cast("void***", net)
        ffi_cast("void(__thiscall*)(void*, int)", nvt[0][6])(net, 0)
        ffi_cast("void(__thiscall*)(void*, int)", nvt[0][4])(net, 0)
        entity_set_prop(created_idx, "m_nPrecipType", we_vars.weather.style)
        local cu = ffi_cast("void***(__thiscall*)(void*)", nvt[0][0])(net)
        if cu and cu ~= ffi.NULL then
            local col = ffi_cast("void***(__thiscall*)(void*)", cu[0][3])(cu)
            if col and col ~= ffi.NULL then
                local mn = ffi_cast("we_Vector*(__thiscall*)(void*)", col[0][1])(col)
                local mx = ffi_cast("we_Vector*(__thiscall*)(void*)", col[0][2])(col)
                if mn and mx and mn ~= ffi.NULL and mx ~= ffi.NULL then
                    mn.x, mn.y, mn.z = -2048, -2048, -2048
                    mx.x, mx.y, mx.z =  2048,  2048,  2048
                end
            end
        end
        local px, py, pz = entity_get_origin(lp)
        if px then
            entity_set_prop(created_idx, "m_vecOrigin", px, py, pz + 500)
        else
            entity_set_prop(created_idx, "m_vecOrigin", 0, 0, 500)
        end
        ffi_cast("void(__thiscall*)(void*, int)", nvt[0][5])(net, 0)
        ffi_cast("void(__thiscall*)(void*, int)", nvt[0][7])(net, 0)
    end)
    if ok2 then
        we_vars.weather.created = true
    else
        we_vars.weather.precipitation_entity_idx = nil
    we_vars.weather.precipitation_class = nil
    end
end

we_utils.release_precipitation = function()
    if we_vars.weather.precipitation_entity_idx then
        pcall(function()
            local cn = entity_get_classname(we_vars.weather.precipitation_entity_idx)
            if cn and (cn == "CPrecipitation" or cn == "env_precipitation") then
                entity_set_prop(we_vars.weather.precipitation_entity_idx, "m_nPrecipType", 3)
                entity_set_prop(we_vars.weather.precipitation_entity_idx, "m_bDormant", 1)
                entity_set_prop(we_vars.weather.precipitation_entity_idx, "m_nRenderMode", 10)
                entity_set_prop(we_vars.weather.precipitation_entity_idx, "m_vecOrigin", 999999, 999999, 999999)
            end
        end)
    end
    we_vars.weather.created = false
    we_vars.weather.precipitation_entity_idx = nil
end

we_utils.restore_sleeves = function()
    for i, mat in ipairs(we_vars.sleeves.materials) do
        local a = we_vars.sleeves.original_alpha[i]
        if a then pcall(function() mat:alpha_modulate(a) end) end
    end
end

we_utils.find_sleeve_materials = function()
    if #we_vars.sleeves.materials > 0 then return we_vars.sleeves.materials end
    local ok, mats = pcall(materialsystem_find_materials, "models/weapons/v_models/arms")
    if ok and mats and #mats > 0 then
        local res = {}
        for _, mat in ipairs(mats) do
            local n = mat:get_name()
            if n and string_find(string_lower(n), "sleeve") then
                table_insert(res, mat)
                if not we_vars.sleeves.original_alpha[#res] then
                    we_vars.sleeves.original_alpha[#res] = 255
                end
            end
        end
        we_vars.sleeves.materials = res
    else
        we_vars.sleeves.materials = {}
    end
    return we_vars.sleeves.materials
end

we_utils.apply_sleeves_visibility = function(visible)
    local mats = we_utils.find_sleeve_materials()
    local a = visible and 255 or 0
    for _, mat in ipairs(mats) do
        pcall(function() mat:alpha_modulate(a) end)
    end
end

-- ── Callbacks ──
local we_cb = {}

we_cb.fog_override = function()
    if not rw.fog.override:get() then
        client_set_cvar("fog_override", "0"); return
    end
    client_set_cvar("fog_override", "1")
    local r, g, b = rw.fog.color:get()
    client_set_cvar("fog_color", string_format("%d %d %d", r, g, b))
    client_set_cvar("fog_start",       rw.fog.start:get())
    client_set_cvar("fog_end",         rw.fog.end_:get())
    client_set_cvar("fog_maxdensity",  rw.fog.density:get() / 100)
end

we_cb.sunset_override = function()
    if not rw.sunset.override:get() then
        client_set_cvar("cl_csm_rot_override", 0); return
    end
    client_set_cvar("cl_csm_rot_override", 1)
    client_set_cvar("cl_csm_rot_x", rw.sunset.azimuth:get())
    client_set_cvar("cl_csm_rot_y", rw.sunset.elevation:get())
end

we_cb.skybox_override = function()
    if not rw.skybox.override then return end
    local r, g, b, a = 255, 255, 255, 255
    if entity_get_local_player() ~= nil then
        if not rw.skybox.override:get() then
            if we_vars.skybox.load_name_sky then
                we_vars.skybox.load_name_sky(we_vars.skybox.old_skybox)
            end
            local mats = materialsystem_find_materials("skybox/")
            for i = 1, #mats do mats[i]:color_modulate(r,g,b); mats[i]:alpha_modulate(a) end
            return
        end
        local skybox = rw.skybox.list:get()
        if we_vars.skybox.load_name_sky then
            we_vars.skybox.load_name_sky(skybox)
        end
        local mats = materialsystem_find_materials("skybox/")
        r, g, b, a = rw.skybox.color:get()
        for i = 1, #mats do mats[i]:color_modulate(r,g,b); mats[i]:alpha_modulate(a) end
    end
    client_set_cvar("r_3dsky", rw.skybox.remove_3d_sky:get() and 0 or 1)
end

we_cb.effects_update = function()
    if rw.model_ambient.enable:get() then
        local v = rw.model_ambient.brightness:get() * 0.05
        if cvar.r_modelAmbientMin:get_float() ~= v then
            cvar.r_modelAmbientMin:set_raw_float(v)
        end
    else
        cvar.r_modelAmbientMin:set_raw_float(0)
    end

    local tmcs = entity_get_all("CEnvTonemapController")
    for i = 1, #tmcs do
        local tmc = tmcs[i]
        -- bloom
        if rw.bloom.enable:get() then
            local bloom = rw.bloom.scale:get() * 0.01
            if we_vars.effects.bloom_default == nil then
                if entity_get_prop(tmc, "m_bUseCustomBloomScale") == 1 then
                    we_vars.effects.bloom_default = entity_get_prop(tmc, "m_flCustomBloomScale")
                else
                    we_vars.effects.bloom_default = -1
                end
            end
            entity_set_prop(tmc, "m_bUseCustomBloomScale", 1)
            entity_set_prop(tmc, "m_flCustomBloomScale", bloom)
            we_vars.effects.bloom_prev = bloom
        else
            if we_vars.effects.bloom_prev ~= nil and we_vars.effects.bloom_default ~= nil then
                we_utils.reset_bloom(tmc)
                we_vars.effects.bloom_prev = nil
            end
        end
        -- exposure
        if rw.exposure.enable:get() then
            local exp = math_max(0.0, rw.exposure.value:get() * 0.001)
            if we_vars.effects.exposure_min_default == nil then
                if entity_get_prop(tmc, "m_bUseCustomAutoExposureMin") == 1 then
                    we_vars.effects.exposure_min_default = entity_get_prop(tmc, "m_flCustomAutoExposureMin")
                else
                    we_vars.effects.exposure_min_default = -1
                end
                if entity_get_prop(tmc, "m_bUseCustomAutoExposureMax") == 1 then
                    we_vars.effects.exposure_max_default = entity_get_prop(tmc, "m_flCustomAutoExposureMax")
                else
                    we_vars.effects.exposure_max_default = -1
                end
            end
            entity_set_prop(tmc, "m_bUseCustomAutoExposureMin", 1)
            entity_set_prop(tmc, "m_bUseCustomAutoExposureMax", 1)
            entity_set_prop(tmc, "m_flCustomAutoExposureMin", exp)
            entity_set_prop(tmc, "m_flCustomAutoExposureMax", exp)
            we_vars.effects.exposure_prev = exp
        else
            if we_vars.effects.exposure_prev ~= nil and we_vars.effects.exposure_min_default ~= nil then
                we_utils.reset_exposure(tmc)
                we_vars.effects.exposure_prev = nil
            end
        end
    end
end

we_cb.update_weather = function()
    local style_name = rw.weather.style:get()
    we_vars.weather.style = we_vars.weather.types[style_name] or 0

    if not rw.weather.enable:get() then
        we_utils.release_precipitation()
        we_vars.weather.created = false
        we_vars.weather.precipitation_entity_idx = nil
    else
        if we_vars.weather.precipitation_entity_idx then
            pcall(function()
                local cn = entity_get_classname(we_vars.weather.precipitation_entity_idx)
                if cn and (cn == "CPrecipitation" or cn == "env_precipitation") then
                    entity_set_prop(we_vars.weather.precipitation_entity_idx, "m_nPrecipType", we_vars.weather.style)
                else
                    we_vars.weather.created = false
                    we_vars.weather.precipitation_entity_idx = nil
                end
            end)
        end
    end

    client_set_cvar("r_rainradius", rw.weather.radius:get())
    client_set_cvar("r_rainwidth",  rw.weather.width:get() / 100)
    client_set_cvar("r_rainalpha",  rw.weather.modulate:get() / 100)

    local is_snow = we_vars.weather.style == 1
    if is_snow then
        client_set_cvar("r_SnowParticles", rw.weather.snow_particles:get())
        client_set_cvar("r_SnowFallSpeed", rw.weather.snow_fall_speed:get() / 10)
        client_set_cvar("r_SnowWindScale", rw.weather.snow_wind_scale:get() / 10000)
        client_set_cvar("r_SnowEnable", "1")
    else
        client_set_cvar("r_SnowEnable", "0")
    end

    if rw.weather.wind_enable:get() then
        client_set_cvar("cl_winddir",   rw.weather.wind_direction:get())
        client_set_cvar("cl_windspeed", rw.weather.wind_speed:get())
    else
        client_set_cvar("cl_winddir",   "0")
        client_set_cvar("cl_windspeed", "0")
    end
end

we_cb.draw_weather = function()
    local mapname = globals_mapname()
    if not mapname or mapname == "" then
        if we_vars.weather.created then
            we_utils.release_precipitation()
            we_vars.weather.created = false
            we_vars.weather.precipitation_entity_idx = nil
        end
        return
    end
    if not rw.weather.enable:get() then
        if we_vars.weather.created then we_utils.release_precipitation() end
        return
    end
    if not entity_get_local_player() then return end
    if we_vars.weather.precipitation_entity_idx then
        local ok, cn = pcall(entity_get_classname, we_vars.weather.precipitation_entity_idx)
        if not ok or not cn or (cn ~= "CPrecipitation" and cn ~= "env_precipitation") then
            we_vars.weather.created = false
            we_vars.weather.precipitation_entity_idx = nil
        end
    end
    if not we_vars.weather.created then
        we_utils.create_precipitation()
    end
end

we_cb.thirdperson = function()
    if not rm.thirdperson.override:get() then
        client_set_cvar("cam_idealdist", we_vars.thirdperson.old_dist); return
    end
    client_set_cvar("cam_idealdist", rm.thirdperson.distance:get())
end

    we_cb.aspect_ratio = function()
    if not rm.aspect_ratio.override:get() then
        client_set_cvar("r_aspectratio", we_vars.aspect_ratio.old or 0)
        return
    end
    local ar_raw = rm.aspect_ratio.value:get() * 0.01
    local sw, sh = client_screen_size()
    local val = (sw * (2 - ar_raw)) / sh
    client_set_cvar("r_aspectratio", tostring(val))
end

we_cb.viewmodel_in_scope = function()
    client_set_cvar("fov_cs_debug", rm.viewmodel_in_scope:get() and 90 or 0)
end

we_cb.viewmodel_changer = function()
    if not rm.viewmodel_changer.override:get() then
        client_set_cvar("viewmodel_fov",      we_vars.viewmodel.old_fov)
        client_set_cvar("viewmodel_offset_x", we_vars.viewmodel.old_x)
        client_set_cvar("viewmodel_offset_y", we_vars.viewmodel.old_y)
        client_set_cvar("viewmodel_offset_z", we_vars.viewmodel.old_z)
        return
    end
    client_set_cvar("viewmodel_fov",      rm.viewmodel_changer.fov:get())
    client_set_cvar("viewmodel_offset_x", rm.viewmodel_changer.x:get() / 10)
    client_set_cvar("viewmodel_offset_y", rm.viewmodel_changer.y:get() / 10)
    client_set_cvar("viewmodel_offset_z", rm.viewmodel_changer.z:get() / 10)
end

we_cb.remove_sleeves = function()
    if not rm.remove_sleeves:get() then
        we_utils.restore_sleeves(); return
    end
    we_utils.apply_sleeves_visibility(false)
end

we_cb.draw_scope_ui = function()
    if not rm.custom_scope.enable:get() then return end
    ui.set(we_vars.custom_scope.scope_overlay, true)
end

we_cb.draw_scope = function()
    if not rm.custom_scope.enable:get() then
        ui.set(we_vars.custom_scope.scope_overlay, true); return
    end
    ui.set(we_vars.custom_scope.scope_overlay, false)

    local width, height = client_screen_size()
    local offset   = rm.custom_scope.offset:get()     * height / 1080
    local init_pos = rm.custom_scope.scope_size:get() * height / 1080
    local speed    = rm.custom_scope.fade_time:get()
    local r, g, b, a = rm.custom_scope.color:get()

    local me = entity_get_local_player()
    if not me then return end
    local wpn = entity_get_player_weapon(me)
    if not wpn then return end

    local scope_level  = entity_get_prop(wpn, "m_zoomLevel")
    local scoped       = entity_get_prop(me,  "m_bIsScoped") == 1
    local resume_zoom  = entity_get_prop(me,  "m_bResumeZoom") == 1
    local is_valid     = entity_is_alive(me) and wpn ~= nil and scope_level ~= nil
    local act          = is_valid and scope_level > 0 and scoped and not resume_zoom

    local FT    = speed > 3 and globals_frametime() * speed or 1
    local alpha = easing.linear(we_vars.custom_scope.m_alpha, 0, 1, 1)

    renderer_gradient(width/2 - init_pos + 2, height/2,    init_pos - offset, 1, r,g,b,0,         r,g,b, alpha*a, true)
    renderer_gradient(width/2 + offset,        height/2,    init_pos - offset, 1, r,g,b, alpha*a,  r,g,b, 0,       true)
    renderer_gradient(width/2,  height/2 - init_pos + 2, 1, init_pos - offset, r,g,b,0,         r,g,b, alpha*a, false)
    renderer_gradient(width/2,  height/2 + offset,        1, init_pos - offset, r,g,b, alpha*a,  r,g,b, 0,       false)

    we_vars.custom_scope.m_alpha = math_max(0, math_floor(
        (we_vars.custom_scope.m_alpha + (act and FT or -FT)) * 1000) / 1000)
    if we_vars.custom_scope.m_alpha > 1 then we_vars.custom_scope.m_alpha = 1 end
end

we_cb.bullet_tracers_record = function(e)
    if not rw.bullet_tracers.enable:get() then return end
    if client_userid_to_entindex(e.userid) ~= entity_get_local_player() then return end
    local x, y, z = client_eye_position()
    we_vars.bullet_tracers.to_draw[globals_tickcount()] = {
        x, y, z, e.x, e.y, e.z, globals_curtime() + rw.bullet_tracers.timer:get()
    }
end

we_cb.bullet_tracers_draw = function()
    if not rw.bullet_tracers.enable:get() then return end
    local now = globals_curtime()
    for tick, pos in pairs(we_vars.bullet_tracers.to_draw) do
        local end_t = pos[7]
        if now <= end_t then
            local fade_t = 0.3
            local remaining = end_t - now
            local alpha = remaining < fade_t and math_floor(remaining/fade_t * 255) or 255
            local r, g, b = rw.bullet_tracers.color:get()
            local x1, y1 = renderer_world_to_screen(pos[1], pos[2], pos[3])
            local x2, y2 = renderer_world_to_screen(pos[4], pos[5], pos[6])
            if x1 and x2 then renderer_line(x1,y1,x2,y2,r,g,b,alpha) end
        end
    end
end

we_cb.hitboxes_record = function(e)
    if not rw.hitbox_on_hit.enable:get() then return end
    if e.interpolated or e.extrapolated then return end
    local r, g, b = rw.hitbox_on_hit.color:get()
    we_vars.hitbox_data.to_draw[e.id] = {
        target = e.target, tick = e.tick,
        end_time = globals_curtime() + rw.hitbox_on_hit.timer:get(),
        r=r, g=g, b=b,
    }
end

we_cb.hitboxes_draw = function()
    if not rw.hitbox_on_hit.enable:get() then
        we_vars.hitbox_data.to_draw = {}; return
    end
    local now = globals_curtime()
    local cur_tick = globals_framecount()
    local fade_t = 0.3
    local to_remove = {}
    for id, data in pairs(we_vars.hitbox_data.to_draw) do
        if now > data.end_time then
            table_insert(to_remove, id)
        else
            local remaining = data.end_time - now
            local alpha = remaining < fade_t and math_floor(remaining/fade_t * 30) or 30
            client.draw_hitboxes(data.target, 0.1, 19, data.r, data.g, data.b, alpha, cur_tick)
        end
    end
    for _, id in ipairs(to_remove) do we_vars.hitbox_data.to_draw[id] = nil end
end

local function we_apply_current_settings()
    pcall(we_cb.fog_override)
    pcall(we_cb.sunset_override)
    pcall(we_cb.skybox_override)
    pcall(we_cb.effects_update)
    pcall(we_cb.update_weather)
    pcall(we_cb.thirdperson)
    pcall(we_cb.aspect_ratio)
    pcall(we_cb.viewmodel_in_scope)
    pcall(we_cb.viewmodel_changer)
    pcall(we_cb.remove_sleeves)

    if rw.weather.enable:get() then
        we_vars.weather.need_bounds_update = true
    end
end

-- ── Setup ──
local function we_setup()
    local load_sky_addr = client_find_signature("engine.dll",
        "\x55\x8B\xEC\x81\xEC\xCC\xCC\xCC\xCC\x56\x57\x8B\xF9\xC7\x45") or
        error("signature for load_name_sky is outdated")
    we_vars.skybox.load_name_sky = ffi_cast(
        ffi_typeof("void(__fastcall*)(const char*)"), load_sky_addr)

    -- collect hidden cvars
    local ccb_ptr = ffi_cast("we_con_command_base ***",
        ffi_cast("uint32_t", we_vars.hidden_cvars.v_engine_cvar) + 0x34)[0][0]
    local cmd = ffi_cast("we_con_command_base *", ccb_ptr.next)
    while ffi_cast("uint32_t", cmd) ~= 0 do
        if bit_band(cmd.flags, 18) then
            table_insert(we_vars.hidden_cvars.cvars, cmd)
        end
        cmd = ffi_cast("we_con_command_base *", cmd.next)
    end
    we_vars.hidden_cvars.ready = true

    -- unlock cvars button
    rm.unlock_cvars:set_callback(function()
        if not we_vars.hidden_cvars.ready then return end
        for _, cv in ipairs(we_vars.hidden_cvars.cvars) do
            cv.flags = bit_band(cv.flags, bit.bnot(18))
        end
        client_log("Unlocked hidden ConVars!")
    end)

    -- fog callbacks
    rw.fog.override:set_callback(we_cb.fog_override)
    rw.fog.color:set_callback(we_cb.fog_override)
    rw.fog.start:set_callback(we_cb.fog_override)
    rw.fog.end_:set_callback(we_cb.fog_override)
    rw.fog.density:set_callback(we_cb.fog_override)

    -- sunset callbacks
    rw.sunset.override:set_callback(we_cb.sunset_override)
    rw.sunset.azimuth:set_callback(we_cb.sunset_override)
    rw.sunset.elevation:set_callback(we_cb.sunset_override)

    -- skybox callbacks
    rw.skybox.override:set_callback(we_cb.skybox_override)
    rw.skybox.color:set_callback(we_cb.skybox_override)
    rw.skybox.list:set_callback(we_cb.skybox_override)
    rw.skybox.remove_3d_sky:set_callback(we_cb.skybox_override)

    -- bloom/exposure/model_ambient
    rw.bloom.enable:set_callback(we_cb.effects_update)
    rw.bloom.scale:set_callback(we_cb.effects_update)
    rw.exposure.enable:set_callback(we_cb.effects_update)
    rw.exposure.value:set_callback(we_cb.effects_update)
    rw.model_ambient.enable:set_callback(we_cb.effects_update)
    rw.model_ambient.brightness:set_callback(we_cb.effects_update)

    -- weather callbacks
    rw.weather.enable:set_callback(function()
        we_cb.update_weather()
        if rw.weather.enable:get() then we_vars.weather.need_bounds_update = true end
    end)
    rw.weather.style:set_callback(we_cb.update_weather)
    rw.weather.radius:set_callback(we_cb.update_weather)
    rw.weather.width:set_callback(we_cb.update_weather)
    rw.weather.modulate:set_callback(we_cb.update_weather)
    rw.weather.wind_enable:set_callback(we_cb.update_weather)
    rw.weather.wind_direction:set_callback(we_cb.update_weather)
    rw.weather.wind_speed:set_callback(we_cb.update_weather)

    -- misc callbacks
    rm.thirdperson.override:set_callback(we_cb.thirdperson)
    rm.thirdperson.distance:set_callback(we_cb.thirdperson)
    rm.aspect_ratio.override:set_callback(we_cb.aspect_ratio)
    rm.aspect_ratio.value:set_callback(we_cb.aspect_ratio)
    rm.viewmodel_in_scope:set_callback(we_cb.viewmodel_in_scope)
    rm.viewmodel_changer.override:set_callback(we_cb.viewmodel_changer)
    rm.viewmodel_changer.fov:set_callback(we_cb.viewmodel_changer)
    rm.viewmodel_changer.x:set_callback(we_cb.viewmodel_changer)
    rm.viewmodel_changer.y:set_callback(we_cb.viewmodel_changer)
    rm.viewmodel_changer.z:set_callback(we_cb.viewmodel_changer)
    rm.remove_sleeves:set_callback(we_cb.remove_sleeves)

    rm.custom_scope.enable:set_callback(function()
        if rm.custom_scope.enable:get() then
            client.set_event_callback("paint_ui", we_cb.draw_scope_ui)
            client.set_event_callback("paint",    we_cb.draw_scope)
        else
            we_vars.custom_scope.m_alpha = 0
            client.unset_event_callback("paint_ui", we_cb.draw_scope_ui)
            client.unset_event_callback("paint",    we_cb.draw_scope)
            ui.set(we_vars.custom_scope.scope_overlay, false)
        end
    end)

    -- apply settings that may have been loaded before World Enhancer callbacks existed
    we_apply_current_settings()
end

local ok, err = pcall(we_setup)
if not ok then
    client.error_log("[Pasthetic] World Enhancer setup failed: " .. tostring(err))
end

-- ── Event callbacks ──
client.set_event_callback("paint", function()
    we_cb.effects_update()
    we_cb.draw_weather()
    we_cb.bullet_tracers_draw()
    we_cb.draw_scope()
    we_cb.hitboxes_draw()
end)

client.set_event_callback("paint_ui", we_cb.draw_scope_ui)

client.set_event_callback("player_connect_full", function(event)
    if client_userid_to_entindex(event.userid) == entity_get_local_player() then
        we_vars.skybox.old_skybox = client_get_cvar("sv_skyname")
        we_cb.skybox_override()
    end
    if globals_mapname() == nil then
        we_vars.effects.bloom_default        = nil
        we_vars.effects.exposure_min_default = nil
        we_vars.effects.exposure_max_default = nil
        we_vars.effects.bloom_prev           = nil
        we_vars.effects.exposure_prev        = nil
    end
end)

client.set_event_callback("cs_intermission", function()
    we_utils.release_precipitation()
end)

client.set_event_callback("player_disconnect", function(event)
    if client_userid_to_entindex(event.userid) == entity_get_local_player() then
        we_utils.release_precipitation()
        we_vars.weather.created = false
        we_vars.weather.precipitation_entity_idx = nil
        we_vars.weather.precipitation_class = nil
    end
    we_vars.bullet_tracers.to_draw = {}
    we_vars.hitbox_data.to_draw    = {}
end)

client.set_event_callback("level_init", function()
    we_cb.fog_override()
    we_cb.sunset_override()
    we_utils.release_precipitation()
    we_vars.weather.created = false
    we_vars.weather.precipitation_entity_idx = nil
    we_vars.weather.precipitation_class = nil

    if rw.weather.enable:get() then we_cb.update_weather() end

    we_vars.bullet_tracers.to_draw = {}
    we_vars.hitbox_data.to_draw    = {}

end)

client.set_event_callback("round_prestart", function()
    we_vars.bullet_tracers.to_draw    = {}
    we_vars.hitbox_data.to_draw       = {}
    we_vars.weather.need_bounds_update = true
end)

client.set_event_callback("game_newmap", function()
    if globals_mapname() == nil then
        we_vars.effects.bloom_default        = nil
        we_vars.effects.exposure_min_default = nil
        we_vars.effects.exposure_max_default = nil
        we_vars.effects.bloom_prev           = nil
        we_vars.effects.exposure_prev        = nil
    end
    we_cb.fog_override()
    we_cb.sunset_override()
    we_utils.release_precipitation()
    we_vars.weather.created = false
    we_vars.weather.precipitation_entity_idx = nil
    we_vars.weather.precipitation_class = nil
    we_vars.bullet_tracers.to_draw = {}
    we_vars.hitbox_data.to_draw    = {}

end)

client.set_event_callback("shutdown", function()
    -- restore fog
    client_set_cvar("fog_override", 0)
    client_set_cvar("cl_csm_rot_override", 0)
    -- restore skybox
    if entity_get_local_player() then
        if we_vars.skybox.load_name_sky then
            we_vars.skybox.load_name_sky(we_vars.skybox.old_skybox)
        end
        local mats = materialsystem_find_materials("skybox/")
        for i=1,#mats do mats[i]:color_modulate(255,255,255); mats[i]:alpha_modulate(255) end
    end
    -- restore bloom/exposure
    local tmcs = entity_get_all("CEnvTonemapController")
    for i=1,#tmcs do
        local tmc = tmcs[i]
        if we_vars.effects.bloom_default ~= nil then we_utils.reset_bloom(tmc) end
        if we_vars.effects.exposure_min_default ~= nil then we_utils.reset_exposure(tmc) end
    end
    cvar.r_modelAmbientMin:set_raw_float(0)
    client_set_cvar("mat_ambient_light_r", 0)
    client_set_cvar("mat_ambient_light_g", 0)
    client_set_cvar("mat_ambient_light_b", 0)
    we_utils.release_precipitation()
    client_set_cvar("r_SnowEnable", "1")
    client_set_cvar("r_SnowParticles", "300")
    client_set_cvar("r_SnowFallSpeed", "1.5")
    client_set_cvar("r_SnowWindScale", "0.0035")
    client_set_cvar("cl_winddir", "0")
    client_set_cvar("cl_windspeed", "0")
    -- restore misc
    client_set_cvar("cam_idealdist",    we_vars.thirdperson.old_dist)
    client_set_cvar("fov_cs_debug",     0)
    client_set_cvar("r_aspectratio",    0)
    client_set_cvar("viewmodel_fov",    we_vars.viewmodel.old_fov)
    client_set_cvar("viewmodel_offset_x", we_vars.viewmodel.old_x)
    client_set_cvar("viewmodel_offset_y", we_vars.viewmodel.old_y)
    client_set_cvar("viewmodel_offset_z", we_vars.viewmodel.old_z)
    client_set_cvar("con_filter_enable", 0)
    client_set_cvar("con_filter_text",   "")
    we_utils.restore_sleeves()
    ui.set(we_vars.custom_scope.scope_overlay, true)
end)

client.set_event_callback("bullet_impact", function(e)
    we_cb.bullet_tracers_record(e)
end)

client.set_event_callback("aim_fire", function(e)
    we_cb.hitboxes_record(e)
end)

end -- end do block








    return true
end

function M.health()
    return true
end

return M