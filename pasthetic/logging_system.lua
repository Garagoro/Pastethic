local M = {}

function M.start(deps)
    local script = assert(deps.script, 'logging_system: script dependency is required')
    local resource = assert(deps.resource, 'logging_system: resource dependency is required')
    local ui = assert(deps.ui, 'logging_system: ui dependency is required')
    local entity = assert(deps.entity, 'logging_system: entity dependency is required')
    local client = assert(deps.client, 'logging_system: client dependency is required')
    local globals = assert(deps.globals, 'logging_system: globals dependency is required')
    local utils = assert(deps.utils, 'logging_system: utils dependency is required')
    local software = assert(deps.software, 'logging_system: software dependency is required')
    local override = assert(deps.override, 'logging_system: override dependency is required')
    local vector = assert(deps.vector, 'logging_system: vector dependency is required')
    local renderer = assert(deps.renderer, 'logging_system: renderer dependency is required')
    local color = assert(deps.color, 'logging_system: color dependency is required')
    local motion = assert(deps.motion, 'logging_system: motion dependency is required')
    local surface = assert(deps.surface, 'logging_system: surface dependency is required')
    local text_fmt = assert(deps.text_fmt, 'logging_system: text_fmt dependency is required')
    local logging_system do
        local ref = resource.main.logging_system

        local PADDING_H = 5
        local PADDING_V = 5

        local HITGROUP = {
            [0]  = 'generic',
            [1]  = 'head',
            [2]  = 'chest',
            [3]  = 'stomach',
            [4]  = 'left arm',
            [5]  = 'right arm',
            [6]  = 'left leg',
            [7]  = 'right leg',
            [8]  = 'neck',
            [10] = 'gear'
        }

        local HURT_ACTS = {
            ['knife'] = 'Knifed',
            ['inferno'] = 'Burned',
            ['hegrenade'] = 'Naded'
        }

        local dev_queue = { }
        local log_queue = { }

        local aimbot_data = { }
        local preview_alpha = 0.0

        local ref_draw_console_output = ui.reference(
            'Misc', 'Miscellaneous', 'Draw console output'
        )

        local ref_log_misses_due_to_spread = ui.reference(
            'Rage', 'Other', 'Log misses due to spread'
        )

        local function wrap_color(text, hex)
            return string.format(
                '\a%s%s\aDEFAULT',
                hex, text
            )
        end

        local function create_log_data(text)
            local list, count = text_fmt.color(text)

            for i = 1, #list do
                local data = list[i]

                local hex = data[2] or 'ffffffc8'
                local col = color(utils.from_hex(hex))

                data[2] = col
            end

            return { list = list, count = count }
        end

        local function print_dev(text)
            local should_add = (
                ref.output:get 'Events' and
                ref.events_font:get() == 'Old'
            )

            if not should_add then
                return
            end

            local data = create_log_data(text)
            data.liferemaining = 8

            table.insert(dev_queue, data)

            if #dev_queue > 6 then
                table.remove(dev_queue, 1)
            end
        end

        local function clear_developer_logs()
            for i = 1, #dev_queue do
                dev_queue[i] = nil
            end
        end

        local function add_crosshair_log(text)
            local data = create_log_data(text)
            local duration = ref.duration:get() * 0.1

            data.alpha = 0.0
            data.liferemaining = duration

            table.insert(log_queue, 1, data)

            if #log_queue > 6 then
                table.remove(log_queue, 1)
            end
        end

        local function print_raw(text)
            local list, count = text_fmt.color(text)

            for i = 1, count do
                local data = list[i]

                local str = data[1]
                local hex = data[2]

                local col = color(utils.from_hex(hex or 'ffffffc8'))

                if i ~= count then
                    str = str .. '\0'
                end

                client.color_log(col.r, col.g, col.b, str)
            end
        end

        local function prefixf(str)
            local hex = 'b464ffff'

            return '\a'.. hex .. '[Pasthetic] '..
                   '\aDEFAULT' .. str
        end

        local function colorf(fmt, repl)
            local count = 0

            local result = fmt:gsub('%${(.-)}', function(str)
                count = count + 1

                return string.format(
                    '\a%s%s\aDEFAULT', repl[count], str
                )
            end)

            return result
        end

        local function get_hitgroup(id)
            return HITGROUP[id] or '?'
        end

        local function get_reason_items(reason)
            if reason == '?' then
                reason = 'resolver'
            end

            reason = string.format(
                '%s%s',
                reason:sub(1, 1):upper(),
                reason:sub(2)
            )

            return ref[reason]
        end

        local function draw_shadow(x, y, w, h, alpha)
            local center = math.floor(0.5 + w * 0.5)

            local col_begin  = color(0, 0, 0, 0)
            local col_finish = color(0, 0, 0, 100 * alpha)

            renderer.gradient(
                x, y, center, h,
                col_begin.r, col_begin.g, col_begin.b, col_begin.a,
                col_finish.r, col_finish.g, col_finish.b, col_finish.a,
                true
            )

            renderer.gradient(
                x + center, y, center, h,
                col_finish.r, col_finish.g, col_finish.b, col_finish.a,
                col_begin.r, col_begin.g, col_begin.b, col_begin.a,
                true
            )
        end

        local function draw_outline(x, y, w, h, alpha)
            local thickness = 1

            local center = math.floor(0.5 + w * 0.5)

            local col_center = color(0, 0, 0, 50 * alpha)
            local col_edge   = color(0, 0, 0, 0)

            renderer.gradient(
                x, y, center, thickness,
                col_edge.r, col_edge.g, col_edge.b, col_edge.a,
                col_center.r, col_center.g, col_center.b, col_center.a,
                true
            )

            renderer.gradient(
                x + center, y, center, thickness,
                col_center.r, col_center.g, col_center.b, col_center.a,
                col_edge.r, col_edge.g, col_edge.b, col_edge.a,
                true
            )

            renderer.gradient(
                x, y + h - thickness, center, thickness,
                col_edge.r, col_edge.g, col_edge.b, col_edge.a,
                col_center.r, col_center.g, col_center.b, col_center.a,
                true
            )

            renderer.gradient(
                x + center, y + h - thickness, center, thickness,
                col_center.r, col_center.g, col_center.b, col_center.a,
                col_edge.r, col_edge.g, col_edge.b, col_edge.a,
                true
            )
        end

        local function update_developer_logs()
            local dt = globals.frametime()

            for i = #dev_queue, 1, -1 do
                local data = dev_queue[i]

                data.liferemaining = data.liferemaining - dt

                if data.liferemaining <= 0 then
                    table.remove(dev_queue, i)
                end
            end
        end

        local function draw_developer_logs()
            local x = 8
            local y = 5

            local font_tall = surface.text_tall(63) + 1

            for i = 1, #dev_queue do
                local data = dev_queue[i]

                local alpha = 1.0
                local timeleft = data.liferemaining

                if timeleft < 0.5 then
                    local f = utils.clamp(timeleft, 0.0, 0.5) / 0.5

                    if i == 1 and f < 0.2 then
                        y = y - font_tall * (1.0 - f / 0.2)
                    end

                    alpha = f
                end

                local text_x = x

                local max_width = 0
                local width_arr = { }

                for j = 1, data.count do
                    local buffer = data.list[j]

                    local text_size = vector(
                        surface.measure_text(63, buffer[1])
                    )

                    width_arr[j] = text_size
                    max_width = max_width + text_size.x
                end

                local half_width = math.floor(0.5 * max_width)

                surface.fade(text_x, y, half_width, font_tall, 0, 0, 0, 0, 0, 0, 0, 50 * alpha, true)
                surface.fade(text_x + half_width, y, half_width, font_tall, 0, 0, 0, 50 * alpha, 0, 0, 0, 0, true)

                for j = 1, data.count do
                    local buffer = data.list[j]

                    local text = buffer[1]
                    local col = buffer[2]

                    surface.text(63, text_x, y, col.r, col.g, col.b, col.a * alpha, text)

                    text_x = text_x + width_arr[j].x
                end

                y = y + font_tall
            end
        end

        local function update_crosshair_logs()
            local dt = globals.frametime()

            for i = #log_queue, 1, -1 do
                local data = log_queue[i]

                data.liferemaining = data.liferemaining - dt

                if data.liferemaining > 0 then
                    data.alpha = motion.interp(
                        data.alpha, 1, 0.05
                    )

                    goto continue
                end

                data.alpha = motion.interp(
                    data.alpha, 0, 0.05
                )

                if data.alpha <= 0.0 then
                    table.remove(log_queue, i)
                end

                ::continue::
            end
        end

        local function draw_crosshair_logs()
            local flags = ''

            local screen_size = vector(
                client.screen_size()
            )

            local position = vector(
                screen_size.x * 0.5,

                utils.lerp(
                    screen_size.y * 0.5 + 50,
                    screen_size.y - 200,
                    ref.offset_y:get() * 0.01
                )
            )

            local queue_list = {
                unpack(log_queue)
            }

            local should_preview = (
                next(queue_list) == nil
                and ui.is_menu_open()
            )

            preview_alpha = motion.interp(
                preview_alpha, should_preview, 0.05
            )

            if preview_alpha > 0.01 then
                local style = ref.crosshair_text_style:get()

                local preview_logs = { }

                if style == 'Gamesense' then
                    local hex = software.get_color(true)

                    table.insert(preview_logs, string.format(
                        'Hit %s in the %s for %s damage (%s health remaining)',
                        wrap_color('You pathetic', hex),
                        wrap_color('stomach', hex),
                        wrap_color('93', hex),
                        wrap_color('7', hex)
                    ))

                    table.insert(preview_logs, string.format(
                        'Missed shot due to %s',
                        wrap_color('spread', hex)
                    ))
                end

                if style == 'Pasthetic' then
                    local reason_items = get_reason_items 'Spread'

                    local target_color = color(ref['Target'].color:get())
                    local other_color = color(ref['Other'].color:get())

                    local miss_color = reason_items ~= nil
                        and color(reason_items.color:get())
                        or color(255, 32, 32, 255)

                    local target_hex = target_color:to_hex()
                    local other_hex = other_color:to_hex()
                    local miss_hex = miss_color:to_hex()

                    table.insert(preview_logs, string.format(
                        'Hit %s ~ group: %s ~ damage: %s hp',
                        wrap_color('You pathetic', target_hex),
                        wrap_color('stomach', other_hex),
                        wrap_color('93', other_hex)
                    ))

                    table.insert(preview_logs, string.format(
                        'Missed %s ~ group: %s ~ reason: %s',
                        wrap_color('cuz u pathetic', target_hex),
                        wrap_color('stomach', other_hex),
                        wrap_color('spread', miss_hex)
                    ))
                end

                for i = 1, #preview_logs do
                    local data = create_log_data(
                        preview_logs[i]
                    )

                    data.alpha = preview_alpha
                    data.liferemaining = 0.0

                    table.insert(queue_list, data)
                end
            end

            for i = 1, #queue_list do
                local data = queue_list[i]

                local alpha = data.alpha

                local size_arr = { }
                local text_size = vector()

                for j = 1, data.count do
                    local buffer = data.list[j]

                    local measure = vector(
                        renderer.measure_text(flags, buffer[1])
                    )

                    size_arr[j] = measure

                    text_size.x = text_size.x + measure.x
                    text_size.y = math.max(text_size.y, measure.y)
                end

                local box_size = text_size + vector(
                    PADDING_H * 2, PADDING_V * 2
                )

                local height = box_size.y + 3

                local rect_pos = position:clone()
                rect_pos.x = rect_pos.x - box_size.x / 2

                draw_shadow(rect_pos.x, rect_pos.y, box_size.x, box_size.y, alpha)
                draw_outline(rect_pos.x, rect_pos.y, box_size.x, box_size.y, alpha)

                local text_pos = vector(
                    rect_pos.x + PADDING_H,
                    rect_pos.y + PADDING_V
                )

                for j = 1, data.count do
                    local buffer = data.list[j]

                    local text = buffer[1]
                    local col = buffer[2]

                    renderer.text(
                        text_pos.x, text_pos.y,
                        col.r, col.g, col.b, col.a * alpha,
                        flags, nil, text
                    )

                    text_pos.x = text_pos.x + size_arr[j].x
                end

                position.y = position.y + height * alpha
            end
        end

        local function on_paint_developer_logs()
            update_developer_logs()
            draw_developer_logs()
        end

        local function on_paint_crosshair_logs()
            update_crosshair_logs()
            draw_crosshair_logs()
        end

        local function on_aim_fire(e)
            local me = entity.get_local_player()

            if me == nil then
                return
            end

            local history = globals.tickcount() - e.tick
            local server_tick = globals.servertickcount()

            aimbot_data[e.id] = {
                original = e,

                history = history,
                server_tick = server_tick
            }
        end

        local function on_aim_hit(e)
            local target = e.target

            if target == nil then
                return
            end

            local aim_data = aimbot_data[e.id]

            if aim_data == nil then
                return
            end

            local console_style = ref.console_text_style:get()
            local crosshair_style = ref.crosshair_text_style:get()

            local elapsed = math.max(globals.servertickcount() - aim_data.server_tick - 1, 0)

            local health = entity.get_prop(target, 'm_iHealth')
            local target_name = entity.get_player_name(target)

            local damage = e.damage or 0
            local hitgroup = e.hitgroup

            local wanted_damage = aim_data.original.damage
            local wanted_hitgroup = aim_data.original.hitgroup

            local backtrack = aim_data.history or 0
            local hit_chance = aim_data.original.hit_chance or 0

            local gamesense_text do
                local hex = software.get_color(true)

                gamesense_text = string.format(
                    'Hit %s in the %s for %s damage (%s health remaining)',
                    wrap_color(target_name, hex),
                    wrap_color(get_hitgroup(e.hitgroup), hex),
                    wrap_color(damage, hex),
                    wrap_color(health, hex)
                )
            end

            local pasthetic_text do
                local target_color = color(ref['Target'].color:get())
                local other_color = color(ref['Other'].color:get())

                local target_hex = target_color:to_hex()
                local other_hex = other_color:to_hex()

                local details = { } do
                    local sep = '\aABABABFF · \aDEFAULT'

                    table.insert(details, string.format('hc: \a%s%d%%\aDEFAULT', other_hex, hit_chance))
                    table.insert(details, string.format('bt: \a%s%dt\aDEFAULT', other_hex, backtrack))

                    details.dev = table.concat(details, sep)

                    table.insert(details, string.format('reg: \a%s%dt\aDEFAULT', other_hex, elapsed))
                    details.raw = table.concat(details, sep)
                end

                local text = { } do
                    local damage_text = string.format('\a%s%d\aDEFAULT', other_hex, damage)
                    local hitgroup_text = string.format('\a%s%s\aDEFAULT', other_hex, get_hitgroup(hitgroup))

                    if damage ~= wanted_damage then
                        damage_text = damage_text .. string.format('(\a%s%d\aDEFAULT)', other_hex, wanted_damage)
                    end

                    if hitgroup ~= wanted_hitgroup then
                        hitgroup_text = hitgroup_text .. string.format('(\a%s%s\aDEFAULT)', other_hex, get_hitgroup(wanted_hitgroup))
                    end

                    local palette = { target_hex }

                    local fmt_dev = string.format('Hit ${%s} ~ group: %s ~ damage: %s hp [%s]', target_name, hitgroup_text, damage_text, details.dev)
                    local fmt_raw = string.format('Hit ${%s} ~ group: %s ~ damage: %s hp [%s]', target_name, hitgroup_text, damage_text, details.raw)
                    local fmt_log = string.format('Hit ${%s} ~ group: %s ~ damage: %s hp', target_name, hitgroup_text, damage_text)

                    text.dev = colorf(fmt_dev, palette)
                    text.raw = colorf(fmt_raw, palette)
                    text.log = colorf(fmt_log, palette)
                end

                pasthetic_text = text
            end

            if console_style == 'Gamesense' then
                print_raw(prefixf(gamesense_text))
                print_dev(gamesense_text)
            elseif console_style == 'Pasthetic' then
                print_raw(prefixf(pasthetic_text.raw))
                print_dev(pasthetic_text.dev)
            end

            if crosshair_style == 'Gamesense' then
                add_crosshair_log(gamesense_text)
            elseif crosshair_style == 'Pasthetic' then
                add_crosshair_log(pasthetic_text.log)
            end
        end

        local function on_aim_miss(e)
            local me = entity.get_local_player()

            if me == nil then
                return
            end

            local target = e.target

            if target == nil then
                return
            end

            local aim_data = aimbot_data[e.id]

            if aim_data == nil then
                return
            end

            local reason = e.reason

            local target_name = entity.get_player_name(target)
            local wanted_hitgroup = aim_data.original.hitgroup

            local backtrack = aim_data.history or 0
            local hit_chance = aim_data.original.hit_chance or 0

            if reason == '?' then
                reason = 'resolver'
            end

            local console_style = ref.console_text_style:get()
            local crosshair_style = ref.crosshair_text_style:get()

            local gamesense_text = string.format(
                'Missed shot due to %s', reason
            )

            local pasthetic_text do
                local reason_items = get_reason_items(reason)

                local target_color = color(ref['Target'].color:get())
                local other_color = color(ref['Other'].color:get())

                local miss_color = reason_items ~= nil
                    and color(reason_items.color:get())
                    or color(255, 32, 32, 255)

                local target_hex = target_color:to_hex()
                local other_hex = other_color:to_hex()
                local miss_hex = miss_color:to_hex()

                local details do
                    local list = { }

                    table.insert(list, string.format('hc: \a%s%d%%\aDEFAULT', other_hex, hit_chance))
                    table.insert(list, string.format('bt: \a%s%dt\aDEFAULT', other_hex, backtrack))

                    details = table.concat(list, '\aABABABFF · \aDEFAULT')
                end

                local text = { } do
                    local palette = { target_hex, other_hex, miss_hex }
                    local hitgroup_text = get_hitgroup(wanted_hitgroup)

                    local fmt_dev = string.format('Missed ${%s} ~ group: ${%s} ~ reason: ${%s} [%s]', target_name, hitgroup_text, reason, details)
                    local fmt_raw = string.format('Missed ${%s} ~ group: ${%s} ~ reason: ${%s} [%s]', target_name, hitgroup_text, reason, details)
                    local fmt_log = string.format('Missed ${%s} ~ group: ${%s} ~ reason: ${%s}', target_name, hitgroup_text, reason)

                    text.dev = colorf(fmt_dev, palette)
                    text.raw = colorf(fmt_raw, palette)
                    text.log = colorf(fmt_log, palette)
                end

                pasthetic_text = text
            end

            if console_style == 'Gamesense' then
                print_raw(prefixf(gamesense_text))
                print_dev(gamesense_text)
            elseif console_style == 'Pasthetic' then
                print_raw(prefixf(pasthetic_text.raw))
                print_dev(pasthetic_text.dev)
            end

            if crosshair_style == 'Gamesense' then
                add_crosshair_log(gamesense_text)
            elseif crosshair_style == 'Pasthetic' then
                add_crosshair_log(pasthetic_text.log)
            end
        end

        local function on_player_hurt(e)
            local me = entity.get_local_player()

            local userid = client.userid_to_entindex(e.userid)
            local attacker = client.userid_to_entindex(e.attacker)

            if me == userid or me ~= attacker then
                return
            end

            local act = HURT_ACTS[e.weapon]

            if act == nil then
                return
            end

            local name = entity.get_player_name(userid)

            local health = e.health
            local damage = e.dmg_health

            local console_style = ref.console_text_style:get()
            local crosshair_style = ref.crosshair_text_style:get()

            local gamesense_text do
                local hex = software.get_color(true)

                gamesense_text = string.format(
                    '%s %s for %s damage',
                    act,
                    wrap_color(name, hex),
                    wrap_color(damage, hex)
                )
            end

            local pasthetic_text do
                local target_color = color(ref['Target'].color:get())
                local other_color = color(ref['Other'].color:get())

                local target_hex = target_color:to_hex()
                local other_hex = other_color:to_hex()

                local text = string.format('%s ${%s} for ${%d} damage (${%d} health remaining)', act, name, damage, health) do
                    text = colorf(text, { target_hex, other_hex, other_hex })
                end

                pasthetic_text = text
            end

            if console_style == 'Gamesense' then
                print_raw(prefixf(gamesense_text))
                print_dev(gamesense_text)
            elseif console_style == 'Pasthetic' then
                print_raw(prefixf(pasthetic_text))
                print_dev(pasthetic_text)
            end

            if crosshair_style == 'Gamesense' then
                add_crosshair_log(gamesense_text)
            elseif crosshair_style == 'Pasthetic' then
                add_crosshair_log(pasthetic_text)
            end
        end

        local function on_item_purchase(e)
            local userid = client.userid_to_entindex(e.userid)

            if userid == nil or not entity.is_enemy(userid) then
                return
            end

            local weapon = e.weapon

            if weapon == 'weapon_unknown' then
                return
            end

            local name = entity.get_player_name(userid)

            local console_style = ref.console_text_style:get()
            local crosshair_style = ref.crosshair_text_style:get()

            local gamesense_text do
                local hex = software.get_color(true)

                gamesense_text = string.format(
                    '%s bought %s',
                    wrap_color(name, hex),
                    wrap_color(weapon, hex)
                )
            end

            local pasthetic_text do
                local target_color = color(ref['Target'].color:get())
                local other_color = color(ref['Other'].color:get())

                local target_hex = target_color:to_hex()
                local other_hex = other_color:to_hex()

                pasthetic_text = string.format(
                    '%s bought %s',
                    wrap_color(name, target_hex),
                    wrap_color(weapon, other_hex)
                )
            end

            if console_style == 'Gamesense' then
                print_raw(prefixf(gamesense_text))
                print_dev(gamesense_text)
            elseif console_style == 'Pasthetic' then
                print_raw(prefixf(pasthetic_text))
                print_dev(pasthetic_text)
            end

            if crosshair_style == 'Gamesense' then
                add_crosshair_log(gamesense_text)
            elseif crosshair_style == 'Pasthetic' then
                add_crosshair_log(pasthetic_text)
            end
        end

        local function update_event_callbacks(value)
            if not value then
                utils.event_callback('paint_ui', on_paint_developer_logs, false)
                utils.event_callback('paint_ui', on_paint_crosshair_logs, false)

                utils.event_callback('aim_fire', on_aim_fire, false)
                utils.event_callback('aim_hit', on_aim_hit, false)
                utils.event_callback('aim_miss', on_aim_miss, false)

                utils.event_callback('player_hurt', on_player_hurt, false)
                utils.event_callback('item_purchase', on_item_purchase, false)
            end
        end

        local callbacks do
            local function on_events_font(item)
                local is_old = item:get() == 'Old'
                local is_bold = item:get() == 'Bold'

                if not is_old then
                    clear_developer_logs()
                end

                utils.event_callback(
                    'paint_ui',
                    on_paint_developer_logs,
                    is_old
                )

                override.unset(ref_draw_console_output)

                if is_old then
                    override.set(ref_draw_console_output, false)
                end

                if is_bold then
                    override.set(ref_draw_console_output, true)
                end
            end

            local function on_events(item)
                local is_aimbot = item:get 'Aimbot'
                local is_purchase = item:get 'Purchase'

                utils.event_callback(
                    'aim_fire',
                    on_aim_fire,
                    is_aimbot
                )

                utils.event_callback(
                    'aim_hit',
                    on_aim_hit,
                    is_aimbot
                )

                utils.event_callback(
                    'aim_miss',
                    on_aim_miss,
                    is_aimbot
                )

                utils.event_callback(
                    'player_hurt',
                    on_player_hurt,
                    is_aimbot
                )

                utils.event_callback(
                    'item_purchase',
                    on_item_purchase,
                    is_purchase
                )
            end

            local function on_output(item)
                local is_events = item:get 'Events'

                if not is_events then
                    utils.event_callback(
                        'paint_ui',
                        on_paint_developer_logs,
                        false
                    )

                    override.unset(ref_draw_console_output)

                    clear_developer_logs()
                end

                if is_events then
                    ref.events_font:set_callback(on_events_font, true)
                else
                    ref.events_font:unset_callback(on_events_font)
                end

                utils.event_callback(
                    'paint_ui',
                    on_paint_crosshair_logs,
                    item:get 'Under crosshair'
                )
            end

            local function on_enabled(item)
                local value = item:get()

                if not value then
                    clear_developer_logs()

                    override.unset(ref_draw_console_output)
                    ref.events:unset_callback(on_events_font)
                end

                if value then
                    override.set(ref_log_misses_due_to_spread, false)
                else
                    override.unset(ref_log_misses_due_to_spread)
                end

                if value then
                    ref.output:set_callback(on_output, true)
                    ref.events:set_callback(on_events, true)
                else
                    ref.events:unset_callback(on_events)
                    ref.output:unset_callback(on_output)
                end

                update_event_callbacks(value)
            end

            ref.enabled:set_callback(
                on_enabled, true
            )
        end
    end

    return true
end

function M.health()
    return true
end

return M