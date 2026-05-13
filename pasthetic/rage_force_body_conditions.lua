local M = {}

function M.start(deps)
    local resource = assert(deps.resource, 'rage_force_body_conditions: resource dependency is required')
    local ui = assert(deps.ui, 'rage_force_body_conditions: ui dependency is required')
    local entity = assert(deps.entity, 'rage_force_body_conditions: entity dependency is required')
    local client = assert(deps.client, 'rage_force_body_conditions: client dependency is required')
    local vector = assert(deps.vector, 'rage_force_body_conditions: vector dependency is required')
    local plist = assert(deps.plist, 'rage_force_body_conditions: plist dependency is required')
    local csgo_weapons = assert(deps.csgo_weapons, 'rage_force_body_conditions: csgo_weapons dependency is required')
    local ragebot = assert(deps.ragebot, 'rage_force_body_conditions: ragebot dependency is required')
    local utils = assert(deps.utils, 'rage_force_body_conditions: utils dependency is required')
    local unpack = deps.unpack or unpack

    local ref = resource.main.ragebot.force_body_conditions
    local ref_minimum_damage = ui.reference('Rage', 'Aimbot', 'Minimum damage')

    local HITGROUP_HEAD = 1
    local HITGROUP_STOMACH = 3
    local HITGROUP_LEFTLEG = 6
    local HITGROUP_RIGHTLEG = 7

    local manipulation = {}
    local item_data = {}

    function manipulation.set(entindex, item_name, ...)
        if item_data[entindex] == nil then
            item_data[entindex] = {}
        end

        if item_data[entindex][item_name] == nil then
            item_data[entindex][item_name] = { plist.get(entindex, item_name) }
        end

        plist.set(entindex, item_name, ...)
    end

    function manipulation.unset(entindex, item_name)
        local entity_data = item_data[entindex]

        if entity_data == nil then
            return
        end

        local item_values = entity_data[item_name]

        if item_values == nil then
            return
        end

        plist.set(entindex, item_name, unpack(item_values))
        entity_data[item_name] = nil
    end

    local player_data = {}

    local function get_or_create_player_data(index)
        local data = player_data[index]

        if data == nil then
            data = {
                misses = 0,
                body_aim = false
            }

            player_data[index] = data
        end

        return data
    end

    local function delete_player_data(index)
        player_data[index] = nil
    end

    local function clear_player_data()
        for k in pairs(player_data) do
            delete_player_data(k)
        end
    end

    local function restore_player_list()
        local enemies = entity.get_players(true)

        for i = 1, #enemies do
            manipulation.unset(enemies[i], 'Override prefer body aim')
        end
    end

    local function restore_ragebot_values()
        ragebot.unset(ref_minimum_damage)
    end

    local function get_hitbox_damage_mult(hitgroup)
        if hitgroup == HITGROUP_HEAD then
            return 4.0
        end

        if hitgroup == HITGROUP_STOMACH then
            return 1.25
        end

        if hitgroup == HITGROUP_LEFTLEG or hitgroup == HITGROUP_RIGHTLEG then
            return 0.75
        end

        return 1.0
    end

    local function scale_damage(enemy, damage, hitgroup, weapon_armor_ratio)
        damage = damage * get_hitbox_damage_mult(hitgroup)

        local armor_value = entity.get_prop(enemy, 'm_ArmorValue')
        local has_helmet = entity.get_prop(enemy, 'm_bHasHelmet')

        if armor_value > 0 then
            if hitgroup == HITGROUP_HEAD then
                if has_helmet ~= 0 then
                    damage = damage * (weapon_armor_ratio * 0.5)
                end
            else
                damage = damage * (weapon_armor_ratio * 0.5)
            end
        end

        return damage
    end

    local function simulate_damage(start_pos, end_pos, enemy, hitgroup, weapon)
        local data = csgo_weapons(weapon)
        local delta = end_pos - start_pos
        local damage = data.damage
        local armor_ratio = data.armor_ratio
        local range = data.range
        local range_modifier = data.range_modifier
        local length = math.min(range, delta:length())

        damage = damage * math.pow(range_modifier, length * 0.002)
        damage = scale_damage(enemy, damage, hitgroup, armor_ratio)

        return damage
    end

    local function is_lethal(start_pos, end_pos, enemy, hitgroup, weapon)
        local damage = simulate_damage(start_pos, end_pos, enemy, hitgroup, weapon)
        local health = entity.get_prop(enemy, 'm_iHealth')

        return damage >= health
    end

    local function get_weapon_type(weapon)
        local weapon_info = csgo_weapons(weapon)

        if weapon_info == nil then
            return nil
        end

        local weapon_type = weapon_info.type
        local weapon_index = weapon_info.idx

        if weapon_type == 'pistol' then
            if weapon_index == 1 then
                return 'Desert Eagle'
            end

            if weapon_index == 64 then
                return 'Revolver R8'
            end

            return 'Pistols'
        end

        if weapon_type == 'sniperrifle' then
            if weapon_index == 40 then
                return 'Scout'
            end

            if weapon_index == 9 then
                return 'AWP'
            end

            return 'Auto Snipers'
        end

        return nil
    end

    local function on_shutdown()
        clear_player_data()
        restore_player_list()
    end

    local function on_run_command()
        if ref.disabler:get() then
            return
        end

        local me = entity.get_local_player()

        if me == nil then
            return
        end

        local weapon = entity.get_player_weapon(me)

        if weapon == nil then
            return
        end

        local weapon_type = get_weapon_type(weapon)

        if weapon_type == nil or not ref.weapons:get(weapon_type) then
            return
        end

        local max_misses = ref.max_misses:get()
        local eye_pos = vector(client.eye_position())
        local my_health = entity.get_prop(me, 'm_iHealth')
        local is_max_misses = ref.conditions:get 'Max misses'
        local is_enemy_lethal = ref.conditions:get 'Enemy lethal'
        local enemies = entity.get_players(true)

        for i = 1, #enemies do
            local enemy = enemies[i]
            local data = get_or_create_player_data(enemy)
            local stomach = vector(entity.hitbox_position(enemy, 5))
            local was_max_misses = is_max_misses and data.misses >= max_misses
            local was_is_enemy_lethal = is_enemy_lethal and is_lethal(eye_pos, stomach, enemy, HITGROUP_STOMACH, weapon)
            local is_force_body = was_max_misses or was_is_enemy_lethal

            if is_force_body then
                manipulation.set(enemy, 'Override prefer body aim', 'Force')

                if was_max_misses and weapon_type == 'Scout' then
                    local damage = ref.scout_damage:get()
                    local should_change_min_damage = my_health == 100 and damage > 0

                    if should_change_min_damage then
                        ragebot.set(ref_minimum_damage, damage)
                    end
                end
            end

            data.body_aim = is_force_body
        end
    end

    local function on_finish_command()
        restore_player_list()
        restore_ragebot_values()
    end

    local function on_aim_miss(e)
        local target = e.target

        if target == nil then
            return
        end

        local target_data = get_or_create_player_data(target)
        target_data.misses = target_data.misses + 1
    end

    local function on_player_death(e)
        local me = entity.get_local_player()
        local userid = client.userid_to_entindex(e.userid)
        local attacker = client.userid_to_entindex(e.attacker)

        if me ~= attacker or me == userid then
            return
        end

        delete_player_data(userid)
    end

    local function on_player_spawn(e)
        local userid = client.userid_to_entindex(e.userid)

        if userid == nil then
            return
        end

        delete_player_data(userid)
    end

    local function on_enabled(item)
        local value = item:get()

        if not value then
            clear_player_data()
            restore_player_list()
            restore_ragebot_values()
        end

        utils.event_callback('shutdown', on_shutdown, value)
        utils.event_callback('run_command', on_run_command, value)
        utils.event_callback('finish_command', on_finish_command, value)
        utils.event_callback('aim_miss', on_aim_miss, value)
        utils.event_callback('player_death', on_player_death, value)
        utils.event_callback('player_spawn', on_player_spawn, value)
    end

    ref.enabled:set_callback(on_enabled, true)
end

return M
