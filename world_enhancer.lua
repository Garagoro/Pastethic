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
    local vtable_thunk = deps.vtable_thunk or vtable_thunk
-- ============================================
-- WORLD ENHANCER + ADBLOCK RUNTIME
-- ============================================
do
local ffi = require("ffi")
local easing = require("gamesense/easing")

local client_set_cvar, client_get_cvar, client_exec, client_log, client_key_state =
    client.set_cvar, client.get_cvar, client.exec, client.log, client.key_state
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
local renderer_world_to_screen, renderer_line, renderer_gradient, renderer_text, renderer_rectangle =
    renderer.world_to_screen, renderer.line, renderer.gradient, renderer.text, renderer.rectangle
local materialsystem_find_materials = materialsystem.find_materials
local ffi_cast, ffi_typeof = ffi.cast, ffi.typeof
local math_floor, math_max, math_min, math_sqrt = math.floor, math.max, math.min, math.sqrt
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

    typedef struct {
        float x, y, z;
    } we_attachment_vec3;

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

    typedef bool(__thiscall *WE_IsButtonDown)(void*, int);
    typedef int(__thiscall *WE_GetInputTick)(void*, int);
    typedef int(__thiscall *WE_GetAnalog)(void*, int);


]])

-- reference to menu items
local rw = resource.render_we.world
local rm = resource.render_we.misc
local vm_editor_thirdperson_ref = { ui.reference("VISUALS", "Effects", "Force third person (alive)") }

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
        old_bob_lower = client_get_cvar("cl_bob_lower_amt"),
        old_bob_lat = client_get_cvar("cl_bobamt_lat"),
        old_bob_vert = client_get_cvar("cl_bobamt_vert"),
        old_bob_up = client_get_cvar("cl_bobup"),
        old_use_new_headbob = client_get_cvar("cl_use_new_headbob"),
        old_headbob_land_dip = client_get_cvar("cl_headbob_land_dip_amt"),
        old_wpn_sway_scale = client_get_cvar("cl_wpn_sway_scale"),
        old_wpn_sway_interp = client_get_cvar("cl_wpn_sway_interp"),
        old_viewmodel_recoil = client_get_cvar("viewmodel_recoil"),
        old_gun_lower_angle = client_get_cvar("cl_gunlowerangle"),
        old_shift_left = client_get_cvar("cl_viewmodel_shift_left_amt"),
        old_shift_right = client_get_cvar("cl_viewmodel_shift_right_amt"),
        fov = 54,
        x = 25,
        y = -20,
        z = -20,
        scope_fov = nil,
        scope_x = nil,
        scope_y = nil,
        scope_z = nil,
        scope_customized = false,
        current_fov = nil,
        current_x = nil,
        current_y = nil,
        current_z = nil,
        active_profile = nil,
    },
    viewmodel_editor = {
        w = 145,
        h = 55,
        dragging = false,
        drag_start_mouse_x = nil,
        drag_start_mouse_y = nil,
        drag_grab_to_muzzle_x = nil,
        drag_grab_to_muzzle_y = nil,
        last_x = nil,
        last_y = nil,
        wheel_up_prev = false,
        wheel_down_prev = false,
        wheel_up_tick = 0,
        wheel_down_tick = 0,
        wheel_next_tick = 0,
        inputsystem = nil,
        is_button_down = nil,
        get_button_pressed_tick = nil,
        get_analog_delta = nil,
        input_ready = nil,
        attachment_ready = nil,
        entity_list = nil,
        get_client_entity = nil,
        get_attachment = nil,
        get_muzzle_attachment = nil,
        block_input_until = 0,
        suspend_until = 0,
        syncing_storage = false,
        storage_load_token = 0,
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

local VM_EDITOR_WHEEL_UP = 112
local VM_EDITOR_WHEEL_DOWN = 113
local VM_EDITOR_MOUSE_WHEEL = 3
local VM_EDITOR_X_MIN, VM_EDITOR_X_MAX = -300, 300
local VM_EDITOR_Y_MIN, VM_EDITOR_Y_MAX = -300, 300
local VM_EDITOR_Z_MIN, VM_EDITOR_Z_MAX = -300, 300
local VM_EDITOR_FOV_MIN, VM_EDITOR_FOV_MAX = -60, 100

local function vm_editor_clamp(value, min_value, max_value)
    return math_max(min_value, math_min(max_value, value))
end

local function vm_editor_round(value)
    return math_floor(value + 0.5)
end

local function vm_editor_set_slider(item, value, min_value, max_value)
    item:set(vm_editor_clamp(vm_editor_round(value), min_value, max_value))
end

local vm_editor_apply_values, vm_editor_is_scoped

local function vm_editor_sync_storage()
    local storage = rm.viewmodel_changer.storage
    local viewmodel = we_vars.viewmodel
    local editor = we_vars.viewmodel_editor

    if storage == nil or editor.syncing_storage then
        return
    end

    local function write(item, value)
        if item ~= nil then
            item:set(value ~= nil and tostring(vm_editor_round(value)) or "")
        end
    end

    editor.syncing_storage = true
    write(storage.fov, viewmodel.fov)
    write(storage.x, viewmodel.x)
    write(storage.y, viewmodel.y)
    write(storage.z, viewmodel.z)
    if viewmodel.scope_customized then
        write(storage.scope_fov, viewmodel.scope_fov)
        write(storage.scope_x, viewmodel.scope_x)
        write(storage.scope_y, viewmodel.scope_y)
        write(storage.scope_z, viewmodel.scope_z)
        write(storage.scope_custom, 1)
    else
        write(storage.scope_fov, nil)
        write(storage.scope_x, nil)
        write(storage.scope_y, nil)
        write(storage.scope_z, nil)
        write(storage.scope_custom, nil)
    end
    editor.syncing_storage = false
end

local function vm_editor_load_storage()
    local storage = rm.viewmodel_changer.storage
    local viewmodel = we_vars.viewmodel
    local editor = we_vars.viewmodel_editor

    if storage == nil or editor.syncing_storage then
        return
    end

    local loaded = false
    local function read(name, min_value, max_value)
        local item = storage[name]
        local value = item ~= nil and tonumber(item:get()) or nil

        if value ~= nil then
            viewmodel[name] = vm_editor_clamp(value, min_value, max_value)
            loaded = true
        end
    end

    read("fov", VM_EDITOR_FOV_MIN, VM_EDITOR_FOV_MAX)
    read("x", VM_EDITOR_X_MIN, VM_EDITOR_X_MAX)
    read("y", VM_EDITOR_Y_MIN, VM_EDITOR_Y_MAX)
    read("z", VM_EDITOR_Z_MIN, VM_EDITOR_Z_MAX)
    local has_legacy_scope = (
        (storage.scope_fov ~= nil and tonumber(storage.scope_fov:get()) ~= nil)
        or (storage.scope_x ~= nil and tonumber(storage.scope_x:get()) ~= nil)
        or (storage.scope_y ~= nil and tonumber(storage.scope_y:get()) ~= nil)
        or (storage.scope_z ~= nil and tonumber(storage.scope_z:get()) ~= nil)
    )
    viewmodel.scope_customized = (storage.scope_custom ~= nil and storage.scope_custom:get() == "1")
        or has_legacy_scope
    if viewmodel.scope_customized then
        read("scope_fov", VM_EDITOR_FOV_MIN, VM_EDITOR_FOV_MAX)
        read("scope_x", VM_EDITOR_X_MIN, VM_EDITOR_X_MAX)
        read("scope_y", VM_EDITOR_Y_MIN, VM_EDITOR_Y_MAX)
        read("scope_z", VM_EDITOR_Z_MIN, VM_EDITOR_Z_MAX)
    else
        viewmodel.scope_fov = nil
        viewmodel.scope_x = nil
        viewmodel.scope_y = nil
        viewmodel.scope_z = nil
    end

    if not loaded then
        vm_editor_sync_storage()
        return
    end

    viewmodel.current_fov = nil
    viewmodel.current_x = nil
    viewmodel.current_y = nil
    viewmodel.current_z = nil
    viewmodel.active_profile = nil

    if rm.viewmodel_changer.override:get() then
        vm_editor_apply_values(vm_editor_is_scoped(), true)
    end
end

local function vm_editor_schedule_load_storage()
    local editor = we_vars.viewmodel_editor

    if editor.syncing_storage then
        return
    end

    editor.storage_load_token = (editor.storage_load_token or 0) + 1
    local token = editor.storage_load_token

    client_delay_call(0, function()
        if token ~= we_vars.viewmodel_editor.storage_load_token then
            return
        end

        vm_editor_load_storage()
    end)
end

local function vm_editor_set_value(key, value, min_value, max_value, mark_scope_customized)
    if mark_scope_customized then
        we_vars.viewmodel.scope_customized = true
    end

    we_vars.viewmodel[key] = vm_editor_clamp(value, min_value, max_value)
    vm_editor_sync_storage()
end

local function vm_editor_ensure_scope_values()
    local viewmodel = we_vars.viewmodel

    if not viewmodel.scope_customized then
        viewmodel.scope_fov = vm_editor_clamp(viewmodel.fov or 54, VM_EDITOR_FOV_MIN, VM_EDITOR_FOV_MAX)
        viewmodel.scope_x = vm_editor_clamp((viewmodel.x or 0) + 20, VM_EDITOR_X_MIN, VM_EDITOR_X_MAX)
        viewmodel.scope_y = vm_editor_clamp(viewmodel.y or 0, VM_EDITOR_Y_MIN, VM_EDITOR_Y_MAX)
        viewmodel.scope_z = vm_editor_clamp((viewmodel.z or 0) + 20, VM_EDITOR_Z_MIN, VM_EDITOR_Z_MAX)
        return
    end

    local changed = false

    if viewmodel.scope_x == nil then
        viewmodel.scope_x = vm_editor_clamp((viewmodel.x or 0) + 20, VM_EDITOR_X_MIN, VM_EDITOR_X_MAX)
        changed = true
    end

    if viewmodel.scope_y == nil then
        viewmodel.scope_y = vm_editor_clamp(
            viewmodel.y or 0,
            VM_EDITOR_Y_MIN,
            VM_EDITOR_Y_MAX
        )
        changed = true
    end

    if viewmodel.scope_z == nil then
        viewmodel.scope_z = vm_editor_clamp(
            (viewmodel.z or 0) + 20,
            VM_EDITOR_Z_MIN,
            VM_EDITOR_Z_MAX
        )
        changed = true
    end

    if viewmodel.scope_fov == nil then
        viewmodel.scope_fov = vm_editor_clamp(
            viewmodel.fov or 54,
            VM_EDITOR_FOV_MIN,
            VM_EDITOR_FOV_MAX
        )
        changed = true
    end

    if changed then
        vm_editor_sync_storage()
    end
end

local function vm_editor_use_scope_values(scoped)
    return scoped and rm.viewmodel_changer.scope_hide:get()
end

local function vm_editor_get_values(scoped)
    local viewmodel = we_vars.viewmodel

    if vm_editor_use_scope_values(scoped) then
        vm_editor_ensure_scope_values()

        return {
            fov = viewmodel.scope_fov,
            x = viewmodel.scope_x,
            y = viewmodel.scope_y,
            z = viewmodel.scope_z,
            label = 'S'
        }
    end

    return {
        fov = viewmodel.fov,
        x = viewmodel.x,
        y = viewmodel.y,
        z = viewmodel.z,
        label = ''
    }
end

local function vm_editor_get_profile(scoped)
    return vm_editor_use_scope_values(scoped) and "scope" or "normal"
end

local function vm_editor_set_cvar(name, value)
    local cv = cvar and cvar[name]
    if cv ~= nil then
        if cv.set_raw_float ~= nil then
            cv:set_raw_float(value)
            return
        end

        if cv.set_float ~= nil then
            cv:set_float(value)
            return
        end
    end

    client_set_cvar(name, value)
end

local function vm_editor_restore_cvar(name, value, fallback)
    vm_editor_set_cvar(name, tonumber(value) or fallback)
end

local function vm_editor_apply_hand_movement()
    local viewmodel = we_vars.viewmodel
    local amount = rm.viewmodel_changer.override:get() and rm.viewmodel_changer.hand_move:get() or 100

    vm_editor_restore_cvar("cl_bob_lower_amt", viewmodel.old_bob_lower, 21)
    vm_editor_restore_cvar("cl_bobamt_lat", viewmodel.old_bob_lat, 0.4)
    vm_editor_restore_cvar("cl_bobamt_vert", viewmodel.old_bob_vert, 0.25)
    vm_editor_restore_cvar("cl_bobup", viewmodel.old_bob_up, 0.5)
    vm_editor_restore_cvar("cl_use_new_headbob", viewmodel.old_use_new_headbob, 1)
    vm_editor_restore_cvar("cl_headbob_land_dip_amt", viewmodel.old_headbob_land_dip, 4)
    vm_editor_restore_cvar("cl_wpn_sway_scale", viewmodel.old_wpn_sway_scale, 1.6)
    vm_editor_restore_cvar("cl_wpn_sway_interp", viewmodel.old_wpn_sway_interp, 0.1)
    vm_editor_restore_cvar("viewmodel_recoil", viewmodel.old_viewmodel_recoil, 1)
    vm_editor_restore_cvar("cl_gunlowerangle", viewmodel.old_gun_lower_angle, 2)
    vm_editor_restore_cvar("cl_viewmodel_shift_left_amt", viewmodel.old_shift_left, 1.5)
    vm_editor_restore_cvar("cl_viewmodel_shift_right_amt", viewmodel.old_shift_right, 0.75)

    if not rm.viewmodel_changer.override:get() then
        return
    end

    vm_editor_set_cvar("cl_headbob_land_dip_amt", 0)

    if amount >= 100 then
        return
    end

    if amount < 100 then
        vm_editor_set_cvar("cl_bob_lower_amt", 0)
    end

    if amount < 65 then
        vm_editor_set_cvar("cl_bobamt_lat", 0)
        vm_editor_set_cvar("cl_bobamt_vert", 0)
    end

    if amount < 35 then
        vm_editor_set_cvar("cl_wpn_sway_scale", 0)
        vm_editor_set_cvar("viewmodel_recoil", 0)
        vm_editor_set_cvar("cl_gunlowerangle", 0)
        vm_editor_set_cvar("cl_viewmodel_shift_left_amt", 0)
        vm_editor_set_cvar("cl_viewmodel_shift_right_amt", 0)
    end

    if amount <= 0 then
        vm_editor_set_cvar("cl_wpn_sway_interp", 0)
    end
end

local function vm_editor_is_hovered(mx, my)
    local editor = we_vars.viewmodel_editor
    if editor.last_x == nil or editor.last_y == nil then
        return false
    end

    return mx >= editor.last_x and my >= editor.last_y
        and mx <= editor.last_x + editor.w and my <= editor.last_y + editor.h
end

local function vm_editor_init_attachment()
    local editor = we_vars.viewmodel_editor
    if editor.attachment_ready ~= nil then
        return editor.attachment_ready
    end

    if not vtable_thunk then
        editor.attachment_ready = false
        return false
    end

    local raw_entity_list = client_create_interface("client_panorama.dll", "VClientEntityList003")
        or client_create_interface("client.dll", "VClientEntityList003")

    if not raw_entity_list then
        editor.attachment_ready = false
        return false
    end

    local ok, get_client_entity, get_attachment, get_muzzle_attachment = pcall(function()
        return
            vtable_thunk(3, "void*(__thiscall*)(void*, int)"),
            vtable_thunk(84, "bool(__thiscall*)(void*, int, we_attachment_vec3&)"),
            vtable_thunk(468, "int(__thiscall*)(void*, void*)")
    end)

    if not ok or not get_client_entity or not get_attachment or not get_muzzle_attachment then
        editor.attachment_ready = false
        return false
    end

    editor.entity_list = raw_entity_list
    editor.get_client_entity = get_client_entity
    editor.get_attachment = get_attachment
    editor.get_muzzle_attachment = get_muzzle_attachment
    editor.attachment_ready = true
    return true
end

local function vm_editor_get_anchor()
    local editor = we_vars.viewmodel_editor
    if globals_tickcount() <= (editor.suspend_until or 0) then
        return nil, nil
    end

    if globals_mapname() == nil then
        return nil, nil
    end

    if not vm_editor_init_attachment() then return nil, nil end

    local lp = entity_get_local_player()
    if not lp or not entity_is_alive(lp) then return nil, nil end

    local weapon = entity_get_player_weapon(lp)
    if not weapon then return nil, nil end

    local view_model = entity_get_prop(lp, "m_hViewModel[0]")
    if not view_model then return nil, nil end

    local ok, sx, sy = pcall(function()
        local active_weapon = editor.get_client_entity(editor.entity_list, weapon)
        local view_model_entity = editor.get_client_entity(editor.entity_list, view_model)

        if not active_weapon or not view_model_entity then
            return nil, nil
        end

        local attachment_index = editor.get_muzzle_attachment(active_weapon, view_model_entity)
        if not attachment_index or attachment_index <= 0 then
            return nil, nil
        end

        local attachment = ffi.new("we_attachment_vec3[1]")
        if not editor.get_attachment(view_model_entity, attachment_index, attachment[0]) then
            return nil, nil
        end

        return renderer_world_to_screen(attachment[0].x, attachment[0].y, attachment[0].z)
    end)

    if not ok or sx == nil or sy == nil then
        return nil, nil
    end

    return sx - editor.w, sy - editor.h
end

local function vm_editor_init_input()
    local editor = we_vars.viewmodel_editor
    if editor.input_ready ~= nil then
        return editor.input_ready
    end

    local raw_inputsystem = client_create_interface("inputsystem.dll", "InputSystemVersion001")
    if not raw_inputsystem then
        editor.input_ready = false
        return false
    end

    local inputsystem = ffi_cast("void***", raw_inputsystem)
    local ok, is_button_down, get_button_pressed_tick, get_analog_delta = pcall(function()
        return
            ffi_cast("WE_IsButtonDown", inputsystem[0][15]),
            ffi_cast("WE_GetInputTick", inputsystem[0][16]),
            ffi_cast("WE_GetAnalog", inputsystem[0][19])
    end)

    if not ok or not is_button_down or not get_button_pressed_tick or not get_analog_delta then
        editor.input_ready = false
        return false
    end

    editor.inputsystem = inputsystem
    editor.is_button_down = is_button_down
    editor.get_button_pressed_tick = get_button_pressed_tick
    editor.get_analog_delta = get_analog_delta
    editor.input_ready = true
    return true
end

local function vm_editor_button_down(button_code)
    local editor = we_vars.viewmodel_editor
    if not vm_editor_init_input() then return false end

    local ok, result = pcall(editor.is_button_down, editor.inputsystem, button_code)
    return ok and result == true
end

local function vm_editor_get_wheel_delta()
    local editor = we_vars.viewmodel_editor
    if not vm_editor_init_input() then return 0 end
    if globals_tickcount() < editor.wheel_next_tick then return 0 end

    local ok_up, up_tick = pcall(editor.get_button_pressed_tick, editor.inputsystem, VM_EDITOR_WHEEL_UP)
    local ok_down, down_tick = pcall(editor.get_button_pressed_tick, editor.inputsystem, VM_EDITOR_WHEEL_DOWN)
    local delta = 0

    if ok_up and up_tick ~= nil and up_tick ~= 0 and up_tick ~= editor.wheel_up_tick then
        delta = delta + 1
        editor.wheel_up_tick = up_tick
    end

    if ok_down and down_tick ~= nil and down_tick ~= 0 and down_tick ~= editor.wheel_down_tick then
        delta = delta - 1
        editor.wheel_down_tick = down_tick
    end

    if delta ~= 0 then
        editor.wheel_next_tick = globals_tickcount() + 2
        return delta
    end

    local up = vm_editor_button_down(VM_EDITOR_WHEEL_UP)
    local down = vm_editor_button_down(VM_EDITOR_WHEEL_DOWN)

    if up and not editor.wheel_up_prev then
        delta = delta + 1
    end

    if down and not editor.wheel_down_prev then
        delta = delta - 1
    end

    editor.wheel_up_prev = up
    editor.wheel_down_prev = down

    if delta ~= 0 then
        editor.wheel_next_tick = globals_tickcount() + 2
    end

    return delta
end

local function vm_editor_capture_input()
    we_vars.viewmodel_editor.block_input_until = globals_tickcount() + 2
end

local function vm_editor_should_block_input()
    local editor = we_vars.viewmodel_editor
    return editor.block_input_until ~= nil
        and globals_tickcount() <= editor.block_input_until
end

local function vm_editor_suspend(ticks)
    local editor = we_vars.viewmodel_editor
    editor.suspend_until = globals_tickcount() + (ticks or 64)
    editor.dragging = false
    editor.last_x = nil
    editor.last_y = nil
    editor.attachment_ready = nil
    editor.entity_list = nil
    editor.get_client_entity = nil
    editor.get_attachment = nil
    editor.get_muzzle_attachment = nil
end

function vm_editor_is_scoped()
    local lp = entity_get_local_player()
    if not lp then return false end

    local ok, is_scoped = pcall(function()
        local weapon = entity_get_player_weapon(lp)
        if not weapon then return false end
        return entity_get_prop(lp, "m_bIsScoped") == 1
    end)

    return ok and is_scoped == true
end

local function vm_editor_is_thirdperson()
    if vm_editor_thirdperson_ref[1] == nil or vm_editor_thirdperson_ref[2] == nil then
        return false
    end

    local ok, enabled, active = pcall(function()
        return ui.get(vm_editor_thirdperson_ref[1]), ui.get(vm_editor_thirdperson_ref[2])
    end)

    return ok and enabled == true and active == true
end

function vm_editor_apply_values(scoped, immediate)
    local viewmodel = we_vars.viewmodel
    local values = vm_editor_get_values(scoped)
    local profile = vm_editor_get_profile(scoped)
    local target_fov = vm_editor_clamp(values.fov, VM_EDITOR_FOV_MIN, VM_EDITOR_FOV_MAX)
    local target_x = vm_editor_clamp(values.x, VM_EDITOR_X_MIN, VM_EDITOR_X_MAX) / 10
    local target_y = vm_editor_clamp(values.y, VM_EDITOR_Y_MIN, VM_EDITOR_Y_MAX) / 10
    local target_z = vm_editor_clamp(values.z, VM_EDITOR_Z_MIN, VM_EDITOR_Z_MAX) / 10

    if viewmodel.current_fov == nil then
        viewmodel.current_fov = target_fov
        viewmodel.current_x = target_x
        viewmodel.current_y = target_y
        viewmodel.current_z = target_z
    end
    viewmodel.active_profile = profile

    local factor = immediate and 1 or math_min(1, 12 * globals_frametime())

    viewmodel.current_fov = viewmodel.current_fov + (target_fov - viewmodel.current_fov) * factor
    viewmodel.current_x = viewmodel.current_x + (target_x - viewmodel.current_x) * factor
    viewmodel.current_y = viewmodel.current_y + (target_y - viewmodel.current_y) * factor
    viewmodel.current_z = viewmodel.current_z + (target_z - viewmodel.current_z) * factor

    if math.abs(viewmodel.current_fov - target_fov) < 0.001 then viewmodel.current_fov = target_fov end
    if math.abs(viewmodel.current_x - target_x) < 0.001 then viewmodel.current_x = target_x end
    if math.abs(viewmodel.current_y - target_y) < 0.001 then viewmodel.current_y = target_y end
    if math.abs(viewmodel.current_z - target_z) < 0.001 then viewmodel.current_z = target_z end

    client_set_cvar("viewmodel_fov", viewmodel.current_fov)
    client_set_cvar("viewmodel_offset_x", viewmodel.current_x)
    client_set_cvar("viewmodel_offset_y", viewmodel.current_y)
    client_set_cvar("viewmodel_offset_z", viewmodel.current_z)
end

local function vm_editor_apply_wheel_delta(wheel_delta)
    if wheel_delta == 0 then return end

    local scoped = vm_editor_is_scoped()
    local use_scope = vm_editor_use_scope_values(scoped)
    local shift = client_key_state(0x10) == true
    local ctrl = client_key_state(0x11) == true

    if use_scope then
        vm_editor_ensure_scope_values()
    end

    if shift then
        local fov_step = ctrl and 1 or 2
        vm_editor_set_value(
            use_scope and "scope_fov" or "fov",
            (use_scope and we_vars.viewmodel.scope_fov or we_vars.viewmodel.fov) + wheel_delta * fov_step,
            VM_EDITOR_FOV_MIN,
            VM_EDITOR_FOV_MAX,
            use_scope
        )
    else
        local y_step = ctrl and 2 or 8
        vm_editor_set_value(
            use_scope and "scope_y" or "y",
            (use_scope and we_vars.viewmodel.scope_y or we_vars.viewmodel.y) + wheel_delta * y_step,
            VM_EDITOR_Y_MIN,
            VM_EDITOR_Y_MAX,
            use_scope
        )
    end

    vm_editor_apply_values(scoped)
end

local function vm_editor_apply_screen_error(error_x, error_y, scoped)
    local ctrl = client_key_state(0x11) == true
    local use_scope = vm_editor_use_scope_values(scoped)
    local gain = ctrl and 0.018 or 0.055
    local step_x = error_x * gain
    local step_z = -error_y * gain

    if math.abs(error_x) < 0.25 then
        step_x = 0
    end

    if math.abs(error_y) < 0.25 then
        step_z = 0
    end

    if step_x ~= 0 then
        if use_scope then
            vm_editor_ensure_scope_values()
            vm_editor_set_value("scope_x", we_vars.viewmodel.scope_x + step_x, VM_EDITOR_X_MIN, VM_EDITOR_X_MAX, true)
        else
            vm_editor_set_value("x", we_vars.viewmodel.x + step_x, VM_EDITOR_X_MIN, VM_EDITOR_X_MAX)
        end
    end

    if step_z ~= 0 then
        if use_scope then
            vm_editor_ensure_scope_values()
            vm_editor_set_value("scope_z", we_vars.viewmodel.scope_z + step_z, VM_EDITOR_Z_MIN, VM_EDITOR_Z_MAX, true)
        else
            vm_editor_set_value("z", we_vars.viewmodel.z + step_z, VM_EDITOR_Z_MIN, VM_EDITOR_Z_MAX)
        end
    end
end

we_cb.viewmodel_editor = function()
    local editor = we_vars.viewmodel_editor

    if not ui.is_menu_open()
        or not rm.viewmodel_changer.override:get()
        or vm_editor_is_thirdperson()
    then
        editor.dragging = false
        editor.drag_start_mouse_x = nil
        editor.drag_start_mouse_y = nil
        editor.drag_grab_to_muzzle_x = nil
        editor.drag_grab_to_muzzle_y = nil
        return
    end

    local anchor_x, anchor_y = vm_editor_get_anchor()
    if anchor_x == nil or anchor_y == nil then
        editor.dragging = false
        editor.drag_start_mouse_x = nil
        editor.drag_start_mouse_y = nil
        editor.last_x = nil
        editor.last_y = nil
        editor.drag_grab_to_muzzle_x = nil
        editor.drag_grab_to_muzzle_y = nil
        return
    end

    local mx, my = ui.mouse_position()
    local x = anchor_x
    local y = anchor_y

    editor.last_x = x
    editor.last_y = y

    local hovered = vm_editor_is_hovered(mx, my)
    local mouse_down = client_key_state(0x01) == true
    local scoped = vm_editor_is_scoped()

    if not mouse_down then
        editor.dragging = false
        editor.drag_start_mouse_x = nil
        editor.drag_start_mouse_y = nil
        editor.drag_grab_to_muzzle_x = nil
        editor.drag_grab_to_muzzle_y = nil
    elseif hovered and not editor.dragging then
        editor.dragging = true
        editor.drag_start_mouse_x = mx
        editor.drag_start_mouse_y = my
        editor.drag_grab_to_muzzle_x = anchor_x + editor.w - mx
        editor.drag_grab_to_muzzle_y = anchor_y + editor.h - my
    end

    if editor.dragging and editor.drag_grab_to_muzzle_x ~= nil and editor.drag_grab_to_muzzle_y ~= nil then
        local current_muzzle_x = anchor_x + editor.w
        local current_muzzle_y = anchor_y + editor.h
        local target_muzzle_x = mx + editor.drag_grab_to_muzzle_x
        local target_muzzle_y = my + editor.drag_grab_to_muzzle_y
        local error_x = target_muzzle_x - current_muzzle_x
        local error_y = target_muzzle_y - current_muzzle_y

        vm_editor_apply_screen_error(error_x, error_y, scoped)
        vm_editor_apply_values(scoped, true)
    end

    local capture_mouse = hovered or editor.dragging
    if capture_mouse then
        vm_editor_capture_input()
    end

    local wheel_delta = capture_mouse and vm_editor_get_wheel_delta() or 0
    if wheel_delta ~= 0 then
        vm_editor_apply_wheel_delta(wheel_delta)
    end

    local r, g, b = hovered and 35 or 18, hovered and 35 or 18, hovered and 35 or 18
    renderer_rectangle(x, y, editor.w, editor.h, r, g, b, 145)
    renderer_rectangle(x, y - 2, editor.w, 2, 160, 220, 40, 220)
    renderer_text(x + 3, y + 4, 235, 235, 235, 235, '-', nil, 'VIEWMODEL')
    renderer_text(x + 6, y + 22, 190, 190, 190, 225, '', nil, 'drag: X/Z')
    renderer_text(x + 6, y + 37, 190, 190, 190, 225, '', nil, 'wheel: Y')

    local values = vm_editor_get_values(scoped)
    local scoped_values = values.label == 'S'
    local x_label = scoped_values and 'SX %.1f' or 'X %.1f'
    local z_label = scoped_values and 'SZ %.1f' or 'Z %.1f'
    renderer_text(x + 76, y + 22, 215, 215, 215, 230, '', nil, string_format(x_label, values.x / 10))
    renderer_text(x + 76, y + 37, 215, 215, 215, 230, '', nil, string_format(z_label, values.z / 10))
end

we_cb.viewmodel_in_scope = function()
    client_set_cvar("fov_cs_debug", rm.viewmodel_in_scope:get() and 90 or 0)
end

we_cb.viewmodel_changer = function()
    if not rm.viewmodel_changer.override:get() then
        we_vars.viewmodel.current_fov = nil
        we_vars.viewmodel.current_x = nil
        we_vars.viewmodel.current_y = nil
        we_vars.viewmodel.current_z = nil
        we_vars.viewmodel.active_profile = nil
        client_set_cvar("viewmodel_fov",      we_vars.viewmodel.old_fov)
        client_set_cvar("viewmodel_offset_x", we_vars.viewmodel.old_x)
        client_set_cvar("viewmodel_offset_y", we_vars.viewmodel.old_y)
        client_set_cvar("viewmodel_offset_z", we_vars.viewmodel.old_z)
        vm_editor_apply_hand_movement()
        return
    end

    vm_editor_apply_hand_movement()
    vm_editor_apply_values(vm_editor_is_scoped())
end

we_cb.scope_hide_update = function()
    if not rm.viewmodel_changer.override:get() then
        return
    end

    vm_editor_apply_values(vm_editor_is_scoped())
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
    rm.viewmodel_changer.scope_hide:set_callback(we_cb.viewmodel_changer)
    rm.viewmodel_changer.hand_move:set_callback(vm_editor_apply_hand_movement)
    if rm.viewmodel_changer.storage ~= nil then
        rm.viewmodel_changer.storage.fov:set_callback(vm_editor_schedule_load_storage)
        rm.viewmodel_changer.storage.x:set_callback(vm_editor_schedule_load_storage)
        rm.viewmodel_changer.storage.y:set_callback(vm_editor_schedule_load_storage)
        rm.viewmodel_changer.storage.z:set_callback(vm_editor_schedule_load_storage)
        rm.viewmodel_changer.storage.scope_fov:set_callback(vm_editor_schedule_load_storage)
        rm.viewmodel_changer.storage.scope_x:set_callback(vm_editor_schedule_load_storage)
        rm.viewmodel_changer.storage.scope_y:set_callback(vm_editor_schedule_load_storage)
        rm.viewmodel_changer.storage.scope_z:set_callback(vm_editor_schedule_load_storage)
        rm.viewmodel_changer.storage.scope_custom:set_callback(vm_editor_schedule_load_storage)
    end
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
    vm_editor_load_storage()
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
    we_cb.scope_hide_update()
end)

client.set_event_callback("paint_ui", function()
    we_cb.draw_scope_ui()
    we_cb.viewmodel_editor()
end)

client.set_event_callback("setup_command", function(cmd)
    if not vm_editor_should_block_input() then
        return
    end

    cmd.in_attack = 0
    cmd.in_attack2 = 0
    cmd.in_attack3 = 0
    cmd.in_weapon1 = 0
    cmd.in_weapon2 = 0
    cmd.weaponselect = 0
    cmd.weaponsubtype = 0
end)

client.set_event_callback("string_cmd", function(cmd)
    if not vm_editor_should_block_input() then
        return
    end

    if cmd == "invnext"
        or cmd == "invprev"
        or cmd == "+jump"
        or cmd == "-jump"
    then
        return true
    end
end)

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
        vm_editor_suspend(128)
        we_vars.weather.created = false
        we_vars.weather.precipitation_entity_idx = nil
        we_vars.weather.precipitation_class = nil
    end
    we_vars.bullet_tracers.to_draw = {}
    we_vars.hitbox_data.to_draw    = {}
end)

client.set_event_callback("level_init", function()
    vm_editor_suspend(32)
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
    vm_editor_suspend(64)
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
    vm_editor_restore_cvar("cl_bob_lower_amt", we_vars.viewmodel.old_bob_lower, 21)
    vm_editor_restore_cvar("cl_bobamt_lat", we_vars.viewmodel.old_bob_lat, 0.4)
    vm_editor_restore_cvar("cl_bobamt_vert", we_vars.viewmodel.old_bob_vert, 0.25)
    vm_editor_restore_cvar("cl_bobup", we_vars.viewmodel.old_bob_up, 0.5)
    vm_editor_restore_cvar("cl_use_new_headbob", we_vars.viewmodel.old_use_new_headbob, 1)
    vm_editor_restore_cvar("cl_headbob_land_dip_amt", we_vars.viewmodel.old_headbob_land_dip, 4)
    vm_editor_restore_cvar("cl_wpn_sway_scale", we_vars.viewmodel.old_wpn_sway_scale, 1.6)
    vm_editor_restore_cvar("cl_wpn_sway_interp", we_vars.viewmodel.old_wpn_sway_interp, 0.1)
    vm_editor_restore_cvar("viewmodel_recoil", we_vars.viewmodel.old_viewmodel_recoil, 1)
    vm_editor_restore_cvar("cl_gunlowerangle", we_vars.viewmodel.old_gun_lower_angle, 2)
    vm_editor_restore_cvar("cl_viewmodel_shift_left_amt", we_vars.viewmodel.old_shift_left, 1.5)
    vm_editor_restore_cvar("cl_viewmodel_shift_right_amt", we_vars.viewmodel.old_shift_right, 0.75)
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
