local M = {}

function M.start(deps)
    local resource = assert(deps.resource, 'automatic_purchase: resource dependency is required')
    local cvar = assert(deps.cvar, 'automatic_purchase: cvar dependency is required')
    local entity = assert(deps.entity, 'automatic_purchase: entity dependency is required')
    local client = assert(deps.client, 'automatic_purchase: client dependency is required')
    local csgo_weapons = assert(deps.csgo_weapons, 'automatic_purchase: csgo_weapons dependency is required')
    local utils = assert(deps.utils, 'automatic_purchase: utils dependency is required')
    local totime = assert(deps.totime, 'automatic_purchase: totime dependency is required')

    local ref = resource.main.automatic_purchase
    local mp_afterroundmoney = cvar.mp_afterroundmoney

    local primary_items = {
        ['AWP'] = 'awp',
        ['Scout'] = 'ssg08',
        ['G3SG1 / SCAR-20'] = 'scar20'
    }

    local secondary_items = {
        ['P250'] = 'p250',
        ['Elites'] = 'elite',
        ['Five-seven / Tec-9 / CZ75'] = 'fn57',
        ['Deagle / Revolver'] = 'deagle'
    }

    local equipment_items = {
        ['Kevlar'] = 'vest',
        ['Kevlar + Helmet'] = 'vesthelm',
        ['Defuse kit'] = 'defuser',
        ['HE'] = 'hegrenade',
        ['Smoke'] = 'smokegrenade',
        ['Molotov'] = 'molotov',
        ['Taser'] = 'taser'
    }

    local function should_buy()
        local me = entity.get_local_player()

        if me == nil then
            return
        end

        local account = entity.get_prop(me, 'm_iAccount')

        if ref.ignore_pistol_round:get() and account <= 1000 then
            return false
        end

        if ref.only_16k:get() then
            local after_round_money = mp_afterroundmoney:get_int()

            return account >= 16000 or after_round_money >= 16000
        end

        return true
    end

    local function should_buy_reserved()
        local me = entity.get_local_player()

        if me == nil then
            return false
        end

        local weapons = utils.get_player_weapons(me)

        for i = 1, #weapons do
            local weapon = weapons[i]
            local weapon_info = csgo_weapons(weapon)

            if weapon_info == nil then
                goto continue
            end

            if weapon_info.idx == 9 then
                return false
            end

            ::continue::
        end

        return true
    end

    local function buy_primary(list)
        local item = primary_items[ref.primary:get()]

        if item == nil then
            return
        end

        if item == 'awp' then
            local function on_awp()
                if not should_buy_reserved() then
                    return
                end

                local reserv = primary_items[ref.alternative:get()]

                if reserv == nil then
                    return
                end

                client.exec('buy ' .. reserv)
            end

            local duration = client.latency() + 0.15
            client.delay_call(duration, on_awp)
        end

        table.insert(list, item)
    end

    local function buy_secondary(list)
        local item = secondary_items[ref.secondary:get()]

        if item ~= nil then
            table.insert(list, item)
        end
    end

    local function buy_equipment(list)
        local values = ref.equipment:get()

        for i = 1, #values do
            local value = equipment_items[values[i]]

            if value ~= nil then
                table.insert(list, value)
            end
        end
    end

    local function process_buy()
        if not should_buy() then
            return
        end

        local list = {}

        buy_primary(list)
        buy_secondary(list)
        buy_equipment(list)

        local command = ''

        for i = 1, #list do
            command = command .. string.format('buy %s;', list[i])
        end

        if command ~= '' then
            client.exec(command)
        end
    end

    local function on_round_prestart()
        client.delay_call(client.latency() + totime(8), process_buy)
    end

    local function on_enabled(item)
        utils.event_callback('round_prestart', on_round_prestart, item:get())
    end

    ref.enabled:set_callback(on_enabled, true)
end

return M
