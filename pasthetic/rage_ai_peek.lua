local M = {}

function M.start(deps)
    deps = deps or {}

    local resource = assert(deps.resource, 'rage_ai_peek: resource dependency is required')
    local ui = assert(deps.ui, 'rage_ai_peek: ui dependency is required')
    local entity = assert(deps.entity, 'rage_ai_peek: entity dependency is required')
    local client = assert(deps.client, 'rage_ai_peek: client dependency is required')
    local globals = assert(deps.globals, 'rage_ai_peek: globals dependency is required')
    local vector = assert(deps.vector, 'rage_ai_peek: vector dependency is required')
    local renderer = deps.renderer or renderer
    local utils = assert(deps.utils, 'rage_ai_peek: utils dependency is required')
    local trace = deps.trace or require 'gamesense/trace'
    local weapons = deps.csgo_weapons or require 'gamesense/csgo_weapons'
    local bit = deps.bit or bit
    local require_module = deps.require_module or require

    local helpers_module = require_module 'pasthetic/rage_ai_peek_helpers'
    local records_module = require_module 'pasthetic/rage_ai_peek_records'
    local positions_module = require_module 'pasthetic/rage_ai_peek_positions'
    local scanner_module = require_module 'pasthetic/rage_ai_peek_scanner'

    local ref = resource.main.ragebot.ai_peek
    local rage_min_damage = { ui.reference('Rage', 'Aimbot', 'Minimum damage') }
    local rage_damage_override = { ui.reference('Rage', 'Aimbot', 'Minimum damage override') }
    local ref_quick_peek = { ui.reference('Rage', 'Other', 'Quick peek assist') }
    local ref_target_selection = ui.reference('Rage', 'Aimbot', 'Target selection')

    local constants = {
        SERVER_TELEPORT_DISTANCE = 64,
        STALL_UPDATES_MIN = 2,
        STALL_SPEED_MIN = 36,
        ROLLBACK_HOLD_TICKS = 12,
        COMMIT_EXPOSURE_DAMAGE = 5,
        COMMIT_LOCK_TICKS = 6,
        COMMIT_DISTANCE = 8,
        SAFE_RESCAN_TICKS = 4,
        RETURN_RESUME_SPEED = 55,
        MANUAL_RESET_DISTANCE_MIN = 160,
        AI_PEEK_TARGET_SELECTION = 'Best hit chance',
        hitbox_names = {
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
    }
    constants.SERVER_TELEPORT_DISTANCE_SQR = constants.SERVER_TELEPORT_DISTANCE * constants.SERVER_TELEPORT_DISTANCE

    local helpers = helpers_module.new({
        ui = ui,
        entity = entity,
        client = client,
        vector = vector,
        globals = globals,
        renderer = renderer,
        utils = utils,
        bit = bit
    })
    local records = records_module.new({
        entity = entity,
        globals = globals,
        helpers = helpers,
        constants = constants
    })
    local positions = positions_module.new({
        entity = entity,
        client = client,
        vector = vector,
        trace = trace,
        ref = ref,
        helpers = helpers
    })
    local scanner = scanner_module.new({
        ui = ui,
        entity = entity,
        client = client,
        vector = vector,
        ref = ref,
        helpers = helpers,
        records = records,
        constants = constants,
        rage_min_damage = rage_min_damage,
        rage_damage_override = rage_damage_override
    })

    local aipeek = {
        data = nil
    }

    local function clear_commit()
        if aipeek.data ~= nil then
            aipeek.data.commit = nil
        end
    end

    local function set_target_selection_override()
        if aipeek.data == nil or ref_target_selection == nil then
            return
        end

        if aipeek.data.target_selection_before == nil then
            aipeek.data.target_selection_before = helpers.safe_get(ref_target_selection, nil)
        end

        pcall(ui.set, ref_target_selection, constants.AI_PEEK_TARGET_SELECTION)
    end

    local function restore_target_selection()
        if aipeek.data == nil or aipeek.data.target_selection_before == nil or ref_target_selection == nil then
            return
        end

        pcall(ui.set, ref_target_selection, aipeek.data.target_selection_before)
        aipeek.data.target_selection_before = nil
    end

    local function start_native_return()
        if aipeek.data == nil then
            return
        end

        aipeek.data.native_return = true
        aipeek.data.safe_rescan_ticks = 0
        clear_commit()
        restore_target_selection()
    end

    local function ready_shot_local()
        local me = entity.get_local_player()

        if me == nil or not entity.is_alive(me) then
            return false
        end

        local weapon_index = entity.get_player_weapon(me)
        local weapon = weapons(weapon_index)

        if weapon == nil or weapon.weapon_type_int == 0 or weapon.weapon_type_int == 9 then
            return false
        end

        local next_attack = entity.get_prop(me, 'm_flNextAttack') or 0
        local next_weapon_attack = entity.get_prop(weapon_index, 'm_flNextPrimaryAttack') or 0
        local now = globals.curtime()

        return next_attack <= now and next_weapon_attack <= now
    end

    local function reset()
        restore_target_selection()
        aipeek.data = nil
        records.reset()
    end

    local function is_active()
        return ref.enabled:get()
            and helpers.safe_get(ref_quick_peek[1], false) == true
            and helpers.safe_get(ref_quick_peek[2], false) == true
    end

    local function update_data()
        local bind_active = is_active()

        if not bind_active then
            reset()
            return
        end

        local me = entity.get_local_player()

        if me == nil or not entity.is_alive(me) then
            reset()
            return
        end

        if aipeek.data == nil then
            aipeek.data = {}
        end

        if aipeek.data.stored == nil then
            aipeek.data.stored = {}
        end

        if aipeek.data.stored.pos ~= true then
            local position = helpers.get_origin(me)
            local eye = helpers.make_vec(client.eye_position())

            if position == nil or eye == nil then
                return
            end

            aipeek.data.positions = {
                center = position,
                other = {}
            }
            aipeek.data.eye = eye
        end

        if aipeek.data.stored.ang ~= true then
            positions.build(aipeek.data)
        end

        aipeek.data.stored = {
            pos = true,
            ang = true
        }

        if ref.live_scan:get() then
            aipeek.data.stored.ang = false
        end
    end

    local function sort_aim_entries()
        table.sort(aipeek.data.aim, function(a, b)
            if a.bad_record_exposure ~= b.bad_record_exposure then
                return (a.bad_record_exposure or 0) < (b.bad_record_exposure or 0)
            end

            if a.exposure_count ~= b.exposure_count then
                return (a.exposure_count or 0) < (b.exposure_count or 0)
            end

            if a.incoming_damage ~= b.incoming_damage then
                return (a.incoming_damage or 0) < (b.incoming_damage or 0)
            end

            if a.lethal ~= b.lethal then
                return a.lethal == true
            end

            if a.move_distance ~= b.move_distance then
                return (a.move_distance or 0) < (b.move_distance or 0)
            end

            if a.damage ~= b.damage then
                return (a.damage or 0) > (b.damage or 0)
            end

            return (a.target_distance or a.start:dist(a['end'])) < (b.target_distance or b.start:dist(b['end']))
        end)
    end

    local function update_native_return(me, origin)
        local current_safety = scanner.evaluate_position_safety(me, origin)
        local stable_speed = helpers.get_speed2d(helpers.get_velocity(me)) <= constants.RETURN_RESUME_SPEED

        if scanner.is_full_safe(current_safety) and stable_speed then
            aipeek.data.safe_rescan_ticks = (aipeek.data.safe_rescan_ticks or 0) + 1
        else
            aipeek.data.safe_rescan_ticks = 0
        end

        if (aipeek.data.safe_rescan_ticks or 0) >= constants.SAFE_RESCAN_TICKS then
            aipeek.data.native_return = false
            aipeek.data.safe_rescan_ticks = 0
            clear_commit()
            restore_target_selection()
        end
    end

    local function get_move_target(me, origin, center_distance, tickcount)
        local active_commit = aipeek.data.commit

        if active_commit ~= nil and active_commit.until_tick < tickcount then
            if center_distance > constants.COMMIT_DISTANCE then
                start_native_return()
                return nil
            end

            clear_commit()
        end

        if not ready_shot_local() then
            aipeek.data.safe_rescan_ticks = 0

            if center_distance > constants.COMMIT_DISTANCE then
                start_native_return()
                return nil
            end

            clear_commit()
            return nil
        end

        set_target_selection_override()
        scanner.scan(aipeek.data, me, origin)
        sort_aim_entries()

        local best_aim = aipeek.data.aim[1]
        local current_safety = center_distance > constants.COMMIT_DISTANCE
            and scanner.evaluate_position_safety(me, origin)
            or nil
        local commit_point = scanner.is_position_hittable(current_safety)

        if commit_point then
            local commit = aipeek.data.commit

            if commit ~= nil and commit.until_tick >= tickcount then
                return commit.position
            end

            if scanner.is_commit_candidate_safe(best_aim, current_safety) then
                aipeek.data.commit = {
                    position = helpers.vector_copy(best_aim.start),
                    until_tick = tickcount + constants.COMMIT_LOCK_TICKS
                }
                return best_aim.start
            end

            start_native_return()
            return nil
        end

        if best_aim ~= nil and best_aim.start ~= nil then
            clear_commit()
            return best_aim.start
        end

        clear_commit()
        return nil
    end

    local function on_setup_command(cmd)
        local me = entity.get_local_player()

        if me == nil or not entity.is_alive(me) then
            return
        end

        if aipeek.data == nil then
            return
        end

        aipeek.data.aim = {}

        local origin = helpers.get_origin(me)

        if origin == nil or aipeek.data.positions == nil then
            return
        end

        local is_move = cmd.in_forward == 1
            or cmd.in_back == 1
            or cmd.in_moveleft == 1
            or cmd.in_moveright == 1

        if cmd.in_attack == 1 or cmd.in_attack == true then
            start_native_return()
        end

        local center_distance = origin:dist2d(aipeek.data.positions.center)
        local tickcount = globals.tickcount()

        if not aipeek.data.native_return and aipeek.data.commit == nil then
            local reset_distance = math.max(ref.distance:get() * 2.25, constants.MANUAL_RESET_DISTANCE_MIN)

            if center_distance > reset_distance then
                reset()
                return
            end
        end

        if aipeek.data.native_return then
            update_native_return(me, origin)
            return
        end

        local move_to_pos = get_move_target(me, origin, center_distance, tickcount)

        if move_to_pos ~= nil and not is_move then
            helpers.move_to(cmd, move_to_pos)
        end
    end

    local function on_paint()
        if aipeek.data == nil or aipeek.data.positions == nil or not ref.debug:get() then
            return
        end

        for _, point in next, aipeek.data.positions.other do
            local damage = point[1] ~= nil and point[1].damage or 0

            if damage > 0 then
                helpers.draw_circle(point.position, 12, 90, 220, 115, 200)
            else
                helpers.draw_circle(point.position, 12, 235, 235, 235, 140)
            end
        end
    end

    local function on_aim_fire()
        if aipeek.data ~= nil then
            start_native_return()
        end
    end

    utils.event_callback('shutdown', reset, true)
    utils.event_callback('round_start', reset, true)
    utils.event_callback('level_init', reset, true)
    utils.event_callback('net_update_end', records.update, true)
    utils.event_callback('run_command', update_data, true)
    utils.event_callback('setup_command', on_setup_command, true)
    utils.event_callback('paint', on_paint, true)
    utils.event_callback('aim_fire', on_aim_fire, true)
end

function M.health()
    return true
end

return M
