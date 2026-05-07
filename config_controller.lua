local M = {}

function M.start(deps)
    local resource = assert(deps.resource, 'config_controller: resource dependency is required')
    local pasthetic_constants = assert(deps.constants, 'config_controller: constants dependency is required')
    local localdb = assert(deps.localdb, 'config_controller: localdb dependency is required')
    local database = assert(deps.database, 'config_controller: database dependency is required')
    local logging = assert(deps.logging, 'config_controller: logging dependency is required')
    local config_system = assert(deps.config_system, 'config_controller: config_system dependency is required')
    local windows = assert(deps.windows, 'config_controller: windows dependency is required')
    local menu = assert(deps.menu, 'config_controller: menu dependency is required')
    local menu_logic = assert(deps.menu_logic, 'config_controller: menu_logic dependency is required')
    local clipboard = assert(deps.clipboard, 'config_controller: clipboard dependency is required')
    local utils = assert(deps.utils, 'config_controller: utils dependency is required')
    local client = assert(deps.client, 'config_controller: client dependency is required')
    local ui = assert(deps.ui, 'config_controller: ui dependency is required')
    local contains = assert(deps.contains, 'config_controller: contains dependency is required')
local config do
    local ref = resource.config

    local DB_NAME = pasthetic_constants.DB.CONFIG
    local DB_DEFAULT = { }

    local db_data = (
        localdb['config']
        or database.read(DB_NAME)
        or database.read(pasthetic_constants.LEGACY_DB.CONFIG)
        or DB_DEFAULT
    )

    local config_data = { }
    local config_list = { }
    local deleted_configs = { }
    local autosave_token = 0
    local autosave_suspended = false
    local skin_config_data = localdb['skin_configs']
        or database.read(pasthetic_constants.DB.SKIN_CONFIGS)
        or database.read(pasthetic_constants.LEGACY_DB.SKIN_CONFIGS)
        or { }
    local skin_config_list = { }
    local active_skin_config_name = nil
    local last_skin_config_name = localdb['last_skin_config_name']
    local pending_skin_cache = nil
    local skin_import_suspended = false
    local gamesense_default_config = localdb['gamesense_default_config']

    if type(skin_config_data) ~= 'table' then
        skin_config_data = { }
    end

    if type(last_skin_config_name) ~= 'string' or last_skin_config_name == '' then
        last_skin_config_name = nil
    end

    if type(gamesense_default_config) ~= 'string' or gamesense_default_config == '' then
        gamesense_default_config = nil
    end

    local config_defaults = { }
    local removed_default_configs = {
        ['Defensive'] = true,
        ['Unmatched undetect (Defensive)'] = true,
        ['Fast Delay Jitter'] = true
    }
    local have_default_config = false
    local db_dirty = false

    for i = 1, #db_data do
        local list = db_data[i]

        if list ~= nil and not removed_default_configs[list.name] then
            if list.is_default == true then
                if have_default_config then
                    list.is_default = false
                    db_dirty = true
                else
                    have_default_config = true
                end
            end

            table.insert(config_data, list)
        elseif list ~= nil then
            db_dirty = true
        end
    end

    for i = #config_defaults, 1, -1 do
        local list = config_defaults[i]

        if list.data == nil then
            goto continue
        end

        local ok, result = config_system.decode(list.data)

        if not ok then
            -- config is not valid, delete it
            table.remove(config_defaults, i)

            goto continue
        end

        list.data = result

        ::continue::
    end

    local function get_categories()
        local result = { }

        local list = ref.categories:get()

        for i = 1, #list do
            local value = list[i]

            local new_value = value:match(
                ' -  (.+)'
            )

            if new_value ~= nil then
                table.insert(result, new_value)
            end
        end

        if #result == 0 then
            return nil
        end

        return result
    end

    local function create_config(name, data, is_default, is_user_default)
        local list = { }

        list.name = name
        list.data = data
        list.default = is_default
        list.is_default = is_user_default == true

        return list
    end

    local function find_config(name)
        for i = 1, #config_list do
            local data = config_list[i]

            if data.name == name then
                return data, i
            end
        end

        return nil, -1
    end

    local function save_config_data()
        localdb['config'] = config_data
    end

    local function get_colorskins_api()
        local api = rawget(_G, 'pasthetic_colorskins') or rawget(_G, 'aesthetic_colorskins')
        if type(api) ~= 'table' then
            return nil
        end

        return api
    end

    local function clone_skin_data(data)
        if type(data) ~= 'table' then
            return { }
        end

        local result = { }

        for key, value in pairs(data) do
            if type(value) == 'table' then
                result[key] = clone_skin_data(value)
            else
                result[key] = value
            end
        end

        return result
    end

    local function save_skin_config_data()
        localdb['skin_configs'] = skin_config_data
        database.write(pasthetic_constants.DB.SKIN_CONFIGS, skin_config_data)
    end

    local function save_last_skin_config_name()
        localdb['last_skin_config_name'] = last_skin_config_name
    end

    local function save_gamesense_default_config()
        localdb['gamesense_default_config'] = gamesense_default_config
    end

    local function load_gamesense_config(name)
        name = utils.trim(name or '')

        if name == '' then
            return false
        end

        local api = rawget(_G, 'config')

        if type(api) ~= 'table' or type(api.load) ~= 'function' then
            logging.error('GameSense config API is unavailable')
            return false
        end

        local ok, result = pcall(api.load, name)

        if not ok then
            logging.error(string.format(
                'failed to load %s GameSense config: %s', name, result
            ))

            return false
        end

        logging.success(string.format(
            'loaded %s GameSense config', name
        ))

        return true
    end

    local function find_skin_config(name)
        for i = 1, #skin_config_data do
            local data = skin_config_data[i]

            if data ~= nil and data.name == name then
                return data, i
            end
        end

        return nil, -1
    end

    local function update_skin_config_list()
        for i = 1, #skin_config_list do
            skin_config_list[i] = nil
        end

        for i = 1, #skin_config_data do
            local data = skin_config_data[i]

            if type(data) == 'table' and type(data.name) == 'string' and type(data.data) == 'table' then
                table.insert(skin_config_list, data)
            end
        end
    end

    local function get_skin_render_list()
        local result = { }

        for i = 1, #skin_config_list do
            local data = skin_config_list[i]
            local name = data.name

            if name == active_skin_config_name then
                name = string.format('%s [active]', name)
            end

            table.insert(result, name)
        end

        return result
    end

    local function get_selected_skin_config()
        local index = ref.skin_list:get()

        if index == nil then
            return nil
        end

        return skin_config_list[index + 1]
    end

    local function sync_skin_input_with_selected_config()
        local list = get_selected_skin_config()

        if list ~= nil then
            ref.skin_input:set(list.name)
        end
    end

    local function update_skin_controls()
        update_skin_config_list()
        ref.skin_list:update(get_skin_render_list())
        menu_logic.update()
    end

    function ref.has_pending_skin_cache()
        return pending_skin_cache ~= nil
    end

    function ref.has_gamesense_default()
        return gamesense_default_config ~= nil
    end

    local function read_current_skin_config()
        local api = get_colorskins_api()

        if api == nil or type(api.export) ~= 'function' then
            return { }
        end

        return clone_skin_data(api.export())
    end

    local function save_skin_config(name, data)
        if name == '' then
            return
        end

        data = clone_skin_data(data)

        local list = find_skin_config(name)

        if list == nil then
            table.insert(skin_config_data, {
                name = name,
                data = data
            })
        else
            list.data = data
        end

        active_skin_config_name = name
        last_skin_config_name = name
        pending_skin_cache = nil

        save_skin_config_data()
        update_skin_controls()

        logging.success(string.format(
            'saved %s skins config', name
        ))
    end

    local function load_skin_config(name)
        local list = find_skin_config(name)

        if list == nil then
            return
        end

        local api = get_colorskins_api()

        if api == nil or type(api.import) ~= 'function' then
            logging.error('colorskins api is unavailable')
            return
        end

        skin_import_suspended = true
        api.import(clone_skin_data(list.data))
        skin_import_suspended = false

        active_skin_config_name = name
        last_skin_config_name = name
        pending_skin_cache = nil
        update_skin_controls()

        logging.success(string.format(
            'loaded %s skins config', name
        ))
    end

    client.set_event_callback('shutdown', function()
        last_skin_config_name = active_skin_config_name
        save_last_skin_config_name()
    end)

    local function on_skins_changed(data)
        if skin_import_suspended then
            return
        end

        data = clone_skin_data(data)

        if active_skin_config_name ~= nil then
            local list = find_skin_config(active_skin_config_name)

            if list ~= nil then
                list.data = data
                save_skin_config_data()
                return
            end

            active_skin_config_name = nil
        end

        pending_skin_cache = data
        update_skin_controls()
    end

    local function import_skins_from_config(data)
        if not ref.load_with_skins:get() or type(data) ~= 'table' or type(data.__colorskinscsgo) ~= 'table' then
            return false
        end

        local api = get_colorskins_api()
        if api == nil or type(api.import) ~= 'function' then
            return false
        end

        api.import(data.__colorskinscsgo)
        menu_logic.update()

        logging.success('loaded skins from config')
        return true
    end

    if db_dirty then
        save_config_data()
    end

    local function update_config_list()
        for i = 1, #config_list do
            config_list[i] = nil
        end

        for i = 1, #config_defaults do
            local list = config_defaults[i]

            local cell = create_config(
                list.name, list.data, true
            )

            table.insert(config_list, cell)
        end

        for i = 1, #config_data do
            local list = config_data[i]

            local cell = create_config(
                list.name, list.data, false, list.is_default
            )

            cell.data_index = i

            table.insert(config_list, cell)
        end
    end

    local function get_render_list()
        local result = { }

        for i = 1, #config_list do
            local list = config_list[i]

            local name = list.name

            if list.default then
                name = string.format(
                    '%s*', name
                )
            end

            if list.is_default then
                name = string.format(
                    '%s [d]', name
                )
            end

            table.insert(result, name)
        end

        return result
    end

    local function get_selected_config()
        local index = ref.list:get()

        if index == nil then
            return nil
        end

        return config_list[index + 1]
    end

    function ref.is_selected_default()
        local list = get_selected_config()

        return list ~= nil and list.is_default == true
    end

    function ref.has_deleted_configs()
        return #deleted_configs > 0
    end

    local function sync_input_with_selected_config()
        local list = get_selected_config()

        if list ~= nil then
            ref.input:set(list.name)
        end
    end


    local function select_config(index)
        if #config_list == 0 then
            return
        end

        index = math.min(
            math.max(index or 0, 0),
            #config_list - 1
        )

        ref.list:set(index)
        sync_input_with_selected_config()
    end

    local function load_config(name, categories)
        local list, idx = find_config(name)

        if list == nil or idx == -1 then
            return
        end

        local data = list.data

        if type(data) == 'string' then
            local ok, result = config_system.decode(data)

            if not ok then
                logging.error(string.format(
                    'failed to decode %s config: %s', name, result
                ))

                return
            end

            data = result
        end

        autosave_suspended = true

        local ok, result = config_system.import(
            data, categories
        )

        if not ok then
            autosave_suspended = false

            logging.error(string.format(
                'failed to import %s config: %s', name, result
            ))

            return
        end

        windows.load_settings()

        local should_restore_builder = (
            type(data.Builder) == 'table'
            and (categories == nil or contains(categories, 'Builder') ~= nil)
        )

        if should_restore_builder then
            local builder_ok, builder_result = config_system.import(
                { Builder = data.Builder }, { 'Builder' }
            )

            if not builder_ok then
                logging.error(string.format(
                    'failed to restore %s builder settings: %s', name, builder_result
                ))
            end
        end

        import_skins_from_config(data)

        logging.success(string.format(
            'loaded %s config', name
        ))

        autosave_suspended = false
    end

    local function save_config(name, silent)
        windows.save_settings()

        local cfg_data = config_system.export()

        local list, idx = find_config(name)

        if list == nil or idx == -1 then
            table.insert(config_data, create_config(
                name, cfg_data, false, false
            ))

            save_config_data()
            update_config_list()

            ref.list:update(
                get_render_list()
            )

            select_config(#config_list - 1)

            if not silent then
                logging.success(string.format(
                    'created %s config', name
                ))
            end

            return
        end

        if list.default then
            logging.error(string.format(
                'you can\'t edit %s config', name
            ))

            return
        end

        list.data = cfg_data

        if list.data_index ~= nil then
            local data_cell = config_data[
                list.data_index
            ]

            if data_cell ~= nil then
                data_cell.data = cfg_data
            end
        end

        save_config_data()
        update_config_list()

        if not silent then
            logging.success(string.format(
                'saved %s config', name
            ))
        end
    end

    local function is_config_control(item)
        return item == ref.categories
            or item == ref.list
            or item == ref.input
            or item == ref.load_button
            or item == ref.save_button
            or item == ref.delete_button
            or item == ref.load_with_skins
            or item == ref.restore_button
            or item == ref.autosave
            or item == ref.mark_default_button
            or item == ref.unmark_default_button
            or item == ref.skin_list
            or item == ref.skin_input
            or item == ref.skin_load_button
            or item == ref.skin_create_button
            or item == ref.skin_create_saved_button
            or item == ref.skin_export_button
            or item == ref.skin_import_button
            or item == ref.share_all_active_button
            or item == ref.export_button
            or item == ref.import_button
    end

    local function schedule_autosave(item)
        if autosave_suspended or is_config_control(item) then
            return
        end

        if not ref.autosave:get() then
            return
        end

        local list = get_selected_config()

        if list == nil or list.default then
            return
        end

        autosave_token = autosave_token + 1
        local token = autosave_token

        client.delay_call(2, function()
            if token ~= autosave_token then
                return
            end

            if autosave_suspended or not ref.autosave:get() then
                return
            end

            local selected = get_selected_config()

            if selected == nil or selected.default then
                return
            end

            save_config(selected.name, true)
        end)
    end

    local function set_default_config(name, value)
        local list = find_config(name)

        if list == nil or list.default then
            return
        end

        for i = 1, #config_data do
            config_data[i].is_default = false
        end

        if value then
            if list.data_index ~= nil and config_data[list.data_index] ~= nil then
                config_data[list.data_index].is_default = true
            end
        end

        save_config_data()
        update_config_list()

        ref.list:update(
            get_render_list()
        )

        select_config(ref.list:get())

        logging.success(string.format(
            '%s %s default config',
            value and 'marked' or 'unmarked',
            name
        ))
    end

    local function delete_config(name)
        local list, idx = find_config(name)

        if list == nil or idx == -1 then
            return
        end

        if list.default then
            logging.error(string.format(
                'you can\'t delete %s config', name
            ))

            return
        end

        local data_index = list.data_index

        if data_index == nil then
            return
        end

        local removed = config_data[data_index]

        if removed ~= nil then
            table.insert(deleted_configs, {
                name = removed.name,
                data = removed.data,
                is_default = removed.is_default == true
            })
        end

        table.remove(config_data, data_index)

        save_config_data()
        update_config_list()

        ref.list:update(
            get_render_list()
        )

        select_config(ref.list:get())

        logging.success(string.format(
            'deleted %s config', name
        ))
    end

    local function restore_config()
        local restored = table.remove(deleted_configs)

        if restored == nil then
            return
        end

        if find_config(restored.name) ~= nil then
            local base_name = restored.name
            local n = 1

            repeat
                n = n + 1
                restored.name = string.format('%s (%d)', base_name, n)
            until find_config(restored.name) == nil
        end

        table.insert(config_data, create_config(
            restored.name, restored.data, false, restored.is_default
        ))

        save_config_data()
        update_config_list()

        ref.list:update(
            get_render_list()
        )

        select_config(#config_list - 1)

        logging.success(string.format(
            'restored %s config', restored.name
        ))
    end

    local callbacks do
        local function on_list(item)
            sync_input_with_selected_config()
        end

        local function on_load()
            local name = utils.trim(
                ref.input:get()
            )

            if name == '' then
                local list = get_selected_config()

                if list == nil then
                    return
                end

                name = list.name
            end

            load_config(name, nil)
        end

        local function on_save()
            local name = utils.trim(
                ref.input:get()
            )

            if name == '' then
                return
            end

            save_config(name)
        end

        local function on_delete()
            local name = utils.trim(
                ref.input:get()
            )

            if name == '' then
                return
            end

            delete_config(name)
        end

        local function on_restore()
            restore_config()
        end

        local function on_mark_default()
            local list = get_selected_config()

            if list == nil then
                return
            end

            set_default_config(list.name, true)
        end

        local function on_unmark_default()
            local list = get_selected_config()

            if list == nil then
                return
            end

            set_default_config(list.name, false)
        end

        local function on_gamesense_mark_default()
            local name = nil

            if ref.get_selected_gamesense_config_name ~= nil then
                name = ref.get_selected_gamesense_config_name()
            end

            if name == nil then
                logging.error('select GameSense config')
                return
            end

            gamesense_default_config = name
            save_gamesense_default_config()
            menu_logic.update()

            logging.success(string.format(
                'marked %s GameSense default config', name
            ))
        end

        local function on_gamesense_remove_default()
            local name = gamesense_default_config

            gamesense_default_config = nil
            save_gamesense_default_config()
            menu_logic.update()

            if name ~= nil then
                logging.success(string.format(
                    'removed %s GameSense default config', name
                ))
            end
        end

        local function on_skin_list()
            sync_skin_input_with_selected_config()
        end

        local function on_skin_load()
            local name = utils.trim(
                ref.skin_input:get()
            )

            if name == '' then
                local list = get_selected_skin_config()

                if list == nil then
                    return
                end

                name = list.name
            end

            load_skin_config(name)
        end

        local function on_skin_create()
            local name = utils.trim(
                ref.skin_input:get()
            )

            if name == '' then
                name = 'skins'
            end

            save_skin_config(name, pending_skin_cache or read_current_skin_config())
        end
        local function get_skin_config_name()
            local name = utils.trim(
                ref.skin_input:get()
            )

            if name ~= '' then
                return name
            end

            local list = get_selected_skin_config()

            if list == nil then
                return nil
            end

            return list.name
        end

        local function is_skin_config_payload(data)
            return type(data) == 'table'
                and type(data.data) == 'table'
                and (data[pasthetic_constants.SKIN_CONFIG_MARKER] == true or data[pasthetic_constants.LEGACY_SKIN_CONFIG_MARKER] == true)
        end

        local function is_all_configs_payload(data)
            return type(data) == 'table'
                and data[pasthetic_constants.ALL_CONFIGS_MARKER] == true
                and (type(data.config) == 'table' or type(data.skins) == 'table')
        end

        local function import_skin_config_payload(data)
            if not is_skin_config_payload(data) then
                return false
            end

            local name = utils.trim(data.name or '')

            if name == '' then
                name = utils.trim(ref.skin_input:get() or '')
            end

            if name == '' then
                name = 'imported skins'
            end

            save_skin_config(name, data.data)
            load_skin_config(name)

            logging.success(string.format(
                'imported %s skins config', name
            ))

            return true
        end

        local function import_raw_script_config(data, success_message)
            local categories = nil

            autosave_suspended = true

            local imported, import_error = config_system.import(data, categories)

            if not imported then
                autosave_suspended = false
                logging.error(string.format('failed to import config: %s', import_error))
                return false
            end

            windows.load_settings()

            local should_restore_builder = (
                type(data.Builder) == 'table'
                and (categories == nil or contains(categories, 'Builder') ~= nil)
            )

            if should_restore_builder then
                local builder_ok, builder_error = config_system.import(
                    { Builder = data.Builder }, { 'Builder' }
                )

                if not builder_ok then
                    logging.error(string.format('failed to restore imported builder settings: %s', builder_error))
                end
            end

            autosave_suspended = false

            logging.success(
                success_message or 'imported config'
            )

            return true
        end

        local function import_all_configs_payload(data)
            if not is_all_configs_payload(data) then
                return false
            end

            local imported_any = false

            if type(data.config) == 'table' and type(data.config.data) == 'table' then
                if import_raw_script_config(data.config.data, 'imported shared config') then
                    imported_any = true
                end
            end

            if type(data.skins) == 'table' and type(data.skins.data) == 'table' then
                local skin_payload = {
                    [pasthetic_constants.SKIN_CONFIG_MARKER] = true,
                    name = data.skins.name,
                    data = data.skins.data
                }

                if import_skin_config_payload(skin_payload) then
                    imported_any = true
                end
            end

            if not imported_any then
                logging.error('shared configs payload is empty')
            end

            return imported_any
        end

        local function import_script_config_payload(data)
            if is_all_configs_payload(data) then
                return import_all_configs_payload(data)
            end

            if is_skin_config_payload(data) then
                return import_skin_config_payload(data)
            end

            return import_raw_script_config(data)
        end

        local function on_skin_export()
            local name = get_skin_config_name()

            if name == nil then
                logging.error('select skins config')
                return
            end

            local list = find_skin_config(name)

            if list == nil then
                logging.error(string.format('skins config %s not found', name))
                return
            end

            local ok, result = config_system.encode({
                [pasthetic_constants.SKIN_CONFIG_MARKER] = true,
                name = name,
                data = clone_skin_data(list.data)
            })

            if not ok then
                logging.error(string.format('failed to export %s skins config: %s', name, result))
                return
            end

            clipboard.set(result)

            logging.success(string.format(
                'exported %s skins config', name
            ))
        end

        local function get_active_config_name()
            local name = utils.trim(
                ref.input:get() or ''
            )

            if name ~= '' then
                return name
            end

            local list = get_selected_config()

            if list ~= nil then
                return list.name
            end

            return 'shared config'
        end

        local function on_share_all_active()
            windows.save_settings()

            local skin_name = active_skin_config_name or get_skin_config_name() or 'shared skins'
            local skin_data = pending_skin_cache or read_current_skin_config()

            local ok, result = config_system.encode({
                [pasthetic_constants.ALL_CONFIGS_MARKER] = true,
                config = {
                    name = get_active_config_name(),
                    data = config_system.export()
                },
                skins = {
                    name = skin_name,
                    data = clone_skin_data(skin_data)
                }
            })

            if not ok then
                logging.error(string.format('failed to share active configs: %s', result))
                return
            end

            clipboard.set(result)

            logging.success('shared all active configs')
        end

        local function decode_clipboard_config(error_prefix)
            local str = clipboard.get()

            if str == nil then
                return nil
            end

            local ok, result = config_system.decode(str)

            if not ok then
                logging.error(string.format('%s: %s', error_prefix, result))
                return nil
            end

            return result
        end

        local function on_skin_import()
            local result = decode_clipboard_config('failed to import skins config')

            if result == nil then
                return
            end

            if is_skin_config_payload(result) then
                import_skin_config_payload(result)
                return
            end

            import_script_config_payload(result)
        end

        local function on_export()
            windows.save_settings()

            local ok, result = config_system.encode(
                config_system.export()
            )

            if not ok then
                return
            end

            clipboard.set(result)

            logging.success(
                'exported config'
            )
        end

        local function on_import()
            local result = decode_clipboard_config('failed to import config')

            if result == nil then
                return
            end

            import_script_config_payload(result)
        end
        ref.list:set_callback(on_list)

        ref.load_button:set_callback(on_load)
        ref.save_button:set_callback(on_save)
        ref.delete_button:set_callback(on_delete)
        ref.restore_button:set_callback(on_restore)
        ref.mark_default_button:set_callback(on_mark_default)
        ref.unmark_default_button:set_callback(on_unmark_default)
        ref.gamesense_mark_default_button:set_callback(on_gamesense_mark_default)
        ref.gamesense_remove_default_button:set_callback(on_gamesense_remove_default)
        ref.skin_list:set_callback(on_skin_list)
        ref.skin_load_button:set_callback(on_skin_load)
        ref.skin_create_button:set_callback(on_skin_create)
        ref.skin_create_saved_button:set_callback(on_skin_create)
        ref.skin_export_button:set_callback(on_skin_export)
        ref.skin_import_button:set_callback(on_skin_import)
        ref.share_all_active_button:set_callback(on_share_all_active)


        ref.export_button:set_callback(on_export)
        ref.import_button:set_callback(on_import)

        menu.get_event_bus().item_changed:set(schedule_autosave)
    end

    update_skin_config_list()
    ref.skin_list:update(get_skin_render_list())
    sync_skin_input_with_selected_config()


    do
        local api = get_colorskins_api()

        if api ~= nil and type(api.on_change) == 'function' then
            api.on_change(on_skins_changed)
        end
    end

    update_config_list()
    ref.list:update(get_render_list())
    local default_index = 0

    for i = 1, #config_list do
        if config_list[i].is_default then
            default_index = i - 1
            break
        end
    end

    select_config(default_index)

    local default_config = get_selected_config()

    logging.script_loaded()

    if gamesense_default_config ~= nil then
        load_gamesense_config(gamesense_default_config)
    end

    if default_config ~= nil and default_config.is_default then
        load_config(default_config.name, nil)
    end

    if last_skin_config_name ~= nil then
        if find_skin_config(last_skin_config_name) ~= nil then
            load_skin_config(last_skin_config_name)
        else
            last_skin_config_name = nil
            save_last_skin_config_name()
        end
    end
end

    return true
end

function M.health()
    return true
end

return M
