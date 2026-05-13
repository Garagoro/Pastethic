local M = {}

function M.start(deps)
    local script = assert(deps.script, 'resource_builder: script dependency is required')
    local menu = assert(deps.menu, 'resource_builder: menu dependency is required')
    local ui = assert(deps.ui, 'resource_builder: ui dependency is required')
    local const = assert(deps.const, 'resource_builder: const dependency is required')
    local ui_callback = assert(deps.ui_callback, 'resource_builder: ui_callback dependency is required')
    local external_config_ref = assert(deps.external_config_ref, 'resource_builder: external_config_ref dependency is required')
    local config_system = assert(deps.config_system, 'resource_builder: config_system dependency is required')
    local menu_logic = assert(deps.menu_logic, 'resource_builder: menu_logic dependency is required')
    local software = assert(deps.software, 'resource_builder: software dependency is required')
    local client = assert(deps.client, 'resource_builder: client dependency is required')
    local utils = assert(deps.utils, 'resource_builder: utils dependency is required')
    local logging = assert(deps.logging, 'resource_builder: logging dependency is required')
    local ui_debug = deps.ui_debug
    local color = assert(deps.color, 'resource_builder: color dependency is required')
    local bundled_dormant_resource = deps.bundled_dormant_resource
    local contains = assert(deps.contains, 'resource_builder: contains dependency is required')
    local unpack = deps.unpack or unpack

    local function is_debug_enabled()
        return ui_debug ~= nil and type(ui_debug.is_enabled) == 'function' and ui_debug:is_enabled()
    end

    local function wrap_external_config_ref(ref, on_fire)
        return external_config_ref.wrap({ ui = ui }, ref, on_fire)
    end
local resource do
    resource = { }

    local function new_key(str, key)
        if str:find '\n' == nil then
            str = str .. '\n'
        end

        return str .. key
    end

    local function lock_unselection(item, default_value)
        local old_value = item:get()

        if #old_value == 0 then
            if default_value == nil then
                if item.type == 'multiselect' then
                    default_value = item.list
                elseif item.type == 'list' then
                    default_value = { }

                    for i = 1, #item.list do
                        default_value[i] = i
                    end
                end
            end

            old_value = default_value
            item:set(default_value)
        end

        item:set_callback(function()
            local value = item:get()

            if #value > 0 then
                old_value = value
            else
                item:set(old_value)
            end

        end)
    end
    local function new_category_item(tab, container, name, list)
        local ref_menu_color = ui.reference(
            'Misc', 'Settings', 'Menu color'
        )

        local lookup = { } do
            local count = 0

            for i = 1, #list do
                local value = list[i]

                local title = value[1]
                local array = value[2]

                local index = count

                if title ~= nil then
                    index = index + 1
                end

                lookup[count] = index
                count = index + #array
            end
        end

        local function get_hex_color(r, g, b, a)
            return string.format(
                '%02x%02x%02x%02x',
                r, g, b, a
            )
        end

        local function get_render_list(r, g, b, a)
            local result = { }

            local hex = get_hex_color(
                r, g, b, a
            )

            for i = 1, #list do
                local value = list[i]

                local title = value[1]
                local array = value[2]

                if title ~= nil then
                    table.insert(result, string.format(
                        '\a%s%s', hex, title
                    ))
                end

                for j = 1, #array do
                    local str = array[j]

                    table.insert(result, string.format(
                        ' -  %s', str
                    ))
                end
            end

            return result
        end

        local render_list = get_render_list(
            ui.get(ref_menu_color)
        )

        local category_item = menu.new(
            ui.new_listbox,
            tab, container, name,
            render_list
        )

        local callbacks do
            local function on_menu_color(item)
                category_item:update(
                    get_render_list(
                        ui.get(item)
                    )
                )
            end

            local function on_category(item)
                local value = item:get()
                local new_value = lookup[value]

                if new_value == nil then
                    return
                end

                item:set(new_value)
            end

            ui_callback.set(
                ref_menu_color,
                on_menu_color
            )

            category_item:set_callback(
                on_category
            )
        end

        return category_item
    end

    local function new_selector_item(tab, container, name, list)
        local lookup = { } do
            for i = 1, #list do
                local value = list[i]

                local title = value[1]
                local array = value[2]

                lookup[title] = true
            end
        end

        local function get_render_list()
            local result = { }

            for i = 1, #list do
                local value = list[i]

                local title = value[1]
                local array = value[2]

                table.insert(result, title)

                for j = 1, #array do
                    local str = array[j]

                    table.insert(result, string.format(
                        ' -  %s', str
                    ))
                end
            end

            return result
        end

        local selector_item = menu.new(
            ui.new_multiselect,
            tab, container, name,
            get_render_list()
        )

        local callbacks do
            local function on_category(item)
                local value = item:get()

                local new_value = { }

                for i = 1, #value do
                    local str = value[i]

                    if not lookup[str] then
                        table.insert(new_value, str)
                    end
                end

                item:set(new_value)
            end

            selector_item:set_callback(
                on_category
            )
        end

        return selector_item
    end

    local general = { } do
        local function get_script_name_label()
            return string.format('Script: \a%s%s [%s]', software.get_color(true), script.name, script.build)
        end

        general.script_name = menu.new(
            ui.new_label, 'AA', 'Fake lag', get_script_name_label()
        )

        general.category = new_category_item(
            'AA', 'Fake lag', new_key('\n', 'category'), {
                {
                    nil, {
                        'Ragebot',
                        'Miscellaneous',
                        'Animations',
                        'Logging system',
                        'Automatic purchase'
                    }
                },

                {
                    'Anti-Aim', {
                        'Builder',
                        'Features',
                        'Hotkeys'
                    }
                },


                {
                    'Render', {
                        'World',
                        'Panorama',
                    }
                },

                {
                    'Manager', {
                        'Configurations'
                    }
                }
            }
        )

        local callbacks do
            local ref_menu_color = ui.reference(
                'Misc', 'Settings', 'Menu color'
            )

            local function on_menu_color(item)
                general.script_name:set(get_script_name_label())
            end

            ui_callback.set(
                ref_menu_color,
                on_menu_color
            )
        end

        resource.general = general

        if is_debug_enabled() and type(ui_debug.general_created) == 'function' then
            ui_debug:general_created(general)
        end
    end

    local main = { } do
        local ragebot = { } do
            local force_body_conditions = { } do
                local weapon_list = {
                    'Auto Snipers',
                    'Desert Eagle',
                    'Revolver R8',
                    'Pistols',
                    'Scout',
                    'AWP'
                }

                local condition_list = {
                    'Enemy lethal',
                    'Max misses'
                }

                local scout_damage_tooltips = { } do
                    scout_damage_tooltips[0] = 'Def.'

                    for i = 101, 126 do
                        scout_damage_tooltips[i] = string.format('HP+%d', i - 100)
                    end
                end

                force_body_conditions.enabled = config_system.push(
                    'Ragebot', 'force_body_conditions.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Force body condition', 'force_body_conditions')
                    )
                )

                force_body_conditions.weapons = config_system.push(
                    'Ragebot', 'force_body_conditions.weapons', menu.new(
                        ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Weapons', 'force_body_conditions'), weapon_list
                    )
                )

                force_body_conditions.conditions = config_system.push(
                    'Ragebot', 'force_body_conditions.conditions', menu.new(
                        ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Conditions', 'force_body_conditions'), condition_list
                    )
                )

                force_body_conditions.max_misses = config_system.push(
                    'Ragebot', 'force_body_conditions.max_misses', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Max misses', 'force_body_conditions'), 1, 5, 2
                    )
                )

                force_body_conditions.scout_damage = config_system.push(
                    'Ragebot', 'force_body_conditions.scout_damage', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Scout damage', 'force_body_conditions'), 0, 126, 0, true, '', 1, scout_damage_tooltips
                    )
                )

                force_body_conditions.disabler = config_system.push(
                    'Ragebot', 'force_body_conditions.disabler', menu.new(
                        ui.new_hotkey, 'AA', 'Anti-aimbot angles', new_key('Disabler', 'force_body_conditions')
                    )
                )

                force_body_conditions.separator = menu.new(
                    ui.new_label, 'AA', 'Anti-aimbot angles', '\n'
                )

                lock_unselection(force_body_conditions.conditions)
                lock_unselection(force_body_conditions.weapons)

                ragebot.force_body_conditions = force_body_conditions
            end

            local force_lethal = { } do
                local weapon_list = {
                    'Auto Snipers',
                    'Desert Eagle'
                }

                force_lethal.enabled = config_system.push(
                    'Ragebot', 'force_lethal.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Force lethal', 'force_lethal')
                    )
                )

                force_lethal.weapons = config_system.push(
                    'Ragebot', 'force_lethal.weapons', menu.new(
                        ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Weapons', 'force_lethal'), weapon_list
                    )
                )

                force_lethal.mode = config_system.push(
                    'Ragebot', 'force_lethal.mode', menu.new(
                        ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Mode', 'force_lethal'), {
                            'Default',
                            'Damage = HP/2'
                        }
                    )
                )

                for i = 1, #weapon_list do
                    local weapon = weapon_list[i]

                    local list = { }

                    list.hitchance = config_system.push(
                        'Ragebot', 'force_lethal.hitchance.' .. weapon, menu.new(
                            ui.new_slider, 'AA', 'Anti-aimbot angles', new_key(weapon .. ' hitchance', 'force_lethal'), -1, 100, -1, true, '%', 1, {
                                [-1] = 'Off'
                            }
                        )
                    )

                    force_lethal[weapon] = list
                end

                force_lethal.separator = menu.new(
                    ui.new_label, 'AA', 'Anti-aimbot angles', '\n'
                )

                lock_unselection(force_lethal.weapons)
                force_lethal.weapon_list = weapon_list

                ragebot.force_lethal = force_lethal
            end


            local allow_duck_on_fd = { } do
                allow_duck_on_fd.enabled = config_system.push(
                    'Ragebot', 'allow_duck_on_fd.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Allow duck on fd', 'allow_duck_on_fd')
                    )
                )

                ragebot.allow_duck_on_fd = allow_duck_on_fd
            end

            local unsafe_recharge = { } do
                unsafe_recharge.enabled = config_system.push(
                    'Ragebot', 'unsafe_recharge.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Unsafe recharge', 'unsafe_recharge')
                    )
                )

                ragebot.unsafe_recharge = unsafe_recharge
            end

            local hideshots_fix = { } do
                hideshots_fix.enabled = config_system.push(
                    'Ragebot', 'hideshots_fix.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Hideshots fix', 'hideshots_fix')
                    )
                )

                ragebot.hideshots_fix = hideshots_fix
            end

            local auto_whitelist_broken_lc = { } do
                auto_whitelist_broken_lc.enabled = config_system.push(
                    'Ragebot', 'auto_whitelist_broken_lc.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Bad record handler', 'auto_whitelist_broken_lc')
                    )
                )

                auto_whitelist_broken_lc.actions = config_system.push(
                    'Ragebot', 'auto_whitelist_broken_lc.actions', menu.new(
                        ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Defensive action', 'auto_whitelist_broken_lc.actions'), {
                            'Force body',
                            'Whitelist'
                        }
                    )
                )
                auto_whitelist_broken_lc.actions:set('Force body')

                auto_whitelist_broken_lc.separator = menu.new(
                    ui.new_label, 'AA', 'Anti-aimbot angles', '\n'
                )

                ragebot.auto_whitelist_broken_lc = auto_whitelist_broken_lc
            end

            local hitchance = { } do
                local option_list = {
                    'In Air',
                    'No Scope',
                    'Hotkey',
                    'Crouch',
                    'Peek Assist'
                }

                local weapon_list = {
                    'Auto Snipers',
                    'Desert Eagle',
                    'Revolver R8',
                    'Pistols',
                    'Scout',
                    'AWP'
                }

                hitchance.enabled = config_system.push(
                    'Ragebot', 'hitchance.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Other', new_key('Hitchance override', 'hitchance')
                    )
                )

                hitchance.weapon = menu.new(
                    ui.new_combobox, 'AA', 'Other', new_key('Weapon', 'hitchance'), weapon_list
                )

                for i = 1, #weapon_list do
                    local weapon = weapon_list[i]

                    local should_has_scope = (
                        weapon == 'Auto Snipers' or
                        weapon == 'Scout' or
                        weapon == 'AWP'
                    )

                    local new_option_list = {
                        unpack(option_list)
                    }

                    if not should_has_scope then
                        local index = contains(
                            new_option_list, 'No Scope'
                        )

                        if index ~= nil then
                            table.remove(new_option_list, index)
                        end
                    end

                    local function hash(name)
                        return string.format(
                            'hitchance.%s[%s]',
                            name, weapon
                        )
                    end

                    local items = { }

                    items.options = config_system.push(
                        'Ragebot', hash 'options', menu.new(
                            ui.new_multiselect, 'AA', 'Other', new_key('Options', hash 'options'), new_option_list
                        )
                    )

                    for j = 1, #new_option_list do
                        local option = new_option_list[j]

                        local function hash_option(name)
                            return hash(string.format(
                                '%s[%s]', option, name
                            ))
                        end

                        local option_items = { }

                        option_items.value = config_system.push(
                            'Ragebot', hash_option 'value', menu.new(
                                ui.new_slider, 'AA', 'Other', new_key(option, hash_option 'value'), 0, 100, 0, true, '%'
                            )
                        )

                        if option == 'No Scope' then
                            option_items.distance = config_system.push(
                                'Ragebot', hash_option 'distance', menu.new(
                                    ui.new_slider, 'AA', 'Other', new_key('Distance', hash_option 'distance'), 5, 101, 35, true, 'u', 1, {
                                        [101] = 'Inf'
                                    }
                                )
                            )
                        end

                        items[option] = option_items
                    end

                    hitchance[weapon] = items
                end

                hitchance.hotkey = config_system.push(
                    'Ragebot', 'hitchance.hotkey', menu.new(
                        ui.new_hotkey, 'AA', 'Other', 'Override hitchance'
                    )
                )

                hitchance.indicator_text = config_system.push(
                    'Ragebot', 'hitchance.indicator_text', menu.new(
                        ui.new_combobox, 'AA', 'Other', new_key('Indicator text', 'hitchance'), {
                            'Off',
                            'HC',
                            'HITCHANCE',
                            'HITCHANCE OVR'
                        }
                    )
                )

                hitchance.separator = menu.new(
                    ui.new_label, 'AA', 'Other', '\n'
                )

                hitchance.option_list = option_list

                ragebot.hitchance = hitchance
            end

            local peek_assist = { } do
                peek_assist.enabled = config_system.push(
                    'Ragebot', 'peek_assist.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Other', new_key('Peek assist', 'peek_assist')
                    )
                )

                local weapon_list = {
                    'Auto Snipers',
                    'Desert Eagle',
                    'Revolver R8',
                    'Pistols',
                    'Scout',
                    'AWP'
                }

                peek_assist.weapons = config_system.push(
                    'Ragebot', 'peek_assist.weapons', menu.new(
                        ui.new_multiselect, 'AA', 'Other', new_key('Weapons', 'peek_assist'), weapon_list
                    )
                )

                lock_unselection(peek_assist.weapons)

                peek_assist.limit = config_system.push(
                    'Ragebot', 'peek_assist.limit', menu.new(
                        ui.new_slider, 'AA', 'Other', new_key('Peek assist limit', 'peek_assist'), 1, 10, 1, true, 't'
                    )
                )

                peek_assist.separator = menu.new(
                    ui.new_label, 'AA', 'Other', '\n'
                )

                ragebot.peek_assist = peek_assist
            end

            local ai_peek = { } do
                ai_peek.enabled = config_system.push(
                    'Ragebot', 'ai_peek.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Other', new_key('AI peek', 'ai_peek')
                    )
                )

                ai_peek.hotkey = config_system.push(
                    'Ragebot', 'ai_peek.hotkey', menu.new(
                        ui.new_hotkey, 'AA', 'Other', new_key('Hotkey', 'ai_peek'), true
                    )
                )

                ai_peek.min_damage_label = menu.new(
                    ui.new_label, 'AA', 'Other', new_key('Minimum damage key', 'ai_peek')
                )

                ai_peek.min_damage_override = config_system.push(
                    'Ragebot', 'ai_peek.min_damage_override', menu.new(
                        ui.new_hotkey, 'AA', 'Other', new_key('\n', 'ai_peek.min_damage_override'), true
                    )
                )

                ai_peek.scan_all = config_system.push(
                    'Ragebot', 'ai_peek.scan_all', menu.new(
                        ui.new_checkbox, 'AA', 'Other', new_key('Scan all players', 'ai_peek')
                    )
                )

                ai_peek.live_scan = config_system.push(
                    'Ragebot', 'ai_peek.live_scan', menu.new(
                        ui.new_checkbox, 'AA', 'Other', new_key('Live angle scan', 'ai_peek')
                    )
                )

                ai_peek.distance = config_system.push(
                    'Ragebot', 'ai_peek.distance', menu.new(
                        ui.new_slider, 'AA', 'Other', new_key('Distance', 'ai_peek'), 25, 100, 70, true, 'u'
                    )
                )

                ai_peek.separation = config_system.push(
                    'Ragebot', 'ai_peek.separation', menu.new(
                        ui.new_slider, 'AA', 'Other', new_key('Separation', 'ai_peek'), 2, 8, 2
                    )
                )

                ai_peek.count = config_system.push(
                    'Ragebot', 'ai_peek.count', menu.new(
                        ui.new_slider, 'AA', 'Other', new_key('Count', 'ai_peek'), 1, 10, 2
                    )
                )

                ai_peek.prediction = config_system.push(
                    'Ragebot', 'ai_peek.prediction', menu.new(
                        ui.new_slider, 'AA', 'Other', new_key('Prediction ticks', 'ai_peek'), 1, 16, 5, true, 't'
                    )
                )

                ai_peek.hitboxes = config_system.push(
                    'Ragebot', 'ai_peek.hitboxes', menu.new(
                        ui.new_multiselect, 'AA', 'Other', new_key('Hitboxes', 'ai_peek'), {
                            'Head',
                            'Neck',
                            'Pelvis',
                            'Stomach',
                            'Lower chest',
                            'Chest',
                            'Upper chest',
                            'Left thigh',
                            'Right thigh',
                            'Left calf',
                            'Right calf',
                            'Left foot',
                            'Right foot',
                            'Left hand',
                            'Right hand',
                            'Left upper arm',
                            'Left forearm',
                            'Right upper arm',
                            'Right forearm'
                        }
                    )
                )

                lock_unselection(ai_peek.hitboxes)
                ai_peek.scan_all:set(true)
                ai_peek.hitboxes:set({
                    'Head',
                    'Pelvis',
                    'Left foot',
                    'Right foot',
                    'Left forearm',
                    'Right forearm'
                })

                ai_peek.debug = config_system.push(
                    'Ragebot', 'ai_peek.debug', menu.new(
                        ui.new_checkbox, 'AA', 'Other', new_key('Debug positions', 'ai_peek')
                    )
                )

                ai_peek.separator = menu.new(
                    ui.new_label, 'AA', 'Other', '\n'
                )

                ragebot.ai_peek = ai_peek
            end

            main.ragebot = ragebot
        end

        local miscellaneous = { } do

            local fast_ladder = { } do
                fast_ladder.enabled = config_system.push(
                    'Miscellaneous', 'fast_ladder.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Fast ladder', 'fast_ladder')
                    )
                )

                miscellaneous.fast_ladder = fast_ladder
            end

            local air_stop_shift = { } do
                air_stop_shift.enabled = config_system.push(
                    'Miscellaneous', 'air_stop_shift.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Air stop on Shift', 'air_stop_shift')
                    )
                )

                miscellaneous.air_stop_shift = air_stop_shift
            end

            local console_filter = { } do
                console_filter.enabled = config_system.push(
                    'Miscellaneous', 'console_filter.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Console filter', 'console_filter')
                    )
                )

                miscellaneous.console_filter = console_filter
            end

            local sync_ragebot_hotkeys = { } do
                sync_ragebot_hotkeys.enabled = config_system.push(
                    'Miscellaneous', 'sync_ragebot_hotkeys.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Sync ragebot hotkeys', 'sync_ragebot_hotkeys')
                    )
                )

                miscellaneous.sync_ragebot_hotkeys = sync_ragebot_hotkeys
            end

            local reveal_enemy_team_chat = { } do
                reveal_enemy_team_chat.enabled = config_system.push(
                    'Miscellaneous', 'reveal_enemy_team_chat.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Reveal enemy team chat', 'reveal_enemy_team_chat')
                    )
                )

                miscellaneous.reveal_enemy_team_chat = reveal_enemy_team_chat
            end

            local clantag = { } do
                clantag.enabled = config_system.push(
                    'Miscellaneous', 'clantag.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Clantag', 'clantag')
                    )
                )

                clantag.separator = menu.new(
                    ui.new_label, 'AA', 'Anti-aimbot angles', '\n'
                )

                miscellaneous.clantag = clantag
            end

            main.miscellaneous = miscellaneous
        end

        local animations = { } do
            animations.air_legs = config_system.push(
                'Animations', 'anim_breaker.air_legs', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Air legs', 'animations'), {
                        'Off',
                        'Static',
                        'Moonwalk',
                        'Kangaroo'
                    }
                )
            )

            animations.air_legs_weight = config_system.push(
                'Animations', 'anim_breaker.air_legs_weight', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Weight', 'animations'), 0, 100, 100, true, '%'
                )
            )

            animations.ground_legs = config_system.push(
                'Animations', 'anim_breaker.ground_legs', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Ground legs', 'animations'), {
                        'Off',
                        'Static',
                        'Jitter',
                        'Moonwalk',
                        'Kangaroo',
                        'Pacan4ik'
                    }
                )
            )

            animations.legs_offset_1 = config_system.push(
                'Animations', 'anim_breaker.legs_offset_1', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Offset 1', 'animations'), 0, 100, 100
                )
            )

            animations.legs_offset_2 = config_system.push(
                'Animations', 'anim_breaker.legs_offset_2', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Offset 2', 'animations'), 0, 100, 100
                )
            )

            animations.legs_jitter_time = config_system.push(
                'Animations', 'anim_breaker.legs_jitter_time', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Jitter time', 'animations'), 1, 8, 2, true, 't'
                )
            )

            animations.options = config_system.push(
                'Animations', 'anim_breaker.options', menu.new(
                    ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Options', 'animations'), {
                        'Move lean',
                        'Pitch zero on land'
                    }
                )
            )

            animations.move_lean = config_system.push(
                'Animations', 'anim_breaker.move_lean', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Move lean', 'animations'), -1, 100, -1, true, '', 1, {
                        [-1] = 'Off'
                    }
                )
            )

            main.animations = animations
        end

        local logging_system = { } do
            local main_color_list = {
                { 'Target', color(127, 180, 95, 255) },
                { 'Other', color(132, 163, 209, 255) }
            }

            local miss_color_list = {
                { 'Death', color(189, 75, 75, 255) },
                { 'Spread', color(189, 75, 75, 255) },
                { 'Resolver', color(189, 75, 75, 255) },
                { 'Prediction error', color(189, 75, 75, 255) },
                { 'Unregistered shot', color(189, 75, 75, 255) }
            }

            logging_system.enabled = config_system.push(
                'Logging system', 'logging_system.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Logging system', 'logging_system')
                )
            )

            logging_system.events = config_system.push(
                'Logging system', 'logging_system.events', menu.new(
                    ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Events', 'logging_system'), {
                        'Aimbot',
                        'Purchase'
                    }
                )
            )

            logging_system.output = config_system.push(
                'Logging system', 'logging_system.output', menu.new(
                    ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Output', 'logging_system'), {
                        'Console',
                        'Events',
                        'Under crosshair'
                    }
                )
            )

            logging_system.events_font = config_system.push(
                'Logging system', 'logging_system.events_font', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Events font', 'logging_system'), {
                        'Bold',
                        'Old'
                    }
                )
            )

            logging_system.offset_y = config_system.push(
                'Logging system', 'logging_system.offset_y', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Offset Y', 'logging_system'), 0, 100, 100, true, '%'
                )
            )

            logging_system.duration = config_system.push(
                'Logging system', 'logging_system.duration', menu.new(
                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Duration', 'logging_system'), 5, 40, 100, true, 's.', 0.1
                )
            )

            logging_system.console_text_style = config_system.push(
                'Logging system', 'logging_system.console_text_style', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Console text style', 'logging_system'), {
                        'Pasthetic',
                        'Gamesense'
                    }
                )
            )

            logging_system.crosshair_text_style = config_system.push(
                'Logging system', 'logging_system.crosshair_text_style', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Crosshair text style', 'logging_system'), {
                        'Pasthetic',
                        'Gamesense'
                    }
                )
            )

            for i = 1, #main_color_list do
                local values = main_color_list[i]

                local name = values[1]
                local col = values[2]

                local items = { }

                local color_key = string.format('%s_color', name:lower())

                local label_name = string.format('%s color', name)
                local picker_name = string.format('%s color picker', name)

                items.label = menu.new(
                    ui.new_label, 'AA', 'Anti-aimbot angles', new_key(label_name, 'logging_system')
                )

                items.color = config_system.push(
                    'Logging system', string.format('logging_system.%s', color_key), menu.new(
                        ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key(picker_name, 'logging_system'), col:unpack()
                    )
                )

                logging_system[name] = items
            end

            logging_system.color_separator = menu.new(
                ui.new_label, 'AA', 'Anti-aimbot angles', '\n'
            )

            for i = 1, #miss_color_list do
                local values = miss_color_list[i]

                local name = values[1]
                local col = values[2]

                local items = { }

                local color_key = string.format('%s_color', name:lower())

                local label_name = string.format('%s color', name)
                local picker_name = string.format('%s color picker', name)

                items.label = menu.new(
                    ui.new_label, 'AA', 'Anti-aimbot angles', new_key(label_name, 'logging_system')
                )

                items.color = config_system.push(
                    'Logging system', string.format('logging_system.%s', color_key), menu.new(
                        ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key(picker_name, 'logging_system'), col:unpack()
                    )
                )

                logging_system[name] = items
            end

            lock_unselection(logging_system.output)
            lock_unselection(logging_system.events)

            logging_system.main_color_list = main_color_list
            logging_system.miss_color_list = miss_color_list

            main.logging_system = logging_system
        end

        local automatic_purchase = { } do
            automatic_purchase.enabled = config_system.push(
                'Automatic purchase', 'buy_bot.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Enabled', 'buy_bot')
                )
            )

            automatic_purchase.primary = config_system.push(
                'Automatic purchase', 'buy_bot.primary', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Primary', 'buy_bot'), {
                        'Off',
                        'AWP',
                        'Scout',
                        'G3SG1 / SCAR-20'
                    }
                )
            )

            automatic_purchase.alternative = config_system.push(
                'Automatic purchase', 'buy_bot.alternative', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Alternative', 'buy_bot'), {
                        'Off',
                        'Scout',
                        'G3SG1 / SCAR-20'
                    }
                )
            )

            automatic_purchase.secondary = config_system.push(
                'Automatic purchase', 'buy_bot.secondary', menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Secondary', 'buy_bot'), {
                        'Off',
                        'P250',
                        'Elites',
                        'Five-seven / Tec-9 / CZ75',
                        'Deagle / Revolver'
                    }
                )
            )

            automatic_purchase.equipment = config_system.push(
                'Automatic purchase', 'buy_bot.equipment', menu.new(
                    ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Equipment', 'buy_bot'), {
                        'Kevlar',
                        'Kevlar + Helmet',
                        'Defuse kit',
                        'HE',
                        'Smoke',
                        'Molotov',
                        'Taser'
                    }
                )
            )

            automatic_purchase.ignore_pistol_round = config_system.push(
                'Automatic purchase', 'buy_bot.ignore_pistol_round', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Ignore pistol round', 'buy_bot')
                )
            )

            automatic_purchase.only_16k = config_system.push(
                'Automatic purchase', 'buy_bot.only_16k', menu.new(
                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Only $16k', 'buy_bot')
                )
            )

            main.automatic_purchase = automatic_purchase
        end

        resource.main = main

        if bundled_dormant_resource ~= nil then
            resource.main.dormant = bundled_dormant_resource
        end
    end

    local antiaim = { } do
        local builder = { } do
            local function create_defensive_items(state, team)
                local items = { }

                local function hash(key)
                    return state .. ':' .. team .. ':defensive_' .. key
                end

                items.enabled = config_system.push(
                    'Builder', hash 'enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Other', new_key(
                            'Defensive anti-aim', hash 'enabled'
                        )
                    )
                )

                items.triggers = config_system.push(
                    'Builder', hash 'triggers', menu.new(
                        ui.new_multiselect, 'AA', 'Other', new_key('Defensive triggers', hash 'triggers'), {
                            'Always',
                            'On weapon switch',
                            'On reload',
                            'On hittable',
                            'On dormant peek',
                            'On freestand',
                            'Hotkey'
                        }
                    )
                )

                items.trigger_hotkey = config_system.push(
                    'Builder', hash 'trigger_hotkey', menu.new(
                        ui.new_hotkey, 'AA', 'Other', new_key('Hotkey', hash 'trigger_hotkey'), true
                    )
                )

                items.trigger_from = config_system.push(
                    'Builder', hash 'trigger_from', menu.new(
                        ui.new_slider, 'AA', 'Other', new_key('Trigger from', hash 'trigger_from'), 1, 64, 1, true, 't'
                    )
                )

                items.trigger_to = config_system.push(
                    'Builder', hash 'trigger_to', menu.new(
                        ui.new_slider, 'AA', 'Other', new_key('Trigger to', hash 'trigger_to'), 1, 64, 8, true, 't'
                    )
                )

                items.trigger_duration = config_system.push(
                    'Builder', hash 'trigger_duration', menu.new(
                        ui.new_slider, 'AA', 'Other', new_key('Trigger duration', hash 'trigger_duration'), 1, 32, 3, true, 't'
                    )
                )

                items.pitch = config_system.push(
                    'Builder', hash 'pitch', menu.new(
                        ui.new_combobox, 'AA', 'Other', new_key('Pitch', hash 'pitch'), {
                            'Off',
                            'Static',
                            'Sway',
                            'Spin',
                            'Cycling',
                            'Jitter',
                            'Switch',
                            'Random',
                            'Randomize Jitter',
                            'Generated',
                            'Static Random'
                        }
                    )
                )

                items.pitch_label_1 = menu.new(
                    ui.new_label, 'AA', 'Other', 'From'
                )

                items.pitch_offset_1 = config_system.push(
                    'Builder', hash 'pitch_offset_1', menu.new(
                        ui.new_slider, 'AA', 'Other', new_key('\n', hash 'pitch_offset_1'), -89, 89, 0, true, '?'
                    )
                )

                items.pitch_label_2 = menu.new(
                    ui.new_label, 'AA', 'Other', 'To'
                )

                items.pitch_offset_2 = config_system.push(
                    'Builder', hash 'pitch_offset_2', menu.new(
                        ui.new_slider, 'AA', 'Other', new_key('\n', hash 'pitch_offset_2'), -89, 89, 0, true, '?'
                    )
                )

                items.pitch_speed = config_system.push(
                    'Builder', hash 'pitch_speed', menu.new(
                        ui.new_slider, 'AA', 'Other', new_key('Speed', hash 'pitch_speed'), -75, 75, 20, true, nil, 0.1
                    )
                )

                items.yaw = config_system.push(
                    'Builder', hash 'yaw', menu.new(
                        ui.new_combobox, 'AA', 'Other', new_key('Yaw', hash 'yaw'), {
                            'Off',
                            'Side Based',
                            'Opposite',
                            'Spin',
                            'Sway',
                            'Distortion',
                            'Freestand',
                            'X-Way',
                            'Random',
                            'Left/Right',
                            'Generated',
                            'Static Random'
                        }
                    )
                )

                items.ways_count = config_system.push(
                    'Builder', hash 'ways_count', menu.new(
                        ui.new_slider, 'AA', 'Other', new_key('\n', hash 'ways_count'), 3, 7, 3, true, ''
                    )
                )

                items.ways_custom = config_system.push(
                    'Builder', hash 'ways_custom', menu.new(
                        ui.new_checkbox, 'AA', 'Other', new_key('Custom ways', hash 'ways_custom')
                    )
                )

                for i = 1, 7 do
                    items['way_' .. i] = config_system.push(
                        'Builder', hash('way_' .. i), menu.new(
                            ui.new_slider, 'AA', 'Other', new_key('\n', hash('way_' .. i)), -180, 180, 0, true, '?'
                        )
                    )
                end

                items.yaw_offset = config_system.push(
                    'Builder', hash 'yaw_offset', menu.new(
                        ui.new_slider, 'AA', 'Other', new_key('\n', hash 'yaw_offset'), -180, 180, 0, true, '?'
                    )
                )

                items.yaw_left = config_system.push(
                    'Builder', hash 'yaw_left', menu.new(
                        ui.new_slider, 'AA', 'Other', new_key('Yaw left', hash 'yaw_left'), -180, 180, 0, true, '?'
                    )
                )

                items.yaw_right = config_system.push(
                    'Builder', hash 'yaw_right', menu.new(
                        ui.new_slider, 'AA', 'Other', new_key('Yaw right', hash 'yaw_right'), -180, 180, 0, true, '?'
                    )
                )

                items.yaw_speed = config_system.push(
                    'Builder', hash 'yaw_speed', menu.new(
                        ui.new_slider, 'AA', 'Other', new_key('Speed', hash 'yaw_speed'), -75, 75, 20, true, '', 0.1
                    )
                )

                items.ways_auto_body_yaw = config_system.push(
                    'Builder', hash 'ways_auto_body_yaw', menu.new(
                        ui.new_checkbox, 'AA', 'Other', new_key('Automatic body yaw', hash 'ways_auto_body_yaw')
                    )
                )

                items.body_yaw = config_system.push(
                    'Builder', hash 'body_yaw', menu.new(
                        ui.new_combobox, 'AA', 'Other', new_key('Body yaw', hash 'body_yaw'), {
                            'Off',
                            'Opposite',
                            'Static',
                            'Jitter',
                            'Jitter Random'
                        }
                    )
                )

                items.body_yaw_offset = config_system.push(
                    'Builder', hash 'body_yaw_offset', menu.new(
                        ui.new_slider, 'AA', 'Other', new_key('\n', hash 'body_yaw_offset'), -180, 180, 0, true, '?'
                    )
                )

                items.freestanding_body_yaw = config_system.push(
                    'Builder', hash 'freestanding_body_yaw', menu.new(
                        ui.new_checkbox, 'AA', 'Other', new_key(
                            'Freestanding body yaw', hash 'freestanding_body_yaw'
                        )
                    )
                )

                return items
            end

            local function create_builder_items(state, team, std_key)
                local items = { }

                local is_default = state == 'Default'
                local is_legit_aa = state == 'Legit AA'

                local is_freestanding = state == 'Freestanding'

                local function hash(key)
                    return team .. ':' .. state .. ':' .. key
                end

                if std_key ~= nil then
                    function hash(key)
                        return state .. ':' .. team .. ':' .. key .. ':' .. std_key
                    end
                end

                if not is_default then
                    local enabled_name = string.format(
                        'Override %s', state
                    )

                    items.enabled = config_system.push(
                        'Builder', hash 'enabled', menu.new(
                            ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key(
                                enabled_name, hash 'enabled'
                            )
                        )
                    )
                end

                if is_legit_aa then
                    items.bomb_e_fix = config_system.push(
                        'Builder', hash 'bomb_e_fix', menu.new(
                            ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key(
                                'Bomb E fix', hash 'bomb_e_fix'
                            )
                        )
                    )
                end

                if is_legit_aa then
                    items.yaw_base = config_system.push(
                        'Builder', hash 'yaw_base', menu.new(
                            ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Yaw base', hash 'yaw_base'), {
                                'Local view',
                                'At targets'
                            }
                        )
                    )
                end

                if not is_freestanding then
                    if state == 'Move-Crouch' then
                        items.yaw_direction = config_system.push(
                            'Builder', hash 'yaw_direction', menu.new(
                                ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Yaw direction', hash 'yaw_direction'), {
                                    'General', unpack(const.crouch_dirs)
                                }
                            )
                        )
                    end

                    items.yaw_left = config_system.push(
                        'Builder', hash 'yaw_left', menu.new(
                            ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Yaw left', hash 'yaw_left'), -180, 180, 0, true, '?'
                        )
                    )

                    items.yaw_right = config_system.push(
                        'Builder', hash 'yaw_right', menu.new(
                            ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Yaw right', hash 'yaw_right'), -180, 180, 0, true, '?'
                        )
                    )

                    if state == 'Move-Crouch' then
                        for i = 1, #const.crouch_dirs do
                            local dir = const.crouch_dirs[i]

                            items['enabled_dir_' .. dir] = config_system.push(
                                'Builder', hash('enabled_dir_' .. dir), menu.new(
                                    ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Enable ' .. dir, hash('enabled_dir_' .. dir))
                                )
                            )

                            items['yaw_left_dir_' .. dir] = config_system.push(
                                'Builder', hash('yaw_left_dir_' .. dir), menu.new(
                                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Yaw left', hash('yaw_left_dir_' .. dir)), -180, 180, 0, true, '?'
                                )
                            )

                            items['yaw_right_dir_' .. dir] = config_system.push(
                                'Builder', hash('yaw_right_dir_' .. dir), menu.new(
                                    ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Yaw left', hash('yaw_right_dir_' .. dir)), -180, 180, 0, true, '?'
                                )
                            )
                        end
                    end

                    items.yaw_random = config_system.push(
                        'Builder', hash 'yaw_random', menu.new(
                            ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Antibrute delta', hash 'yaw_random'), 0, 100, 0, true, '%'
                        )
                    )

                    items.yaw_jitter = config_system.push(
                        'Builder', hash 'yaw_jitter', menu.new(
                            ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Yaw jitter', hash 'yaw_jitter'), {
                                'Off',
                                'Offset',
                                'Center',
                                'Random',
                                'Sway',
                                'Randomized',
                                'Center Flick',
                                'Offset Flick'
                            }
                        )
                    )

                    items.jitter_offset = config_system.push(
                        'Builder', hash 'jitter_offset', menu.new(
                            ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', hash 'jitter_offset'), -180, 180, 0, true, '?'
                        )
                    )

                    items.jitter_random = config_system.push(
                        'Builder', hash 'jitter_random', menu.new(
                            ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Antibrute delta', hash 'jitter_random'), 0, 100, 0, true, '%'
                        )
                    )

                    items.jitter_min = config_system.push(
                        'Builder', hash 'jitter_min', menu.new(
                            ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Min', hash 'jitter_min'), -180, 180, -60, true, '?'
                        )
                    )

                    items.jitter_max = config_system.push(
                        'Builder', hash 'jitter_max', menu.new(
                            ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Max', hash 'jitter_max'), -180, 180, 60, true, '?'
                        )
                    )

                    items.jitter_delay = config_system.push(
                        'Builder', hash 'jitter_delay', menu.new(
                            ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Delay', hash 'jitter_delay'), 1, 64, 1, true, 't'
                        )
                    )

                    items.jitter_speed = config_system.push(
                        'Builder', hash 'jitter_speed', menu.new(
                            ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Speed', hash 'jitter_speed'), 1, 64, 1, true, 't'
                        )
                    )
                end

                items.body_yaw = config_system.push(
                    'Builder', hash 'body_yaw', menu.new(
                        ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Body yaw', hash 'body_yaw'), {
                            'Off',
                            'Opposite',
                            'Static',
                            'Jitter',
                            'Jitter Random'
                        }
                    )
                )

                items.body_yaw_offset = config_system.push(
                    'Builder', hash 'body_yaw_offset', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', hash 'body_yaw_offset'), -180, 180, 0, true, '?'
                    )
                )

                items.freestanding_body_yaw = config_system.push(
                    'Builder', hash 'freestanding_body_yaw', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key(
                            'Freestanding body yaw', hash 'freestanding_body_yaw'
                        )
                    )
                )

                if state ~= 'Fakelag' then
                    items.delay_from = config_system.push(
                        'Builder', hash 'delay_from', menu.new(
                            ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Delay from', hash 'delay_from'), 1, 8, 1, true, 't', 1, {
                                [1] = 'Off'
                            }
                        )
                    )

                    items.delay_to = config_system.push(
                        'Builder', hash 'delay_to', menu.new(
                            ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Delay to', hash 'delay_to'), 1, 8, 1, true, 't', 1, {
                                [1] = 'Off'
                            }
                        )
                    )

                    items.delay_chaos = config_system.push(
                        'Builder', hash 'delay_chaos', menu.new(
                            ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Delay chaos', hash 'delay_chaos'), 0, 8, 0, true, 't'
                        )
                    )
                end

                return items
            end

            local function get_items(state, team)
                local items = builder[state]

                if items == nil then
                    return nil
                end

                return items[team]
            end

            local function get_values(items)
                local data = { }

                if items.angles ~= nil then
                    data.angles = { enabled = { true } }

                    for k, v in pairs(items.angles) do
                        data.angles[k] = { v:get() }
                    end
                end

                if items.defensive ~= nil then
                    data.defensive = { }

                    for k, v in pairs(items.defensive) do
                        data.defensive[k] = { v:get() }
                    end
                end

                return data
            end

            local function set_values(items, data)
                if items.angles ~= nil and data.angles ~= nil then
                    for k, v in pairs(data.angles) do
                        local item = items.angles[k]

                        if item == nil then
                            goto continue
                        end

                        if item.type == 'label' then
                            goto continue
                        end

                        item:set(unpack(v))

                        ::continue::
                    end
                end

                if items.defensive ~= nil and data.defensive ~= nil then
                    for k, v in pairs(data.defensive) do
                        local item = items.defensive[k]

                        if item == nil then
                            goto continue
                        end

                        if item.type == 'label' then
                            goto continue
                        end

                        item:set(unpack(v))

                        ::continue::
                    end
                end
            end


            builder.state = menu.new(
                ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('State', 'builder'), const.states
            )

            for i = 1, #const.states do
                local state = const.states[i]

                local items = { }

                items.team = menu.new(
                    ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Team', 'builder'), const.teams
                )

                for j = 1, #const.teams do
                    local team = const.teams[j]

                    local team_items = { }

                    team_items.angles = create_builder_items(
                        state, team, nil
                    )

                    if state ~= 'Fakelag' then
                        team_items.defensive = create_defensive_items(state, team)
                    end

                    team_items.separator = menu.new(
                        ui.new_label, 'AA', 'Anti-aimbot angles', new_key('\n', 'separator')
                    )

                    team_items.send_to_another_team = menu.new(
                        ui.new_button, 'AA', 'Anti-aimbot angles', 'Send to another team', function()
                            local new_team = team == 'Counter-Terrorist'
                                and 'Terrorist' or 'Counter-Terrorist'

                            local target = get_items(
                                state, new_team
                            )

                            if target == nil then
                                return
                            end

                            set_values(target, get_values(team_items))
                            logging.success('sent to another team')
                        end
                    )

                    items[team] = team_items
                end

                builder[state] = items
            end

            antiaim.builder = builder
        end

        local features = { } do
            local avoid_backstab = { } do
                avoid_backstab.enabled = config_system.push(
                    'Features', 'avoid_backstab.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', 'Avoid backstab'
                    )
                )

                avoid_backstab.distance = config_system.push(
                    'Features', 'avoid_backstab.distance', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Distance', 'avoid_backstab'), 150, 320, 240, true, 'u'
                    )
                )

                avoid_backstab.separator = menu.new(
                    ui.new_label, 'AA', 'Anti-aimbot angles', '\n'
                )

                features.avoid_backstab = avoid_backstab
            end

            local backtrack_disruptor = { } do
                backtrack_disruptor.enabled = config_system.push(
                    'Features', 'backtrack_disruptor.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', 'Backtrack disruptor'
                    )
                )

                backtrack_disruptor.mode = config_system.push(
                    'Features', 'backtrack_disruptor.mode', menu.new(
                        ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Break when', 'backtrack_disruptor'), {
                            'Standing',
                            'Moving',
                            'Slow Walk',
                            'Air',
                            'Air-Crouch',
                            'Crouch',
                            'Move-Crouch'
                        }
                    )
                )

                backtrack_disruptor.delay_min = config_system.push(
                    'Features', 'backtrack_disruptor.delay_min', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Min delay', 'backtrack_disruptor'), 2, 64, 8, true, 't'
                    )
                )

                backtrack_disruptor.delay_max = config_system.push(
                    'Features', 'backtrack_disruptor.delay_max', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Max delay', 'backtrack_disruptor'), 2, 64, 24, true, 't'
                    )
                )

                features.backtrack_disruptor = backtrack_disruptor
            end

            local record_disruptor = { } do
                record_disruptor.enabled = config_system.push(
                    'Features', 'record_disruptor.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', 'Record disruptor'
                    )
                )

                record_disruptor.separator = menu.new(
                    ui.new_label, 'AA', 'Anti-aimbot angles', '\n'
                )

                features.record_disruptor = record_disruptor
            end

            local safe_head = { } do
                safe_head.enabled = config_system.push(
                    'Features', 'safe_head.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Safe head', 'safe_head')
                    )
                )

                safe_head.conditions = config_system.push(
                    'Features', 'safe_head.conditions', menu.new(
                        ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Conditions', 'safe_head'), {
                            'Standing',
                            'Crouch',
                            'Air crouch',
                            'Air crouch knife',
                            'Air crouch taser',
                            'Distance'
                        }
                    )
                )

                safe_head.e_spam_while_active = config_system.push(
                    'Features', 'safe_head.e_spam_while_active', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('E Spam while active', 'safe_head')
                    )
                )

                safe_head.separator = menu.new(
                    ui.new_label, 'AA', 'Anti-aimbot angles', '\n'
                )

                lock_unselection(safe_head.conditions)

                features.safe_head = safe_head
            end

            local warmup_round_end = { } do
                warmup_round_end.enabled = config_system.push(
                    'Features', 'warmup_round_end.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Warmup / Round end AA', 'warmup_round_end')
                    )
                )

                features.warmup_round_end = warmup_round_end
            end

            local flick_exploit = { } do
                flick_exploit.enabled = config_system.push(
                    'Features', 'flick_exploit.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Flick exploit', 'flick_exploit')
                    )
                )

                flick_exploit.states = config_system.push(
                    'Features', 'flick_exploit.states', menu.new(
                        ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('States', 'flick_exploit'), {
                            'Standing',
                            'Slow Walk',
                            'Air',
                            'Air-Crouch',
                            'Crouch',
                            'Move-Crouch'
                        }
                    )
                )

                flick_exploit.pitch = config_system.push(
                    'Features', 'flick_pitch', menu.new(
                        ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Pitch', 'flick_pitch'), {
                            'Off',
                            'Static',
                            'Sway',
                            'Switch',
                            'Random',
                            'Generated',
                            'Static Random'
                        }
                    )
                )

                flick_exploit.pitch_label_1 = menu.new(
                    ui.new_label, 'AA', 'Anti-aimbot angles', 'From'
                )

                flick_exploit.pitch_offset_1 = config_system.push(
                    'Features', 'flick_pitch_offset_1', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', 'flick_pitch_offset_1'), -89, 89, 0, true, '?'
                    )
                )

                flick_exploit.pitch_label_2 = menu.new(
                    ui.new_label, 'AA', 'Anti-aimbot angles', 'To'
                )

                flick_exploit.pitch_offset_2 = config_system.push(
                    'Features', 'flick_pitch_offset_2', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('\n', 'flick_pitch_offset_2'), -89, 89, 0, true, '?'
                    )
                )

                flick_exploit.pitch_speed = config_system.push(
                    'Features', 'flick_pitch_speed', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Speed', 'flick_pitch_speed'), -75, 75, 20, true, nil, 0.1
                    )
                )

                flick_exploit.separator = menu.new(
                    ui.new_label, 'AA', 'Anti-aimbot angles', '\n'
                )

                lock_unselection(flick_exploit.states, {
                    'Slow Walk',
                    'Crouch',
                    'Move-Crouch'
                })

                features.flick_exploit = flick_exploit
            end

            local predicted_at_targets = { } do
                predicted_at_targets.enabled = config_system.push(
                    'Features', 'predicted_at_targets.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Predicted at targets', 'predicted_at_targets')
                    )
                )

                features.predicted_at_targets = predicted_at_targets
            end

            antiaim.features = features
        end

        local hotkeys = { } do
            local edge_yaw = { } do
                edge_yaw.enabled = config_system.push(
                    'Hotkeys', 'edge_yaw.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Edge yaw', 'edge_yaw')
                    )
                )

                edge_yaw.hotkey = config_system.push(
                    'Hotkeys', 'edge_yaw.hotkey', menu.new(
                        ui.new_hotkey, 'AA', 'Anti-aimbot angles', new_key('Hotkey', 'edge_yaw'), true
                    )
                )

                edge_yaw.disablers = config_system.push(
                    'Hotkeys', 'edge_yaw.disablers', menu.new(
                        ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Disablers', 'edge_yaw'), {
                            'Standing',
                            'Moving',
                            'Slow Walk',
                            'Air',
                            'Crouched'
                        }
                    )
                )

                hotkeys.edge_yaw = edge_yaw
            end

            local freestanding = { } do
                freestanding.enabled = config_system.push(
                    'Hotkeys', 'freestanding.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Freestanding', 'freestanding')
                    )
                )

                freestanding.hotkey = config_system.push(
                    'Hotkeys', 'freestanding.hotkey', menu.new(
                        ui.new_hotkey, 'AA', 'Anti-aimbot angles', new_key('Hotkey', 'freestanding'), true
                    )
                )

                freestanding.disablers = config_system.push(
                    'Hotkeys', 'freestanding.disablers', menu.new(
                        ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Disablers', 'freestanding'), {
                            'Standing',
                            'Moving',
                            'Slow Walk',
                            'Air',
                            'Crouched'
                        }
                    )
                )

                freestanding.separator = menu.new(
                    ui.new_label, 'AA', 'Anti-aimbot angles', '\n'
                )

                hotkeys.freestanding = freestanding
            end

            local manual_yaw = { } do
                manual_yaw.enabled = config_system.push(
                    'Hotkeys', 'manual_yaw.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Manual Yaw', 'manual_yaw')
                    )
                )

                manual_yaw.options = config_system.push(
                    'Hotkeys', 'manual_yaw.options', menu.new(
                        ui.new_multiselect, 'AA', 'Anti-aimbot angles', new_key('Options', 'manual_yaw'), {
                            'Disable yaw modifiers',
                            'Freestanding body',
                        }
                    )
                )

                manual_yaw.reset_hotkey = config_system.push(
                    'Hotkeys', 'manual_yaw.reset_hotkey', menu.new(
                        ui.new_hotkey, 'AA', 'Anti-aimbot angles', new_key(
                            'Reset', 'manual_yaw'
                        )
                    )
                )

                manual_yaw.left_hotkey = config_system.push(
                    'Hotkeys', 'manual_yaw.left_hotkey', menu.new(
                        ui.new_hotkey, 'AA', 'Anti-aimbot angles', new_key(
                            'Left', 'manual_yaw'
                        )
                    )
                )

                manual_yaw.right_hotkey = config_system.push(
                    'Hotkeys', 'manual_yaw.right_hotkey', menu.new(
                        ui.new_hotkey, 'AA', 'Anti-aimbot angles', new_key(
                            'Right', 'manual_yaw'
                        )
                    )
                )

                manual_yaw.forward_hotkey = config_system.push(
                    'Hotkeys', 'manual_yaw.forward_hotkey', menu.new(
                        ui.new_hotkey, 'AA', 'Anti-aimbot angles', new_key(
                            'Forward', 'manual_yaw'
                        )
                    )
                )

                manual_yaw.backward_hotkey = config_system.push(
                    'Hotkeys', 'manual_yaw.backward_hotkey', menu.new(
                        ui.new_hotkey, 'AA', 'Anti-aimbot angles', new_key(
                            'Backward', 'manual_yaw'
                        )
                    )
                )

                manual_yaw.manual_arrows = config_system.push(
                    'Hotkeys', 'manual_yaw.manual_arrows', menu.new(
                        ui.new_combobox, 'AA', 'Anti-aimbot angles', new_key('Manual arrows', 'manual_yaw'), {
                            'Off',
                            'Classic',
                            'Modern',
                            'Teamskeet'
                        }
                    )
                )

                manual_yaw.arrows_offset = config_system.push(
                    'Hotkeys', 'manual_yaw.arrows_offset', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Arrows offset', 'manual_yaw'), 8, 128, 40, true, 'px'
                    )
                )

                manual_yaw.arrows_color = config_system.push(
                    'Hotkeys', 'manual_yaw.arrows_color', menu.new(
                        ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Arrows color', 'manual_yaw'), 175, 255, 55, 255
                    )
                )

                manual_yaw.desync_color = config_system.push(
                    'Hotkeys', 'manual_yaw.desync_color', menu.new(
                        ui.new_color_picker, 'AA', 'Anti-aimbot angles', new_key('Desync color', 'manual_yaw'), 35, 128, 255, 255
                    )
                )

                manual_yaw.separator = menu.new(
                    ui.new_label, 'AA', 'Anti-aimbot angles', '\n'
                )

                manual_yaw.reset_hotkey:set 'On hotkey'

                manual_yaw.left_hotkey:set 'Toggle'
                manual_yaw.right_hotkey:set 'Toggle'
                manual_yaw.forward_hotkey:set 'Toggle'
                manual_yaw.backward_hotkey:set 'Toggle'

                hotkeys.manual_yaw = manual_yaw
            end

            local roll_aa = { } do
                roll_aa.enabled = config_system.push(
                    'Hotkeys', 'roll_aa.enabled', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('Roll AA', 'roll_aa')
                    )
                )

                roll_aa.hotkey = config_system.push(
                    'Hotkeys', 'roll_aa.hotkey', menu.new(
                        ui.new_hotkey, 'AA', 'Anti-aimbot angles', new_key('Hotkey', 'roll_aa'), true
                    )
                )

                roll_aa.value = config_system.push(
                    'Hotkeys', 'roll_aa.value', menu.new(
                        ui.new_slider, 'AA', 'Anti-aimbot angles', new_key('Value', 'roll_aa'), -50, 50, 0, true, '?'
                    )
                )

                roll_aa.on_manual_yaw = config_system.push(
                    'Hotkeys', 'roll_aa.on_manual_yaw', menu.new(
                        ui.new_checkbox, 'AA', 'Anti-aimbot angles', new_key('On manual yaw', 'roll_aa')
                    )
                )

                roll_aa.separator = menu.new(
                    ui.new_label, 'AA', 'Anti-aimbot angles', '\n'
                )

                hotkeys.roll_aa = roll_aa
            end

            antiaim.hotkeys = hotkeys
        end

        local fakelag = { } do
            local HOTKEY_MODE = {
                [0] = 'Always on',
                [1] = 'On hotkey',
                [2] = 'Toggle',
                [3] = 'Off hotkey'
            }

            local function get_hotkey_value(_, mode, key)
                return HOTKEY_MODE[mode], key or 0
            end

            fakelag.enabled = config_system.push(
                'Features', 'fakelag.enabled', menu.new(
                    ui.new_checkbox, 'AA', 'Other', new_key('Enabled', 'fakelag')
                )
            )

            fakelag.hotkey = config_system.push(
                'Features', 'fakelag.hotkey', menu.new(
                    ui.new_hotkey, 'AA', 'Other', new_key('Hotkey', 'fakelag'), true
                )
            )

            fakelag.amount = config_system.push(
                'Features', 'fakelag.amount', menu.new(
                    ui.new_combobox, 'AA', 'Other', new_key('Amount', 'fakelag'), {
                        'Dynamic',
                        'Maximum',
                        'Fluctuate'
                    }
                )
            )

            fakelag.variance = config_system.push(
                'Features', 'fakelag.variance', menu.new(
                    ui.new_slider, 'AA', 'Other', new_key('Variance', 'fakelag'), 0, 100, 0, true, '%'
                )
            )

            fakelag.limit = config_system.push(
                'Features', 'fakelag.limit', menu.new(
                    ui.new_slider, 'AA', 'Other', new_key('Limit', 'fakelag'), 1, 15, 1, true, 't'
                )
            )

            fakelag.enabled:set(ui.get(software.antiaimbot.fake_lag.enabled[1]))
            fakelag.hotkey:set(get_hotkey_value(ui.get(software.antiaimbot.fake_lag.enabled[2])))

            fakelag.amount:set(ui.get(software.antiaimbot.fake_lag.amount))

            fakelag.variance:set(ui.get(software.antiaimbot.fake_lag.variance))
            fakelag.limit:set(ui.get(software.antiaimbot.fake_lag.limit))

            antiaim.fakelag = fakelag
        end

        resource.antiaim = antiaim
    end

    local render_we = {} do
        local function register_config_items(tab_name, prefix, node)
            if type(node) ~= "table" then
                return
            end

            if node.ref ~= nil and node.type ~= nil then
                if node.type ~= "button" and node.type ~= "label" and node.type ~= "unknown" then
                    config_system.push(tab_name, prefix, node)
                end

                return
            end

            for key, value in pairs(node) do
                if type(key) == "string" then
                    register_config_items(tab_name, prefix .. "." .. key, value)
                end
            end
        end

        local world_section = {} do
            world_section.fog = {
                override    = menu.new(ui.new_checkbox,     "AA", "Anti-aimbot angles", new_key("Fog override",       "we_fog")),
                color       = menu.new(ui.new_color_picker, "AA", "Anti-aimbot angles", new_key("Fog color",          "we_fog"), 120, 160, 80, 255),
                start       = menu.new(ui.new_slider,       "AA", "Anti-aimbot angles", new_key("Fog start",          "we_fog"), 0, 5000, 100),
                end_        = menu.new(ui.new_slider,       "AA", "Anti-aimbot angles", new_key("Fog end",            "we_fog"), 0, 10000, 1000),
                density     = menu.new(ui.new_slider,       "AA", "Anti-aimbot angles", new_key("Fog density",        "we_fog"), 0, 100, 50),
            }
            world_section.sunset = {
                override    = menu.new(ui.new_checkbox,     "AA", "Anti-aimbot angles", new_key("Sunset override",    "we_sun")),
                azimuth     = menu.new(ui.new_slider,       "AA", "Anti-aimbot angles", new_key("Azimuth",            "we_sun"), -180, 180, 0),
                elevation   = menu.new(ui.new_slider,       "AA", "Anti-aimbot angles", new_key("Elevation",          "we_sun"), -180, 180, 0),
            }
            world_section.skybox = {
                override      = menu.new(ui.new_checkbox,     "AA", "Anti-aimbot angles", new_key("Skybox override",   "we_sky")),
                color         = menu.new(ui.new_color_picker, "AA", "Anti-aimbot angles", new_key("Skybox color",      "we_sky"), 255, 255, 255, 255),
                list          = menu.new(ui.new_combobox,     "AA", "Anti-aimbot angles", new_key("Skybox",            "we_sky"),
                    "cs_tibet", "cs_baggage_skybox_", "embassy", "italy", "jungle", "office",
                    "sky_cs15_daylight01_hdr", "vertigoblue_hdr", "sky_cs15_daylight02_hdr",
                    "vertigo", "sky_day02_05_hdr", "nukeblank", "sky_venice",
                    "sky_cs15_daylight03_hdr", "sky_cs15_daylight04_hdr",
                    "sky_csgo_cloudy01", "sky_csgo_night02", "sky_csgo_night02b",
                    "sky_csgo_night_flat", "sky_dust", "vietnam"),
                remove_3d_sky = menu.new(ui.new_checkbox,     "AA", "Anti-aimbot angles", new_key("Remove 3D Sky",     "we_sky")),
            }
            world_section.bloom = {
                enable  = menu.new(ui.new_checkbox, "AA", "Anti-aimbot angles", new_key("Bloom",        "we_bloom")),
                scale   = menu.new(ui.new_slider,   "AA", "Anti-aimbot angles", new_key("Bloom scale",  "we_bloom"), -1, 500, -1, true, nil, 0.01),
            }
            world_section.exposure = {
                enable  = menu.new(ui.new_checkbox, "AA", "Anti-aimbot angles", new_key("Exposure",      "we_exp")),
                value   = menu.new(ui.new_slider,   "AA", "Anti-aimbot angles", new_key("Auto Exposure", "we_exp"), -1, 1000, -1),
            }
            world_section.model_ambient = {
                enable      = menu.new(ui.new_checkbox, "AA", "Anti-aimbot angles", new_key("Model ambient",    "we_ma")),
                brightness  = menu.new(ui.new_slider,   "AA", "Anti-aimbot angles", new_key("Model brightness", "we_ma"), 0, 1000, 0),
            }
            world_section.weather = {
                enable          = menu.new(ui.new_checkbox,  "AA", "Anti-aimbot angles", new_key("Weather",           "we_wx")),
                style           = menu.new(ui.new_combobox,  "AA", "Anti-aimbot angles", new_key("Weather type",      "we_wx"), "Rain 1", "Rain 2"),
                radius          = menu.new(ui.new_slider,    "AA", "Anti-aimbot angles", new_key("Weather radius",    "we_wx"), 0, 1500, 600),
                width           = menu.new(ui.new_slider,    "AA", "Anti-aimbot angles", new_key("Weather width",     "we_wx"), 0, 100, 50),
                modulate        = menu.new(ui.new_slider,    "AA", "Anti-aimbot angles", new_key("Weather modulate",  "we_wx"), 0, 100, 50),
                snow_particles  = menu.new(ui.new_slider,    "AA", "Anti-aimbot angles", new_key("Rain2 particles",   "we_wx"), 100, 1000, 300),
                snow_fall_speed = menu.new(ui.new_slider,    "AA", "Anti-aimbot angles", new_key("Rain2 fall speed",  "we_wx"), 1, 100, 15),
                snow_wind_scale = menu.new(ui.new_slider,    "AA", "Anti-aimbot angles", new_key("Rain2 wind scale",  "we_wx"), 0, 100, 35),
                wind_enable     = menu.new(ui.new_checkbox,  "AA", "Anti-aimbot angles", new_key("Custom wind",       "we_wx")),
                wind_direction  = menu.new(ui.new_slider,    "AA", "Anti-aimbot angles", new_key("Wind direction",    "we_wx"), 0, 360, 0),
                wind_speed      = menu.new(ui.new_slider,    "AA", "Anti-aimbot angles", new_key("Wind speed",        "we_wx"), 0, 500, 0),
            }
            world_section.bullet_tracers = {
                enable  = menu.new(ui.new_checkbox,     "AA", "Anti-aimbot angles", new_key("Bullet tracers",        "we_bt")),
                color   = menu.new(ui.new_color_picker, "AA", "Anti-aimbot angles", new_key("Tracer color",          "we_bt"), 255, 255, 255, 255),
                timer   = menu.new(ui.new_slider,       "AA", "Anti-aimbot angles", new_key("Bullet tracers timer",  "we_bt"), 1, 10, 2),
            }
            world_section.hitbox_on_hit = {
                enable  = menu.new(ui.new_checkbox,     "AA", "Anti-aimbot angles", new_key("Hitboxes on hit",   "we_hb")),
                color   = menu.new(ui.new_color_picker, "AA", "Anti-aimbot angles", new_key("Hitbox color",      "we_hb"), 255, 255, 255, 255),
                timer   = menu.new(ui.new_slider,       "AA", "Anti-aimbot angles", new_key("Hitboxes timer",    "we_hb"), 1, 10, 2),
            }
            world_section.ragdolls = {
                remove = menu.new(ui.new_checkbox, "AA", "Anti-aimbot angles", new_key("Remove ragdolls", "we_rg")),
            }
            render_we.world = world_section
        end

        local misc_section = {} do
            misc_section.unlock_cvars       = menu.new(ui.new_button,   "AA", "Anti-aimbot angles", new_key("Unlock Hidden ConVars",  "we_misc"))
            misc_section.viewmodel_in_scope = menu.new(ui.new_checkbox, "AA", "Anti-aimbot angles", new_key("Viewmodel in scope",     "we_misc"))
            misc_section.remove_sleeves     = menu.new(ui.new_checkbox, "AA", "Anti-aimbot angles", new_key("Remove sleeves",         "we_misc"))
            misc_section.thirdperson = {
                override    = menu.new(ui.new_checkbox, "AA", "Anti-aimbot angles", new_key("ThirdPerson",       "we_tp")),
                distance    = menu.new(ui.new_slider,   "AA", "Anti-aimbot angles", new_key("TP distance",       "we_tp"), 0, 300, 150),
            }
            misc_section.aspect_ratio = {
                override    = menu.new(ui.new_checkbox, "AA", "Anti-aimbot angles", new_key("Aspect ratio",      "we_ar")),
                value       = menu.new(ui.new_slider,   "AA", "Anti-aimbot angles", new_key("Aspect ratio value", "we_ar"), 0, 200, 100, true, nil, 0.01),
            }
            misc_section.viewmodel_changer = {
                override    = menu.new(ui.new_checkbox, "AA", "Anti-aimbot angles", new_key("Viewmodel changer",  "we_vm")),
                scope_hide  = menu.new(ui.new_checkbox, "AA", "Anti-aimbot angles", new_key("Scoped viewmodel",  "we_vm")),
                hand_move   = menu.new(ui.new_slider,   "AA", "Anti-aimbot angles", new_key("Hand movement",     "we_vm"), 0, 100, 100, true, "%"),
                storage = {
                    fov       = menu.new(ui.new_textbox, "AA", "Anti-aimbot angles", new_key("VM fov storage",       "we_vm")),
                    x         = menu.new(ui.new_textbox, "AA", "Anti-aimbot angles", new_key("VM x storage",         "we_vm")),
                    y         = menu.new(ui.new_textbox, "AA", "Anti-aimbot angles", new_key("VM y storage",         "we_vm")),
                    z         = menu.new(ui.new_textbox, "AA", "Anti-aimbot angles", new_key("VM z storage",         "we_vm")),
                    scope_fov = menu.new(ui.new_textbox, "AA", "Anti-aimbot angles", new_key("VM scope fov storage", "we_vm")),
                    scope_x   = menu.new(ui.new_textbox, "AA", "Anti-aimbot angles", new_key("VM scope x storage",   "we_vm")),
                    scope_y   = menu.new(ui.new_textbox, "AA", "Anti-aimbot angles", new_key("VM scope y storage",   "we_vm")),
                    scope_z   = menu.new(ui.new_textbox, "AA", "Anti-aimbot angles", new_key("VM scope z storage",   "we_vm")),
                    scope_custom = menu.new(ui.new_textbox, "AA", "Anti-aimbot angles", new_key("VM scope custom storage", "we_vm")),
                },
            }
            misc_section.custom_scope = {
                enable      = menu.new(ui.new_checkbox,     "AA", "Anti-aimbot angles", new_key("Custom scope",      "we_cs")),
                color       = menu.new(ui.new_color_picker, "AA", "Anti-aimbot angles", new_key("Scope color",       "we_cs"), 0, 0, 0, 255),
                scope_size  = menu.new(ui.new_slider,       "AA", "Anti-aimbot angles", new_key("Scope size",        "we_cs"), 0, 500, 190),
                offset      = menu.new(ui.new_slider,       "AA", "Anti-aimbot angles", new_key("Scope offset",      "we_cs"), 0, 500, 15),
                fade_time   = menu.new(ui.new_slider,       "AA", "Anti-aimbot angles", new_key("Scope anim speed",  "we_cs"), 3, 15, 9),
            }
            render_we.misc = misc_section
        end

        local panorama_section = {} do
            panorama_section.cleanup = menu.new(ui.new_multiselect, "AA", "Anti-aimbot angles", new_key("Main menu cleanup", "we_panorama"),
                'CS:GO Logo',
                'Remove News and Shop',
                'Server Browser',
                'Change background',
                'Remove stats button',
                'Remove watch button',
                'Remove sidebar',
                'Remove VAC panel',
                'Remove model in mainmenu'
            )
            render_we.panorama = panorama_section
        end

        register_config_items("World", "world", render_we.world)
        register_config_items("Panorama", "panorama", render_we.panorama)
        register_config_items("Miscellaneous", "misc", render_we.misc)

        resource.render_we = render_we
    end



    local config = { } do
        config.categories = new_selector_item(
            'AA', 'Anti-aimbot angles', '\n config.categories', {
                {
                    'Main', {
                        'Ragebot',
                        'Miscellaneous',
                        'Animations',
                        'Logging system',
                        'Automatic purchase'
                    }
                },

                {
                    'Anti-Aim', {
                        'Builder',
                        'Features',
                        'Hotkeys'
                    }
                },

                {
                    'Render', {
                        'World',
                        'Panorama',
                    }
                },
            }
        )

        config.list = menu.new(
            ui.new_listbox, 'AA', 'Anti-aimbot angles', '\n config.list', { }
        )

        config.input = menu.new(
            ui.new_textbox, 'AA', 'Anti-aimbot angles', '\n config.input', ''
        )

        config.load_with_skins = menu.new(
            ui.new_checkbox, 'AA', 'Anti-aimbot angles', 'Load with skins (cannot restore yours)'
        )

        config.autosave = menu.new(
            ui.new_checkbox, 'AA', 'Anti-aimbot angles', 'Autosave'
        )

        config.mark_default_button = menu.new(
            ui.new_button, 'AA', 'Anti-aimbot angles', 'Mark as default', nil
        )

        config.unmark_default_button = menu.new(
            ui.new_button, 'AA', 'Anti-aimbot angles', 'Unmark as default', nil
        )

        config.load_button = menu.new(
            ui.new_button, 'AA', 'Anti-aimbot angles', 'Load', nil
        )

        config.save_button = menu.new(
            ui.new_button, 'AA', 'Anti-aimbot angles', 'Save', nil
        )

        config.delete_button = menu.new(
            ui.new_button, 'AA', 'Anti-aimbot angles', 'Delete', nil
        )

        config.restore_button = menu.new(
            ui.new_button, 'AA', 'Other', 'Restore last config', nil
        )

        config.skin_list = menu.new(
            ui.new_listbox, 'AA', 'Other', '\n skin_config.list', { }
        )

        config.skin_input = menu.new(
            ui.new_textbox, 'AA', 'Other', '\n skin_config.input', ''
        )

        config.skin_load_button = menu.new(
            ui.new_button, 'AA', 'Other', 'Load skins', nil
        )

        config.skin_create_button = menu.new(
            ui.new_button, 'AA', 'Other', 'Create', nil
        )

        config.skin_create_saved_button = menu.new(
            ui.new_button, 'AA', 'Other', 'Create with saved skins', nil
        )

        config.skin_export_button = menu.new(
            ui.new_button, 'AA', 'Other', 'Export skins to clipboard', nil
        )

        config.skin_import_button = menu.new(
            ui.new_button, 'AA', 'Other', 'Import skins from clipboard', nil
        )

        config.share_all_active_button = menu.new(
            ui.new_button, 'AA', 'Anti-aimbot angles', 'Share all active configs', nil
        )

        config.export_button = menu.new(
            ui.new_button, 'AA', 'Anti-aimbot angles', 'Export to clipboard', nil
        )

        config.import_button = menu.new(
            ui.new_button, 'AA', 'Anti-aimbot angles', 'Import from clipboard', nil
        )


        lock_unselection(config.categories)

        resource.config = config
    end

    local scene do
        local function set_native_visible(ref, value)
            if ref == nil then
                return
            end

            ui.set_visible(ref, value)
        end

        local function set_antiaimbot_display(value)
            local items = software.antiaimbot.angles

            local pitch_value = ui.get(items.pitch[1])
            local yaw_value = ui.get(items.yaw[1])
            local body_yaw_value = ui.get(items.body_yaw[1])

            local force = not value

            set_native_visible(items.enabled, value)
            set_native_visible(items.pitch[1], value)

            if pitch_value == 'Custom' or force then
                set_native_visible(items.pitch[2], value)
            end

            set_native_visible(items.yaw_base, value)
            set_native_visible(items.yaw[1], value)

            if yaw_value ~= 'Off' or force then
                local yaw_jitter_value = ui.get(items.yaw_jitter[1])

                set_native_visible(items.yaw[2], value)
                set_native_visible(items.yaw_jitter[1], value)

                if yaw_jitter_value ~= 'Off' or force then
                    set_native_visible(items.yaw_jitter[2], value)
                end
            end

            set_native_visible(items.body_yaw[1], value)

            if body_yaw_value ~= 'Off' or force then
                if body_yaw_value ~= 'Opposite' or force then
                    set_native_visible(items.body_yaw[2], value)
                end

                set_native_visible(items.freestanding_body_yaw, value)
            end

            set_native_visible(items.edge_yaw, value)

            set_native_visible(items.freestanding[1], value)
            set_native_visible(items.freestanding[2], value)

            set_native_visible(items.roll, value)
        end

        local function set_fakelag_display(value)
            local items = software.antiaimbot.fake_lag

            set_native_visible(items.enabled[1], value)
            set_native_visible(items.enabled[2], value)

            set_native_visible(items.amount, value)
            set_native_visible(items.limit, value)
            set_native_visible(items.variance, value)
        end

        local function set_other_display(value)
            local items = software.antiaimbot.other

            set_native_visible(items.slow_motion[1], value)
            set_native_visible(items.slow_motion[2], value)

            set_native_visible(items.leg_movement, value)

            set_native_visible(items.on_shot_antiaim[1], value)
            set_native_visible(items.on_shot_antiaim[2], value)

            set_native_visible(items.fake_peek[1], value)
            set_native_visible(items.fake_peek[2], value)
        end

        local function update_builder_items(items)
            local angles = items.angles
            local defensive = items.defensive

            if items.separator ~= nil then
                menu_logic.set(items.separator, true)
            end

            if items.send_to_another_team ~= nil then
                menu_logic.set(items.send_to_another_team, true)
            end

            if angles ~= nil then
                if angles.enabled ~= nil then
                    menu_logic.set(angles.enabled, true)

                    if not angles.enabled:get() then
                        return
                    end
                end

                if angles.bomb_e_fix ~= nil then
                    menu_logic.set(angles.bomb_e_fix, true)
                end

                if angles.yaw_base ~= nil then
                    menu_logic.set(angles.yaw_base, true)
                end

                if angles.yaw_left ~= nil and angles.yaw_right ~= nil then
                    local is_general_yaw = true

                    if angles.yaw_direction ~= nil then
                        local dir = angles.yaw_direction:get()
                        menu_logic.set(angles.yaw_direction, true)

                        if dir ~= 'General' then
                            is_general_yaw = false
                        end

                        local item_enable = angles['enabled_dir_' .. dir]

                        if item_enable == nil then
                            goto continue
                        end

                        menu_logic.set(item_enable, true)

                        if not item_enable:get() then
                            goto continue
                        end

                        local item_left = angles['yaw_left_dir_' .. dir]
                        local item_right = angles['yaw_right_dir_' .. dir]

                        if item_left ~= nil then
                            menu_logic.set(item_left, true)
                        end

                        if item_right ~= nil then
                            menu_logic.set(item_right, true)
                        end

                        ::continue::
                    end

                    if is_general_yaw then
                        menu_logic.set(angles.yaw_left, true)
                        menu_logic.set(angles.yaw_right, true)
                        menu_logic.set(angles.yaw_random, true)
                    end

                    menu_logic.set(angles.yaw_jitter, true)

                    local yaw_jitter = angles.yaw_jitter:get()
                    local is_dynamic_jitter = (
                        yaw_jitter == 'Sway'
                        or yaw_jitter == 'Randomized'
                        or yaw_jitter == 'Center Flick'
                        or yaw_jitter == 'Offset Flick'
                    )

                    if yaw_jitter ~= 'Off' and not is_dynamic_jitter then
                        menu_logic.set(angles.jitter_offset, true)
                        menu_logic.set(angles.jitter_random, true)
                    end

                    if is_dynamic_jitter then
                        menu_logic.set(angles.jitter_min, true)
                        menu_logic.set(angles.jitter_max, true)
                        menu_logic.set(angles.jitter_random, true)
                        menu_logic.set(angles.jitter_delay, true)
                    end

                    if yaw_jitter == 'Sway' then
                        menu_logic.set(angles.jitter_speed, true)
                    end
                end

                menu_logic.set(angles.body_yaw, true)

                if angles.body_yaw:get() ~= 'Off' then
                    if angles.body_yaw:get() ~= 'Opposite' then
                        menu_logic.set(angles.body_yaw_offset, true)
                    end

                    local is_jitter = (
                        angles.body_yaw:get() == 'Jitter'
                        or angles.body_yaw:get() == 'Jitter Random'
                    )

                    if is_jitter then
                        menu_logic.set(angles.delay_from, true)
                        menu_logic.set(angles.delay_to, true)
                        menu_logic.set(angles.delay_chaos, true)
                    else
                        menu_logic.set(angles.freestanding_body_yaw, true)
                    end
                end
            end


            if items.separator_1 ~= nil then
                menu_logic.set(items.separator_1, true)
            end

            if defensive ~= nil then
                menu_logic.set(defensive.enabled, true)

                if defensive.enabled:get() then
                    menu_logic.set(defensive.triggers, true)

                    if defensive.triggers:get('Hotkey') then
                        menu_logic.set(defensive.trigger_hotkey, true)
                    end

                    menu_logic.set(defensive.trigger_from, true)
                    menu_logic.set(defensive.trigger_to, true)
                    menu_logic.set(defensive.trigger_duration, true)
                    menu_logic.set(defensive.pitch, true)

                    if defensive.pitch:get() ~= 'Off' then
                        menu_logic.set(defensive.pitch_offset_1, true)

                        if defensive.pitch:get() ~= 'Static' then
                            menu_logic.set(defensive.pitch_label_1, true)
                            menu_logic.set(defensive.pitch_label_2, true)

                            menu_logic.set(defensive.pitch_offset_2, true)
                        end

                        if defensive.pitch:get() == 'Sway' or defensive.pitch:get() == 'Spin' or defensive.pitch:get() == 'Cycling' or defensive.pitch:get() == 'Jitter' then
                            menu_logic.set(defensive.pitch_speed, true)
                        end
                    end

                    menu_logic.set(defensive.yaw, true)

                    if defensive.yaw:get() ~= 'Off' then
                        local yaw = defensive.yaw:get()

                        local have_limits = (
                            yaw == 'Sway' or
                            yaw == 'Distortion' or
                            yaw == 'Random' or
                            yaw == 'Left/Right' or
                            yaw == 'Generated' or
                            yaw == 'Static Random'
                        )

                        local have_speed = (
                            yaw == 'Sway' or
                            yaw == 'Distortion'
                        )

                        if yaw == 'X-Way' then
                            menu_logic.set(defensive.ways_count, true)
                            menu_logic.set(defensive.ways_custom, true)

                            if defensive.ways_custom:get() then
                                local ways_count = defensive.ways_count:get()
                                menu_logic.set(defensive.ways_count, true)

                                for i = 1, ways_count do
                                    menu_logic.set(defensive['way_' .. i], true)
                                end
                            else
                                menu_logic.set(defensive.yaw_offset, true)
                            end

                            menu_logic.set(defensive.ways_auto_body_yaw, true)
                        else
                            if have_limits then
                                menu_logic.set(defensive.yaw_left, true)
                                menu_logic.set(defensive.yaw_right, true)
                            else
                                menu_logic.set(defensive.yaw_offset, true)
                            end

                            if have_speed then
                                menu_logic.set(defensive.yaw_speed, true)
                            end
                        end
                    end

                    menu_logic.set(defensive.body_yaw, true)

                    if defensive.body_yaw:get() ~= 'Off' then
                        if defensive.body_yaw:get() ~= 'Opposite' then
                            menu_logic.set(defensive.body_yaw_offset, true)
                        end

                        local is_jitter = (
                            defensive.body_yaw:get() == 'Jitter'
                            or defensive.body_yaw:get() == 'Jitter Random'
                        )

                        if not is_jitter then
                            menu_logic.set(defensive.freestanding_body_yaw, true)
                        end
                    end
                end
            end
        end

        local function force_update_scene()
            menu_logic.set(general.script_name, true)

            local category = general.category:get()
            menu_logic.set(general.category, true)

            -- Ragebot
            if category == 0 then
                local ref = resource.main.ragebot

                local is_force_body_conditions = ref.force_body_conditions.enabled:get() do
                    menu_logic.set(ref.force_body_conditions.enabled, true)

                    if not is_force_body_conditions then
                        goto continue
                    end

                    menu_logic.set(ref.force_body_conditions.separator, true)

                    menu_logic.set(ref.force_body_conditions.weapons, true)
                    menu_logic.set(ref.force_body_conditions.conditions, true)

                    if ref.force_body_conditions.conditions:get 'Max misses' then
                        menu_logic.set(ref.force_body_conditions.max_misses, true)

                        if ref.force_body_conditions.weapons:get 'Scout' then
                            menu_logic.set(ref.force_body_conditions.scout_damage, true)
                        end
                    end

                    menu_logic.set(ref.force_body_conditions.disabler, true)

                    ::continue::
                end

                local is_force_lethal = ref.force_lethal.enabled:get() do
                    menu_logic.set(ref.force_lethal.enabled, true)

                    if not is_force_lethal then
                        goto continue
                    end

                    menu_logic.set(ref.force_lethal.mode, true)

                    local weapons = ref.force_lethal.weapons:get()
                    menu_logic.set(ref.force_lethal.weapons, true)

                    for i = 1, #weapons do
                        local weapon = weapons[i]

                        local items = ref.force_lethal[weapon]

                        if items ~= nil then
                            menu_logic.set(items.hitchance, true)
                        end
                    end

                    menu_logic.set(ref.force_lethal.separator, true)

                    ::continue::
                end


                local is_hitchance = ref.hitchance.enabled:get() do
                    menu_logic.set(ref.hitchance.enabled, true)

                    if not is_hitchance then
                        goto continue
                    end

                    menu_logic.set(ref.hitchance.separator, true)

                    local weapon = ref.hitchance.weapon:get()
                    menu_logic.set(ref.hitchance.weapon, true)

                    local items = ref.hitchance[weapon]

                    if items == nil then
                        goto continue
                    end

                    local options = items.options:get()
                    menu_logic.set(items.options, true)

                    for i = 1, #options do
                        local option = options[i]
                        local option_items = items[option]

                        if option_items ~= nil then
                            menu_logic.set(option_items.value, true)

                            if option_items.distance ~= nil then
                                menu_logic.set(option_items.distance, true)
                            end
                        end
                    end

                    if items.options:get 'Hotkey' then
                        menu_logic.set(ref.hitchance.hotkey, true)
                        menu_logic.set(ref.hitchance.indicator_text, true)
                    end

                    ::continue::
                end

                local is_peek_assist = ref.peek_assist.enabled:get() do
                    menu_logic.set(ref.peek_assist.enabled, true)

                    if is_peek_assist then
                        menu_logic.set(ref.peek_assist.limit, true)
                        menu_logic.set(ref.peek_assist.weapons, true)
                        menu_logic.set(ref.peek_assist.separator, true)
                    end
                end

                local is_ai_peek = ref.ai_peek.enabled:get() do
                    menu_logic.set(ref.ai_peek.enabled, true)
                    menu_logic.set(ref.ai_peek.hotkey, false)

                    if is_ai_peek then
                        menu_logic.set(ref.ai_peek.min_damage_label, true)
                        menu_logic.set(ref.ai_peek.min_damage_override, true)
                        menu_logic.set(ref.ai_peek.scan_all, true)
                        menu_logic.set(ref.ai_peek.live_scan, true)
                        menu_logic.set(ref.ai_peek.distance, true)
                        menu_logic.set(ref.ai_peek.separation, true)
                        menu_logic.set(ref.ai_peek.count, true)
                        menu_logic.set(ref.ai_peek.prediction, true)
                        menu_logic.set(ref.ai_peek.hitboxes, true)
                        menu_logic.set(ref.ai_peek.debug, true)
                        menu_logic.set(ref.ai_peek.separator, true)
                    end
                end

                local is_auto_whitelist_broken_lc = ref.auto_whitelist_broken_lc.enabled:get() do
                    menu_logic.set(ref.auto_whitelist_broken_lc.enabled, true)
                    menu_logic.set(ref.auto_whitelist_broken_lc.actions, is_auto_whitelist_broken_lc)
                    menu_logic.set(ref.auto_whitelist_broken_lc.separator, is_auto_whitelist_broken_lc)
                end

                if resource.main.dormant ~= nil then
                    local dormant = resource.main.dormant
                    menu_logic.set(dormant.enabled, true)

                    if dormant.enabled:get() then
                        menu_logic.set(dormant.hotkey, true)
                        menu_logic.set(dormant.minimum_damage, true)
                        menu_logic.set(dormant.indicator, true)
                    end
                end

                menu_logic.set(ref.allow_duck_on_fd.enabled, true)
                menu_logic.set(ref.unsafe_recharge.enabled, true)
                menu_logic.set(ref.hideshots_fix.enabled, true)
            end

            -- Miscellaneous
            if category == 1 then
                local ref = resource.main.miscellaneous


                menu_logic.set(ref.fast_ladder.enabled, true)
                menu_logic.set(ref.air_stop_shift.enabled, true)
                menu_logic.set(ref.console_filter.enabled, true)
                menu_logic.set(ref.sync_ragebot_hotkeys.enabled, true)
                menu_logic.set(ref.reveal_enemy_team_chat.enabled, true)
                menu_logic.set(ref.clantag.enabled, true)

                if ref.clantag.enabled:get() then
                    menu_logic.set(ref.clantag.separator, true)
                end

                local render_ref = resource.render_we.misc

                menu_logic.set(render_ref.unlock_cvars, true)
                menu_logic.set(render_ref.viewmodel_in_scope, true)
                menu_logic.set(render_ref.remove_sleeves, true)

                menu_logic.set(render_ref.thirdperson.override, true)
                if render_ref.thirdperson.override:get() then
                    menu_logic.set(render_ref.thirdperson.distance, true)
                end

                menu_logic.set(render_ref.aspect_ratio.override, true)
                if render_ref.aspect_ratio.override:get() then
                    menu_logic.set(render_ref.aspect_ratio.value, true)
                end

                menu_logic.set(render_ref.viewmodel_changer.override, true)
                if render_ref.viewmodel_changer.override:get() then
                    menu_logic.set(render_ref.viewmodel_changer.scope_hide, true)
                    menu_logic.set(render_ref.viewmodel_changer.hand_move, true)
                end

                menu_logic.set(render_ref.custom_scope.enable, true)
                if render_ref.custom_scope.enable:get() then
                    menu_logic.set(render_ref.custom_scope.color, true)
                    menu_logic.set(render_ref.custom_scope.scope_size, true)
                    menu_logic.set(render_ref.custom_scope.offset, true)
                    menu_logic.set(render_ref.custom_scope.fade_time, true)
                end
            end

            -- Animations
            if category == 2 then
                local ref = resource.main.animations

                menu_logic.set(ref.air_legs, true)

                if ref.air_legs:get() == 'Static' then
                    menu_logic.set(ref.air_legs_weight, true)
                end

                menu_logic.set(ref.ground_legs, true)

                local has_offset = (
                    ref.ground_legs:get() == 'Jitter'
                    or ref.ground_legs:get() == 'Pacan4ik'
                )

                if has_offset then
                    menu_logic.set(ref.legs_offset_1, true)
                    menu_logic.set(ref.legs_offset_2, true)

                    if ref.ground_legs:get() == 'Jitter' then
                        menu_logic.set(ref.legs_jitter_time, true)
                    end
                end

                menu_logic.set(ref.options, true)

                if ref.options:get 'Move lean' then
                    menu_logic.set(ref.move_lean, true)
                end
            end

            -- Logging system
            if category == 3 then
                local ref = resource.main.logging_system

                menu_logic.set(ref.enabled, true)

                if not ref.enabled:get() then
                    goto continue
                end

                menu_logic.set(ref.events, true)
                menu_logic.set(ref.output, true)

                if ref.output:get 'Events' then
                    menu_logic.set(ref.events_font, true)
                end

                if ref.output:get 'Under crosshair' then
                    menu_logic.set(ref.offset_y, true)
                    menu_logic.set(ref.duration, true)
                end

                menu_logic.set(ref.console_text_style, true)
                menu_logic.set(ref.crosshair_text_style, true)

                local is_colors_visible = (
                    ref.console_text_style:get() == 'Pasthetic' or
                    ref.crosshair_text_style:get() == 'Pasthetic'
                )

                if is_colors_visible then
                    for i = 1, #ref.main_color_list do
                        local name = ref.main_color_list[i][1]

                        menu_logic.set(ref[name].label, true)
                        menu_logic.set(ref[name].color, true)
                    end

                    menu_logic.set(ref.color_separator, true)

                    for i = 1, #ref.miss_color_list do
                        local name = ref.miss_color_list[i][1]

                        menu_logic.set(ref[name].label, true)
                        menu_logic.set(ref[name].color, true)
                    end
                end

                ::continue::
            end

            -- Automatic purchase
            if category == 4 then
                local ref = resource.main.automatic_purchase

                menu_logic.set(ref.enabled, true)

                if not ref.enabled:get() then
                    goto continue
                end

                menu_logic.set(ref.primary, true)

                if ref.primary:get() == 'AWP' then
                    menu_logic.set(ref.alternative, true)
                end

                menu_logic.set(ref.secondary, true)
                menu_logic.set(ref.equipment, true)

                menu_logic.set(ref.ignore_pistol_round, true)
                menu_logic.set(ref.only_16k, true)

                ::continue::
            end

            -- Builder
            if category == 6 then
                local builder do
                    local ref = resource.antiaim.builder

                    local state = ref.state:get()
                    menu_logic.set(ref.state, true)

                    local items = ref[state]

                    if items == nil then
                        goto continue
                    end

                    local team = items.team:get()
                    menu_logic.set(items.team, true)

                    local team_items = items[team]

                    if team_items == nil then
                        goto continue
                    end

                    update_builder_items(team_items)

                    ::continue::
                end
            end

            -- Features
            if category == 7 then
                local ref = resource.antiaim.features

                local is_avoid_backstab = ref.avoid_backstab.enabled:get() do
                    menu_logic.set(ref.avoid_backstab.enabled, true)

                    if not is_avoid_backstab then
                        goto continue
                    end

                    menu_logic.set(ref.avoid_backstab.distance, true)
                    menu_logic.set(ref.avoid_backstab.separator, true)

                    ::continue::
                end

                local is_backtrack_disruptor = ref.backtrack_disruptor.enabled:get() do
                    menu_logic.set(ref.backtrack_disruptor.enabled, true)
                end

                local is_record_disruptor = ref.record_disruptor.enabled:get() do
                    menu_logic.set(ref.record_disruptor.enabled, true)

                    if not is_record_disruptor then
                        goto continue
                    end

                    menu_logic.set(ref.record_disruptor.separator, true)

                    ::continue::
                end

                local is_safe_head = ref.safe_head.enabled:get() do
                    menu_logic.set(ref.safe_head.enabled, true)

                    if not is_safe_head then
                        goto continue
                    end

                    menu_logic.set(ref.safe_head.conditions, true)
                    menu_logic.set(ref.safe_head.e_spam_while_active, true)

                    menu_logic.set(ref.safe_head.separator, true)

                    ::continue::
                end

                menu_logic.set(ref.warmup_round_end.enabled, true)

                local is_flick_exploit = ref.flick_exploit.enabled:get() do
                    menu_logic.set(ref.flick_exploit.enabled, true)

                    if not is_flick_exploit then
                        goto continue
                    end

                    menu_logic.set(ref.flick_exploit.states, true)
                    menu_logic.set(ref.flick_exploit.pitch, true)

                    if ref.flick_exploit.pitch:get() ~= 'Off' then
                        menu_logic.set(ref.flick_exploit.pitch_offset_1, true)

                        if ref.flick_exploit.pitch:get() ~= 'Static' then
                            menu_logic.set(ref.flick_exploit.pitch_label_1, true)
                            menu_logic.set(ref.flick_exploit.pitch_label_2, true)

                            menu_logic.set(ref.flick_exploit.pitch_offset_2, true)
                        end

                        if ref.flick_exploit.pitch:get() == 'Sway' then
                            menu_logic.set(ref.flick_exploit.pitch_speed, true)
                        end
                    end

                    menu_logic.set(ref.flick_exploit.separator, true)

                    ::continue::
                end

                local is_predicted_at_targets = ref.predicted_at_targets.enabled:get() do
                    menu_logic.set(ref.predicted_at_targets.enabled, true)

                    if not is_predicted_at_targets then
                        goto continue
                    end

                    ::continue::
                end

                local fakelag do
                    local ref = resource.antiaim.fakelag

                    menu_logic.set(ref.enabled, true)
                    menu_logic.set(ref.hotkey, true)

                    menu_logic.set(ref.amount, true)

                    menu_logic.set(ref.variance, true)
                    menu_logic.set(ref.limit, true)
                end
            end

            -- Hotkeys
            if category == 8 then
                local ref = resource.antiaim.hotkeys

                local is_edge_yaw = ref.edge_yaw.enabled:get() do
                    menu_logic.set(ref.edge_yaw.enabled, true)
                    menu_logic.set(ref.edge_yaw.hotkey, true)

                    if not is_edge_yaw then
                        goto continue
                    end

                    menu_logic.set(ref.edge_yaw.disablers, true)

                    ::continue::
                end

                local is_freestanding = ref.freestanding.enabled:get() do
                    menu_logic.set(ref.freestanding.enabled, true)
                    menu_logic.set(ref.freestanding.hotkey, true)

                    if not is_freestanding then
                        goto continue
                    end

                    menu_logic.set(ref.freestanding.options, true)
                    menu_logic.set(ref.freestanding.disablers, true)

                    menu_logic.set(ref.freestanding.separator, true)

                    ::continue::
                end

                local is_manual_yaw = ref.manual_yaw.enabled:get() do
                    menu_logic.set(ref.manual_yaw.enabled, true)

                    if not is_manual_yaw then
                        goto continue
                    end

                    menu_logic.set(ref.manual_yaw.options, true)

                    menu_logic.set(ref.manual_yaw.left_hotkey, true)
                    menu_logic.set(ref.manual_yaw.right_hotkey, true)
                    menu_logic.set(ref.manual_yaw.forward_hotkey, true)
                    menu_logic.set(ref.manual_yaw.backward_hotkey, true)
                    menu_logic.set(ref.manual_yaw.reset_hotkey, true)

                    menu_logic.set(ref.manual_yaw.manual_arrows, true)

                    if ref.manual_yaw.manual_arrows:get() ~= 'Off' then
                        menu_logic.set(ref.manual_yaw.arrows_color, true)
                        menu_logic.set(ref.manual_yaw.arrows_offset, true)
                    end

                    if ref.manual_yaw.manual_arrows:get() == 'Teamskeet' then
                        menu_logic.set(ref.manual_yaw.desync_color, true)
                    end

                    menu_logic.set(ref.manual_yaw.separator, true)

                    ::continue::
                end

                local is_roll_aa = ref.roll_aa.enabled:get() do
                    menu_logic.set(ref.roll_aa.enabled, true)
                    menu_logic.set(ref.roll_aa.hotkey, true)

                    if not is_roll_aa then
                        goto continue
                    end

                    menu_logic.set(ref.roll_aa.value, true)
                    menu_logic.set(ref.roll_aa.on_manual_yaw, true)

                    menu_logic.set(ref.roll_aa.separator, true)

                    ::continue::
                end
            end





            -- Render - World
            if category == 10 then
                local ref = resource.render_we.world

                menu_logic.set(ref.fog.override, true)
                if ref.fog.override:get() then
                    menu_logic.set(ref.fog.color, true)
                    menu_logic.set(ref.fog.start, true)
                    menu_logic.set(ref.fog.end_, true)
                    menu_logic.set(ref.fog.density, true)
                end

                menu_logic.set(ref.sunset.override, true)
                if ref.sunset.override:get() then
                    menu_logic.set(ref.sunset.azimuth, true)
                    menu_logic.set(ref.sunset.elevation, true)
                end

                menu_logic.set(ref.skybox.override, true)
                if ref.skybox.override:get() then
                    menu_logic.set(ref.skybox.color, true)
                    menu_logic.set(ref.skybox.list, true)
                    menu_logic.set(ref.skybox.remove_3d_sky, true)
                end

                menu_logic.set(ref.bloom.enable, true)
                if ref.bloom.enable:get() then
                    menu_logic.set(ref.bloom.scale, true)
                end

                menu_logic.set(ref.exposure.enable, true)
                if ref.exposure.enable:get() then
                    menu_logic.set(ref.exposure.value, true)
                end

                menu_logic.set(ref.model_ambient.enable, true)
                if ref.model_ambient.enable:get() then
                    menu_logic.set(ref.model_ambient.brightness, true)
                end

                menu_logic.set(ref.weather.enable, true)
                if ref.weather.enable:get() then
                    menu_logic.set(ref.weather.style, true)
                    menu_logic.set(ref.weather.radius, true)
                    menu_logic.set(ref.weather.width, true)
                    menu_logic.set(ref.weather.modulate, true)

                    if ref.weather.style:get() == "Rain 2" then
                        menu_logic.set(ref.weather.snow_particles, true)
                        menu_logic.set(ref.weather.snow_fall_speed, true)
                        menu_logic.set(ref.weather.snow_wind_scale, true)
                    end

                    menu_logic.set(ref.weather.wind_enable, true)
                    if ref.weather.wind_enable:get() then
                        menu_logic.set(ref.weather.wind_direction, true)
                        menu_logic.set(ref.weather.wind_speed, true)
                    end
                end

                menu_logic.set(ref.bullet_tracers.enable, true)
                if ref.bullet_tracers.enable:get() then
                    menu_logic.set(ref.bullet_tracers.color, true)
                    menu_logic.set(ref.bullet_tracers.timer, true)
                end

                menu_logic.set(ref.hitbox_on_hit.enable, true)
                if ref.hitbox_on_hit.enable:get() then
                    menu_logic.set(ref.hitbox_on_hit.color, true)
                    menu_logic.set(ref.hitbox_on_hit.timer, true)
                end

                menu_logic.set(ref.ragdolls.remove, true)

            end
            -- Render - Panorama
            if category == 11 then
                local ref = resource.render_we.panorama

                menu_logic.set(ref.cleanup, true)
            end
            -- Configurations
            if category == 13 then
                menu_logic.set(config.categories, true)

                menu_logic.set(config.list, true)
                menu_logic.set(config.input, true)

                menu_logic.set(config.autosave, true)
                menu_logic.set(config.mark_default_button, not (config.is_selected_default ~= nil and config.is_selected_default()))
                menu_logic.set(config.unmark_default_button, config.is_selected_default ~= nil and config.is_selected_default())
                menu_logic.set(config.load_button, true)
                menu_logic.set(config.save_button, true)
                menu_logic.set(config.delete_button, true)
                menu_logic.set(config.restore_button, config.has_deleted_configs ~= nil and config.has_deleted_configs())
                menu_logic.set(config.skin_list, true)
                menu_logic.set(config.skin_input, true)
                menu_logic.set(config.skin_load_button, true)
                menu_logic.set(config.skin_create_button, not (config.has_pending_skin_cache ~= nil and config.has_pending_skin_cache()))
                menu_logic.set(config.skin_create_saved_button, config.has_pending_skin_cache ~= nil and config.has_pending_skin_cache())
                menu_logic.set(config.skin_export_button, true)
                menu_logic.set(config.skin_import_button, true)
                menu_logic.set(config.share_all_active_button, true)
                menu_logic.set(config.import_button, true)
                menu_logic.set(config.export_button, true)

            end
        end

        local function on_shutdown()
            set_antiaimbot_display(true)
            set_fakelag_display(true)
            set_other_display(true)
        end

        local last_menu_error
        local visibility_update_count = 0

        local function update_script_menu_visibility(reason, ...)
            visibility_update_count = visibility_update_count + 1
            local category_before = 'nil'

            if resource.general ~= nil and resource.general.category ~= nil then
                local ok_category, category = pcall(resource.general.category.get, resource.general.category)
                category_before = ok_category and tostring(category) or ('error:' .. tostring(category))
            end

            if is_debug_enabled() and type(ui_debug.visibility_begin) == 'function' then
                ui_debug:visibility_begin(reason, visibility_update_count, category_before)
            end

            local ok, result = pcall(force_update_scene, ...)

            if not ok then
                result = tostring(result)

                if result ~= last_menu_error then
                    logging.error(string.format('menu %s error: %s', reason, result))
                    last_menu_error = result
                end
            elseif is_debug_enabled()
                and type(ui_debug.visibility_queued) == 'function'
                and type(menu_logic.debug_snapshot) == 'function'
            then
                local snapshot = menu_logic.debug_snapshot()
                ui_debug:visibility_queued(reason, visibility_update_count, snapshot)
            end

            return ok
        end

        local function on_paint_ui()
            local category = resource.general.category:get()
            local is_hotkeys = category == 8

            set_antiaimbot_display(false)
            set_fakelag_display(false)
            set_other_display(is_hotkeys)
        end

        local logic_events = menu_logic.get_event_bus() do
            logic_events.update:set(
                function(...)
                    update_script_menu_visibility('update', ...)
                end
            )

            update_script_menu_visibility('init')
            if is_debug_enabled()
                and type(ui_debug.before_init_force_update) == 'function'
                and type(menu_logic.debug_snapshot) == 'function'
            then
                local snapshot = menu_logic.debug_snapshot()
                ui_debug:before_init_force_update(snapshot)
            end
            menu_logic.force_update()
        end

        client.set_event_callback('shutdown', on_shutdown)
        client.set_event_callback('paint_ui', on_paint_ui)
    end
end

    return resource
end

function M.health(ctx)
    return ctx ~= nil and ctx.resource ~= nil
end

return M
