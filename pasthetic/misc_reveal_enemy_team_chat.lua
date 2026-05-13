local M = {}

function M.start(deps)
    local resource = assert(deps.resource, 'misc_reveal_enemy_team_chat: resource dependency is required')
    local panorama = assert(deps.panorama, 'misc_reveal_enemy_team_chat: panorama dependency is required')
    local cvar = assert(deps.cvar, 'misc_reveal_enemy_team_chat: cvar dependency is required')
    local client = assert(deps.client, 'misc_reveal_enemy_team_chat: client dependency is required')
    local entity = assert(deps.entity, 'misc_reveal_enemy_team_chat: entity dependency is required')
    local globals = assert(deps.globals, 'misc_reveal_enemy_team_chat: globals dependency is required')
    local chat = assert(deps.chat, 'misc_reveal_enemy_team_chat: chat dependency is required')
    local localize = assert(deps.localize, 'misc_reveal_enemy_team_chat: localize dependency is required')
    local utils = assert(deps.utils, 'misc_reveal_enemy_team_chat: utils dependency is required')

    local ref = resource.main.miscellaneous.reveal_enemy_team_chat
    local game_state_api = panorama.open().GameStateAPI
    local cl_mute_enemy_team = cvar.cl_mute_enemy_team
    local cl_mute_all_but_friends_and_party = cvar.cl_mute_all_but_friends_and_party
    local chat_data = {}

    local function on_player_say(e)
        local entindex = client.userid_to_entindex(e.userid)

        if not entity.is_enemy(entindex) then
            return
        end

        local xuid = game_state_api.GetPlayerXuidStringFromEntIndex(entindex)

        if game_state_api.IsSelectedPlayerMuted(xuid) then
            return
        end

        if cl_mute_enemy_team:get_int() == 1 then
            return
        end

        if cl_mute_all_but_friends_and_party:get_int() == 1 then
            return
        end

        client.delay_call(0.2, function()
            if chat_data[entindex] ~= nil and math.abs(globals.realtime() - chat_data[entindex]) < 0.4 then
                return
            end

            local player_resource = entity.get_player_resource()
            local last_place_name = entity.get_prop(entindex, 'm_szLastPlaceName')
            local player_name = entity.get_player_name(entindex)
            local team_literal = entity.get_prop(player_resource, 'm_iTeam', entindex) == 2 and 'T' or 'CT'
            local state_literal = entity.is_alive(entindex) and 'Loc' or 'Dead'
            local text = string.format('Cstrike_Chat_%s_%s', team_literal, state_literal)
            local localized_text = localize(text, {
                s1 = player_name,
                s2 = e.text,
                s3 = localize(last_place_name ~= '' and last_place_name or 'UI_Unknown')
            })

            chat.print_player(entindex, localized_text)
        end)
    end

    local function on_player_chat(e)
        if not entity.is_enemy(e.entity) then
            return
        end

        chat_data[e.entity] = globals.realtime()
    end

    local function on_enabled(item)
        local value = item:get()

        utils.event_callback('player_say', on_player_say, value)
        utils.event_callback('player_chat', on_player_chat, value)
    end

    ref.enabled:set_callback(on_enabled, true)
end

return M
