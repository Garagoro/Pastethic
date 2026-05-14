local M = {}

function M.new(deps)
    deps = deps or {}

    local ui = assert(deps.ui, 'rage_ai_peek_scanner: ui dependency is required')
    local entity = assert(deps.entity, 'rage_ai_peek_scanner: entity dependency is required')
    local client = assert(deps.client, 'rage_ai_peek_scanner: client dependency is required')
    local vector = assert(deps.vector, 'rage_ai_peek_scanner: vector dependency is required')
    local ref = assert(deps.ref, 'rage_ai_peek_scanner: ref dependency is required')
    local helpers = assert(deps.helpers, 'rage_ai_peek_scanner: helpers dependency is required')
    local records = assert(deps.records, 'rage_ai_peek_scanner: records dependency is required')
    local constants = assert(deps.constants, 'rage_ai_peek_scanner: constants dependency is required')
    local rage_min_damage = assert(deps.rage_min_damage, 'rage_ai_peek_scanner: rage_min_damage dependency is required')
    local rage_damage_override = assert(deps.rage_damage_override, 'rage_ai_peek_scanner: rage_damage_override dependency is required')

    local api = {}

    function api.get_active_hitboxes()
        local active = {}

        for i = 1, #constants.hitbox_names do
            local name = constants.hitbox_names[i]

            if ref.hitboxes:get(name) then
                active[i - 1] = name
            end
        end

        if next(active) == nil then
            active[0] = 'Head'
            active[3] = 'Stomach'
        end

        return active
    end

    function api.get_targets(exclude)
        local players = {}

        if ref.scan_all:get() or exclude then
            local list = entity.get_players(exclude and false or true)

            for i = 1, #list do
                local ent = list[i]

                if ent ~= exclude and ent ~= nil and entity.is_alive(ent) and not entity.is_dormant(ent) then
                    players[#players + 1] = ent
                end
            end
        else
            local ent = client.current_threat()

            if ent ~= nil and entity.is_alive(ent) and not entity.is_dormant(ent) then
                players[#players + 1] = ent
            end
        end

        if #players == 0 then
            local list = entity.get_players(true)

            for i = 1, #list do
                local ent = list[i]

                if ent ~= nil and entity.is_alive(ent) and not entity.is_dormant(ent) then
                    players[#players + 1] = ent
                end
            end
        end

        return players
    end

    function api.get_threats()
        local players = {}
        local list = entity.get_players(true)

        for i = 1, #list do
            local ent = list[i]

            if ent ~= nil and entity.is_alive(ent) and not entity.is_dormant(ent) then
                players[#players + 1] = ent
            end
        end

        return players
    end

    function api.get_local_damage_points_at(pos)
        return {
            pos + vector(0, 0, 64),
            pos + vector(0, 0, 54),
            pos + vector(0, 0, 42),
            pos + vector(0, 0, 34)
        }
    end

    function api.evaluate_position_safety(me, pos)
        local max_damage = 0
        local exposure_count = 0
        local bad_record_exposure = 0
        local threats = api.get_threats()
        local local_points = api.get_local_damage_points_at(pos)

        for i = 1, #threats do
            local threat = threats[i]
            local eye = helpers.get_eye_position(threat)
            local threat_damage = 0

            if eye ~= nil then
                for j = 1, #local_points do
                    local point = local_points[j]
                    local hit_ent, damage = client.trace_bullet(
                        threat,
                        eye.x, eye.y, eye.z,
                        point.x, point.y, point.z,
                        false
                    )

                    if hit_ent == me and damage ~= nil then
                        threat_damage = math.max(threat_damage, damage)
                    end
                end
            end

            if threat_damage > 5 then
                exposure_count = exposure_count + 1
                max_damage = math.max(max_damage, threat_damage)

                if records.is_garbage(threat) then
                    bad_record_exposure = bad_record_exposure + 1
                end
            end
        end

        return {
            incoming_damage = max_damage,
            exposure_count = exposure_count,
            bad_record_exposure = bad_record_exposure
        }
    end

    function api.is_position_hittable(safety)
        return safety ~= nil
            and ((safety.incoming_damage or 0) > constants.COMMIT_EXPOSURE_DAMAGE
                or (safety.exposure_count or 0) > 0)
    end

    function api.is_full_safe(safety)
        return safety ~= nil
            and (safety.incoming_damage or 0) <= 0
            and (safety.exposure_count or 0) <= 0
            and (safety.bad_record_exposure or 0) <= 0
    end

    function api.is_commit_candidate_safe(candidate, current_safety)
        if candidate == nil or candidate.start == nil then
            return false
        end

        if (candidate.bad_record_exposure or 0) > 0 then
            return false
        end

        local current_exposure = current_safety ~= nil and (current_safety.exposure_count or 0) or 0
        local current_damage = current_safety ~= nil and (current_safety.incoming_damage or 0) or 0

        if (candidate.exposure_count or 0) > math.max(1, current_exposure) then
            return false
        end

        if (candidate.incoming_damage or 0) > math.max(constants.COMMIT_EXPOSURE_DAMAGE, current_damage + 5) then
            return false
        end

        return true
    end

    function api.get_min_damage()
        if ref.min_damage_override:get() then
            return helpers.safe_get(rage_damage_override[3], helpers.safe_get(rage_min_damage[1], 1))
        end

        return helpers.safe_get(rage_min_damage[1], 1)
    end

    function api.scan(data, me, origin)
        if data == nil or data.positions == nil then
            return
        end

        for _, point in next, data.positions.other do
            local total_damage = 0
            point[1] = {
                hitbox = {},
                damage = 0
            }

            local start = helpers.vector_copy(point.position) + vector(0, 0, 64)
            local targets = api.get_targets()
            local hitboxes = api.get_active_hitboxes()
            local min_damage = api.get_min_damage()
            local safety = nil

            for _, target in next, targets do
                if records.is_garbage(target) then
                    goto skip_target
                end

                local health = entity.get_prop(target, 'm_iHealth') or 0

                for hitbox_id in next, hitboxes do
                    local velocity = helpers.get_velocity(target)
                    local hitbox_pos = helpers.make_vec(entity.hitbox_position(target, hitbox_id))

                    if hitbox_pos ~= nil then
                        local predicted = helpers.extrapolate(
                            hitbox_pos,
                            velocity,
                            ref.prediction:get()
                        )
                        local hit_ent, damage = client.trace_bullet(
                            me,
                            start.x, start.y, start.z,
                            predicted.x, predicted.y, predicted.z
                        )
                        local trace_damage = damage or 0

                        if not hit_ent then
                            point[1].damage = total_damage
                        elseif target == hit_ent then
                            point[1].damage = total_damage < trace_damage and trace_damage or total_damage
                        end

                        total_damage = point[1].damage

                        if (hit_ent == nil or target == hit_ent)
                            and (trace_damage >= min_damage or health <= trace_damage)
                        then
                            if safety == nil then
                                safety = api.evaluate_position_safety(me, point.position)
                            end

                            local target_origin = helpers.get_origin(target)

                            if target_origin ~= nil then
                                data.aim[#data.aim + 1] = {
                                    start = start,
                                    ['end'] = target_origin,
                                    damage = trace_damage,
                                    lethal = health <= trace_damage,
                                    move_distance = origin:dist2d(point.position),
                                    target_distance = start:dist(target_origin),
                                    incoming_damage = safety.incoming_damage,
                                    exposure_count = safety.exposure_count,
                                    bad_record_exposure = safety.bad_record_exposure
                                }
                            end

                            point[1].hitbox[hitbox_id] = predicted
                        end
                    end
                end

                ::skip_target::
            end
        end
    end

    return api
end

return M
