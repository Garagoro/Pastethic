local ffi = require("ffi")

local DB_KEY = "colorskinscsgo_skin_color_config_v1"
local CONFIG_FILE = "colorskinscsgo_config.json"
local SKIN_SELECTION_PREFIX = "__skin_selection:"
local PAINTKIT_COLOR_PREFIX = "__paintkit_color:"

local read = function(typename, address)
    if address == nil then
        return function(address)
            return ffi.cast(ffi.typeof(typename.."*"), ffi.cast("uint32_t ", address))[0]
        end
    end
    return ffi.cast(ffi.typeof(typename.."*"), ffi.cast("uint32_t ", address))[0]
end
local follow_call = function(ptr)
    local insn = ffi.cast("uint8_t*", ptr)

    if insn[0] == 0xE8 then
        -- relative, displacement relative to next instruction
        local offset = ffi.cast("int32_t*", insn+1)[0]

        return insn + offset + 5
    elseif insn[0] == 0xFF and insn[1] == 0x15 then
        -- absolute
        local call_addr = ffi.cast("uint32_t**", ffi.cast("const char*", ptr)+2)

        return call_addr[0][0]
    elseif insn[0] == 0xB0 then
        return ffi.cast("uint32_t", ptr + 4 + read("uint32_t", ptr))
    else
        error(string.format("unknown instruction to follow: %02X!", insn[0]))
    end
end
local string_t = [[struct {
    char* buffer;
    int capacity;
    int grow_size;
    int length;
}]]
local paint_kit_t = [[struct {
    int nID;

    ]].. string_t ..[[ name;
    ]].. string_t ..[[ description;
    ]].. string_t ..[[ tag;
    ]].. string_t ..[[ same_name_family_aggregate;
    ]].. string_t ..[[ pattern;
    ]].. string_t ..[[ normal;
    ]].. string_t ..[[ logoMaterial;
    bool baseDiffuseOverride;
    int rarity;
    int style;
    uint8_t color[4][4];
    char pad[35];
    float wearRemapMin;
    float wearRemapMax;
}]]
local create_map_t = function(key_type, value_type)
    return ffi.typeof([[struct {
    void* lessFunc;
    struct {
        struct {
            int left;
            int right;
            int parent;
            int type;
            $ key;
            $ value;
        }* memory;
        int allocationCount;
        int growSize;
    } memory;
    int root;
    int num_elements;
    int firstFree;
    int lastAlloc;
    struct {
        int left;
        int right;
        int parent;
        int type;
        $ key;
        $ value;
    }* elements;
}
]], ffi.typeof(key_type), ffi.typeof(value_type), ffi.typeof(key_type), ffi.typeof(value_type))
end
item_schema_t = ffi.typeof([[struct {
    $ paint_kits;
}*]],
create_map_t("int", paint_kit_t.."*"))
local get_item_schema_addr = client.find_signature("client.dll", "\xA1\xCC\xCC\xCC\xCC\x85\xC0\x75\x53") or error("cant find get_item_scham()")
local get_item_schema_fn = ffi.cast("uint32_t(__stdcall*)()", get_item_schema_addr)
local get_paint_kit_definition_addr = client.find_signature("client.dll", "\xE8\xCC\xCC\xCC\xCC\x8B\xF0\x8B\x4E\x7C") or error("cant find get_paint_kit_definition")
local get_paint_kit_definition_fn = ffi.cast("void*(__thiscall*)(void*, int)", follow_call(get_paint_kit_definition_addr))

local item_schema_c = {}

function item_schema_c.create(ptr)
    return setmetatable({
        ptr = ptr,
    }, {
        __index = item_schema_c,
        __metatable = "item_schema"
    })
end
function item_schema_c:get_paint_kit(index)
    local paint_kit_addr = get_paint_kit_definition_fn(self.ptr, index)
    if paint_kit_addr == nil then return end

    return ffi.cast(ffi.typeof(paint_kit_t .. "*"), paint_kit_addr)
end

local schema = item_schema_c.create(ffi.cast(item_schema_t, get_item_schema_fn()+4));
local json_escape = function(value)
    value = tostring(value)
    value = string.gsub(value, "\\", "\\\\")
    value = string.gsub(value, '"', '\\"')
    return value
end

local normalize_color_table = function(colors)
    if type(colors) ~= "table" then return nil end

    local result = {}
    for layer = 1, 4 do
        local color = colors[ layer ]
        if type(color) ~= "table" then return nil end

        result[ layer ] = {
            math.max(0, math.min(255, tonumber(color[ 1 ]) or 255)),
            math.max(0, math.min(255, tonumber(color[ 2 ]) or 255)),
            math.max(0, math.min(255, tonumber(color[ 3 ]) or 255)),
            math.max(0, math.min(255, tonumber(color[ 4 ]) or 255))
        }
    end

    return result
end

local decode_config_json = function(text)
    if type(text) ~= "string" then return {} end

    local result = {}

    for key, value in string.gmatch(text, '"([^"]+)"%s*:%s*(%-?%d+)') do
        if string.sub(key, 1, #SKIN_SELECTION_PREFIX) == SKIN_SELECTION_PREFIX then
            result[ key ] = tonumber(value)
        end
    end

    for key, body in string.gmatch(text, '"([^"]+)"%s*:%s*(%[%[.-%]%])') do
        local nums = {}
        for number in string.gmatch(body, '%-?%d+') do
            nums[ #nums + 1 ] = tonumber(number)
        end

        if #nums >= 16 then
            result[ key ] = {
                { nums[ 1 ], nums[ 2 ], nums[ 3 ], nums[ 4 ] },
                { nums[ 5 ], nums[ 6 ], nums[ 7 ], nums[ 8 ] },
                { nums[ 9 ], nums[ 10 ], nums[ 11 ], nums[ 12 ] },
                { nums[ 13 ], nums[ 14 ], nums[ 15 ], nums[ 16 ] }
            }
        end
    end

    return result
end

local encode_config_json = function(colors_by_key)
    local keys = {}
    for key in pairs(colors_by_key) do
        keys[ #keys + 1 ] = key
    end
    table.sort(keys)

    local entries = {}
    for i = 1, #keys do
        local key = keys[ i ]
        local value = colors_by_key[ key ]

        if string.sub(key, 1, #SKIN_SELECTION_PREFIX) == SKIN_SELECTION_PREFIX and type(value) == "number" then
            entries[ #entries + 1 ] = string.format('  "%s": %d', json_escape(key), value)
        else
            local colors = normalize_color_table(value)
            if colors ~= nil then
                entries[ #entries + 1 ] = string.format(
                '  "%s": [[%d,%d,%d,%d],[%d,%d,%d,%d],[%d,%d,%d,%d],[%d,%d,%d,%d]]',
                json_escape(key),
                colors[1][1], colors[1][2], colors[1][3], colors[1][4],
                colors[2][1], colors[2][2], colors[2][3], colors[2][4],
                colors[3][1], colors[3][2], colors[3][3], colors[3][4],
                colors[4][1], colors[4][2], colors[4][3], colors[4][4]
            )
            end
        end
    end

    local lines = { "{" }
    for i = 1, #entries do
        lines[ #lines + 1 ] = entries[ i ] .. (i < #entries and "," or "")
    end
    lines[ #lines + 1 ] = "}"

    return table.concat(lines, "\n")
end

local read_config_json = function()
    if io == nil or io.open == nil then return {} end

    local file = io.open(CONFIG_FILE, "r")
    if file == nil then return {} end

    local text = file:read("*a")
    file:close()

    return decode_config_json(text)
end

local write_config_json = function(colors_by_key)
    if io == nil or io.open == nil then return false end

    local file = io.open(CONFIG_FILE, "w")
    if file == nil then return false end

    file:write(encode_config_json(colors_by_key))
    file:write("\n")
    file:close()

    return true
end

local load_config = function()
    local from_file = read_config_json()
    if next(from_file) ~= nil then
        return from_file
    end

    local from_database = database.read(DB_KEY)
    if type(from_database) == "table" then
        return from_database
    end

    return {}
end

local skin_color_config
local pending_config_save_token = 0
local config_change_callbacks = {}
local clone_config_table
local notify_config_change

local flush_config_json_debounced = function(token)
    if token ~= pending_config_save_token then return end
    write_config_json(skin_color_config)
end

local save_config = function(colors_by_key)
    database.write(DB_KEY, colors_by_key)

    pending_config_save_token = pending_config_save_token + 1
    local token = pending_config_save_token
    client.delay_call(0.5, function()
        flush_config_json_debounced(token)
    end)

    if notify_config_change ~= nil then
        notify_config_change()
    end
end

skin_color_config = load_config()

local ctx = {
    skin_color_config = skin_color_config,
    applied_skins = {},
    paintkit_owner = {},
    vars = {
        colors = {
            ui.new_color_picker('SKINS', 'Weapon skin', '1', 255, 255, 255, 255),
            ui.new_color_picker('SKINS', 'Weapon skin', '2', 255, 255, 255, 255),
            ui.new_color_picker('SKINS', 'Weapon skin', '3', 255, 255, 255, 255),
            ui.new_color_picker('SKINS', 'Weapon skin', '4`', 255, 255, 255, 255)
        },
        reset_colors = nil,
    },
    refs = {
        skins_enabled = ui.reference('SKINS', 'Weapon skin', 'Enabled'),
        skins_weapon_skin = ui.reference('SKINS', 'Weapon skin', 'Skin'),
    },

    paint_kits = {},
    o_pk_colors = {},
    current_paintkit = nil,
    syncing_menu = false,
    syncing_skin = false,
    refresh_token = 0,
    last_weapon_ent = nil,
    last_skin_key = nil,
    last_weapon_team_key = nil,
    weapon_seen_at = 0,
    maybe_disabled_skins = {},

    set_paintkit_color = function( obj, r, g, b, a )
        obj[ 0 ] = r;
        obj[ 1 ] = g;
        obj[ 2 ] = b;
        obj[ 3 ] = a;
    end,

    set_menu_color = function(ref, obj )
        ui.set(ref, obj[ 0 ], obj[ 1 ], obj[ 2 ], obj[ 3 ])
    end,
}

local init = function()
    for i = 1, 4000 do
        local num = i;
    
        if num >= 3000 then
            num = num + 10000;
        end
    
        local paint_kit = schema:get_paint_kit(num);
        if paint_kit ~= nil then
            local copy = ffi.new( "uint8_t[4][4]" );

            for layer = 0, 3 do
                ctx.set_paintkit_color(
                    copy[ layer ],
                    paint_kit.color[ layer ][ 0 ],
                    paint_kit.color[ layer ][ 1 ],
                    paint_kit.color[ layer ][ 2 ],
                    paint_kit.color[ layer ][ 3 ]
                )
            end
            
            ctx.paint_kits[ paint_kit.nID ] = paint_kit
            ctx.o_pk_colors[ paint_kit.nID ] = copy
        end
    end

    ctx.current_paintkit = ui.get(ctx.refs.skins_weapon_skin)
end

init()

local get_skin_key
local get_weapon_team_key
local get_paintkit_color_key
local save_active_config

local ensure_skinchanger_enabled = function()
    if not ui.get(ctx.refs.skins_enabled) then
        ui.set(ctx.refs.skins_enabled, true)
    end
end

local force_update = function()
    ui.set(ctx.refs.skins_enabled, false)
    client.delay_call(0.8, ensure_skinchanger_enabled)
end

local get_menu_colors = function()
    local result = {}

    for x = 1, 4 do
        local r, g, b, a = ui.get(ctx.vars.colors[ x ])
        result[ x ] = { r, g, b, a }
    end

    return result
end

local set_menu_colors_table = function(colors)
    if type(colors) ~= "table" then return end

    ctx.syncing_menu = true

    for x = 1, 4 do
        local color = colors[ x ]
        if type(color) == "table" then
            ui.set(ctx.vars.colors[ x ], color[ 1 ] or 255, color[ 2 ] or 255, color[ 3 ] or 255, color[ 4 ] or 255)
        end
    end

    ctx.syncing_menu = false
end

local apply_color_table = function(paintkit, colors)
    local paint_kit = ctx.paint_kits[ paintkit ]
    if paint_kit == nil or type(colors) ~= "table" then return false end

    for x = 1, 4 do
        local color = colors[ x ]
        if type(color) == "table" then
            ctx.set_paintkit_color(
                paint_kit.color[ x - 1 ],
                color[ 1 ] or 255,
                color[ 2 ] or 255,
                color[ 3 ] or 255,
                color[ 4 ] or 255
            )
        end
    end

    return true
end

local colors_match_original = function(paintkit, colors)
    local original = ctx.o_pk_colors[ paintkit ]
    colors = normalize_color_table(colors)
    if original == nil or colors == nil then return false end

    for layer = 1, 4 do
        local color = colors[ layer ]
        local source = original[ layer - 1 ]
        for channel = 1, 4 do
            if color[ channel ] ~= source[ channel - 1 ] then
                return false
            end
        end
    end

    return true
end


local get_current_weapon_id = function()
    local player = entity.get_local_player()
    if player == nil then return nil end

    local weapon = entity.get_player_weapon(player)
    if weapon == nil then return nil end

    local weapon_id = entity.get_prop(weapon, "m_iItemDefinitionIndex")
    if weapon_id == nil then return nil end

    return weapon_id % 65536
end

local get_current_team = function()
    local player = entity.get_local_player()
    if player == nil then return nil end

    return entity.get_prop(player, "m_iTeamNum")
end

get_skin_key = function()
    local weapon_id = get_current_weapon_id()
    local paintkit = ui.get(ctx.refs.skins_weapon_skin)

    if weapon_id == nil or paintkit == nil then return nil, paintkit end

    local color_key = get_paintkit_color_key(paintkit)
    local legacy_key = tostring(weapon_id) .. ";" .. tostring(paintkit)
    local team = get_current_team()

    if team == nil then
        return color_key, paintkit, weapon_id, nil, legacy_key
    end

    return color_key, paintkit, weapon_id, team, legacy_key, tostring(team) .. ";" .. legacy_key
end

get_weapon_team_key = function()
    local weapon_id = get_current_weapon_id()
    if weapon_id == nil then return nil end

    local team = get_current_team()
    local legacy_key = tostring(weapon_id)
    if team == nil then
        return legacy_key, legacy_key
    end

    return tostring(team) .. ";" .. legacy_key, legacy_key
end

get_paintkit_color_key = function(paintkit)
    paintkit = tonumber(paintkit)
    if paintkit == nil then return nil end

    return PAINTKIT_COLOR_PREFIX .. tostring(paintkit)
end

local get_weapon_held_time = function()
    local seen_at = tonumber(ctx.weapon_seen_at) or 0
    if seen_at <= 0 then return nil end

    return globals.curtime() - seen_at
end

local mark_current_skin_maybe_disabled = function()
    local key = get_skin_key()
    if key ~= nil then
        ctx.maybe_disabled_skins[key] = true
    end
end

local enable_current_skin_if_marked = function()
    local key = get_skin_key()
    if key == nil or not ctx.maybe_disabled_skins[key] then return false end

    if not ui.get(ctx.refs.skins_enabled) then
        ui.set(ctx.refs.skins_enabled, true)
    end

    ctx.maybe_disabled_skins[key] = nil
    return true
end

local get_skin_selection_key = function(team_weapon_key)
    if team_weapon_key == nil then return nil end
    return SKIN_SELECTION_PREFIX .. team_weapon_key
end

local save_skin_for_current_weapon = function(paintkit)
    local team_weapon_key = get_weapon_team_key()
    paintkit = tonumber(paintkit)
    if team_weapon_key == nil or paintkit == nil then return false end

    ctx.skin_color_config[ get_skin_selection_key(team_weapon_key) ] = paintkit
    save_active_config()

    return true
end

local apply_saved_skin_for_current_weapon = function()
    local team_weapon_key, legacy_weapon_key = get_weapon_team_key()
    if team_weapon_key == nil then return false end

    local saved = ctx.skin_color_config[ get_skin_selection_key(team_weapon_key) ]
    if saved == nil and legacy_weapon_key ~= nil and legacy_weapon_key ~= team_weapon_key then
        saved = ctx.skin_color_config[ get_skin_selection_key(legacy_weapon_key) ]
    end

    saved = tonumber(saved)
    if saved == nil then return false end

    if ui.get(ctx.refs.skins_weapon_skin) ~= saved then
        ctx.syncing_skin = true
        ui.set(ctx.refs.skins_weapon_skin, saved)
        ctx.syncing_skin = false
    end

    ctx.current_paintkit = saved
    return true
end

local apply_config_for_current_skin

local apply_saved_skin_and_rebuild = function()
    local applied_skin = apply_saved_skin_for_current_weapon()
    local applied_config = apply_config_for_current_skin(true)

    if applied_skin and not applied_config then
        force_update()
    end

    local held_time = get_weapon_held_time()
    if held_time ~= nil and held_time < 1 then
        mark_current_skin_maybe_disabled()
    end

    return applied_skin or applied_config
end

clone_config_table = function(source)
    if type(source) ~= "table" then return {} end

    local result = {}
    local active_paintkits = {}
    local selections = {}

    for key, value in pairs(source) do
        key = tostring(key)

        if type(value) == "number" and string.sub(key, 1, #SKIN_SELECTION_PREFIX) == SKIN_SELECTION_PREFIX then
            local paintkit = tonumber(value)
            if paintkit ~= nil then
                result[key] = paintkit
                selections[string.sub(key, #SKIN_SELECTION_PREFIX + 1)] = paintkit
                active_paintkits[paintkit] = true
            end
        end
    end

    for key, value in pairs(source) do
        key = tostring(key)

        if type(value) == "table" then
            local colors = normalize_color_table(value)
            if colors ~= nil then
                local paintkit = tonumber(string.match(key, "^" .. PAINTKIT_COLOR_PREFIX .. "(%d+)$"))

                if paintkit ~= nil then
                    if active_paintkits[paintkit] then
                        result[get_paintkit_color_key(paintkit)] = colors
                    end
                else
                    local team, weapon_id, legacy_paintkit = string.match(key, "^(%d+);(%d+);(%d+)$")
                    if team ~= nil and weapon_id ~= nil and legacy_paintkit ~= nil then
                        local selected = selections[tostring(team) .. ";" .. tostring(weapon_id)]
                        paintkit = tonumber(legacy_paintkit)

                        if selected == paintkit and result[get_paintkit_color_key(paintkit)] == nil then
                            result[get_paintkit_color_key(paintkit)] = colors
                        end
                    else
                        local legacy_weapon_id
                        legacy_weapon_id, legacy_paintkit = string.match(key, "^(%d+);(%d+)$")
                        paintkit = tonumber(legacy_paintkit)

                        if paintkit ~= nil and selections[legacy_weapon_id] == paintkit and result[get_paintkit_color_key(paintkit)] == nil then
                            result[get_paintkit_color_key(paintkit)] = colors
                        end
                    end
                end
            end
        end
    end

    return result
end

save_active_config = function()
    ctx.skin_color_config = clone_config_table(ctx.skin_color_config)
    skin_color_config = ctx.skin_color_config
    save_config(ctx.skin_color_config)
end

ctx.skin_color_config = clone_config_table(ctx.skin_color_config)
skin_color_config = ctx.skin_color_config
save_config(ctx.skin_color_config)

notify_config_change = function()
    local snapshot = clone_config_table(ctx.skin_color_config)

    for i = 1, #config_change_callbacks do
        pcall(config_change_callbacks[i], snapshot)
    end
end

local import_config_table = function(data)
    skin_color_config = clone_config_table(data)
    ctx.skin_color_config = skin_color_config
    ctx.applied_skins = {}
    ctx.paintkit_owner = {}
    save_active_config()
    client.delay_call(0.8, apply_saved_skin_and_rebuild)
end

local save_colors_for_current_skin = function(colors)
    local key, paintkit = get_skin_key()
    colors = normalize_color_table(colors)

    if key == nil or colors == nil then return false end

    local team_weapon_key = get_weapon_team_key()
    if team_weapon_key ~= nil then
        ctx.skin_color_config[ get_skin_selection_key(team_weapon_key) ] = paintkit
    end

    local is_original = colors_match_original(paintkit, colors)

    if is_original then
        ctx.skin_color_config[ key ] = nil
    else
        ctx.skin_color_config[ key ] = colors
    end

    save_active_config()

    return true, key, not is_original
end

apply_config_for_current_skin = function(should_force_update)
    local key, paintkit, weapon_id, team, legacy_key, team_legacy_key = get_skin_key()
    if key == nil or paintkit == nil then return false end

    local colors = normalize_color_table(ctx.skin_color_config[ key ])
    if colors == nil and team_legacy_key ~= nil and team_legacy_key ~= key then
        colors = normalize_color_table(ctx.skin_color_config[ team_legacy_key ])
        if colors ~= nil then
            ctx.skin_color_config[ key ] = colors
            save_active_config()
        end
    end

    if colors == nil and legacy_key ~= nil and legacy_key ~= key then
        colors = normalize_color_table(ctx.skin_color_config[ legacy_key ])
        if colors ~= nil then
            ctx.skin_color_config[ key ] = colors
            save_active_config()
        end
    end

    if colors == nil then return false, key, paintkit end

    local needs_rebuild = ctx.paintkit_owner[ paintkit ] ~= key or ctx.applied_skins[ key ] ~= true

    set_menu_colors_table(colors)
    apply_color_table(paintkit, colors)

    if should_force_update and needs_rebuild then
        force_update()
        ctx.applied_skins[ key ] = true
        ctx.paintkit_owner[ paintkit ] = key
    end

    return true, key, paintkit
end

local set_paintkit_colors = function( paintkit )
    if ctx.paint_kits[ paintkit ] == nil then return end

    for x = 1, 4 do
        ctx.set_paintkit_color( ctx.paint_kits[ paintkit ].color[ x - 1 ], ui.get(ctx.vars.colors[ x ]) )
    end
end

local set_menu_colors = function( obj )
    if obj == nil then return end

    ctx.syncing_menu = true

    for x = 1, 4 do
        ctx.set_menu_color( ctx.vars.colors[ x ], obj[ x - 1 ] )
    end

    ctx.syncing_menu = false
end

local reset_paintkit_colors = function( paintkit )
    set_menu_colors( ctx.o_pk_colors[ paintkit ] )
end

local color_cb = function()
    if ctx.syncing_menu then return end

    ctx.current_paintkit = ui.get(ctx.refs.skins_weapon_skin)
    set_paintkit_colors( ctx.current_paintkit )

    local saved, key, stored_color = save_colors_for_current_skin(get_menu_colors())
    if saved and key ~= nil then
        ctx.applied_skins[ key ] = stored_color == true
        ctx.paintkit_owner[ ctx.current_paintkit ] = stored_color == true and key or nil
    end

    force_update()
    client.delay_call(0.8, function() set_paintkit_colors(ctx.current_paintkit); apply_config_for_current_skin(true); ensure_skinchanger_enabled() end)
end

local weapon_skin_cb = function()
    if not ctx.syncing_skin then
        save_skin_for_current_weapon(ui.get(ctx.refs.skins_weapon_skin))
    end

    ctx.current_paintkit = ui.get(ctx.refs.skins_weapon_skin)

    if apply_config_for_current_skin(true) then
        return
    end

    if ctx.paint_kits[ ctx.current_paintkit ] ~= nil then
        set_menu_colors( ctx.paint_kits[ ctx.current_paintkit ].color )
        set_paintkit_colors( ctx.current_paintkit )
        save_colors_for_current_skin(get_menu_colors())
    end

    force_update()
end

local reset_color_cb = function()
    ctx.current_paintkit = ui.get(ctx.refs.skins_weapon_skin)
    reset_paintkit_colors( ctx.current_paintkit )
    set_paintkit_colors( ctx.current_paintkit )
    local saved, key, stored_color = save_colors_for_current_skin(get_menu_colors())

    if saved and key ~= nil then
        ctx.applied_skins[ key ] = stored_color == true
        ctx.paintkit_owner[ ctx.current_paintkit ] = stored_color == true and key or nil
    end

    force_update()
end

local startup_skin_refresh = function()
    client.delay_call(0.8, apply_saved_skin_and_rebuild)
end

local schedule_skin_refresh = function()
    ctx.refresh_token = ctx.refresh_token + 1
    local token = ctx.refresh_token

    client.delay_call(0.8, function()
        if token ~= ctx.refresh_token then return end
        apply_saved_skin_and_rebuild()
    end)
end

_G.pasthetic_colorskins = {
    import = function(data)
        import_config_table(data)
    end,

    restore = function(data)
        import_config_table(data)
    end,

    export = function()
        return clone_config_table(ctx.skin_color_config)
    end,

    on_change = function(callback)
        if type(callback) ~= "function" then
            return false
        end

        table.insert(config_change_callbacks, callback)
        return true
    end
}
_G.aesthetic_colorskins = _G.pasthetic_colorskins

ctx.vars.reset_colors = ui.new_button('SKINS', 'Weapon skin', 'Reset color', reset_color_cb)
ui.set_callback(ctx.refs.skins_weapon_skin, weapon_skin_cb )
ui.set_callback(ctx.vars.colors[ 1 ], color_cb )
ui.set_callback(ctx.vars.colors[ 2 ], color_cb )
ui.set_callback(ctx.vars.colors[ 3 ], color_cb )
ui.set_callback(ctx.vars.colors[ 4 ], color_cb )

startup_skin_refresh()
client.set_event_callback("paint", function()
    local player = entity.get_local_player()
    if player == nil then return end

    local weapon = entity.get_player_weapon(player)
    local team_weapon_key = get_weapon_team_key()
    local key = get_skin_key()
    if weapon == nil then return end

    if weapon == ctx.last_weapon_ent and key == ctx.last_skin_key and team_weapon_key == ctx.last_weapon_team_key then return end

    ctx.weapon_seen_at = globals.curtime()
    ctx.last_weapon_ent = weapon
    ctx.last_weapon_team_key = team_weapon_key

    apply_saved_skin_for_current_weapon()
    key = get_skin_key()
    ctx.last_skin_key = key
    enable_current_skin_if_marked()
    apply_config_for_current_skin(false)
    schedule_skin_refresh()
end)







