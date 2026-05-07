local M = {}

function M.new(deps)
    deps = deps or {}

    local ui = deps.ui or ui
    local utils = deps.utils
    local software = {}

    software.ragebot = {
        weapon_type = ui.reference(
            'Rage', 'Weapon type', 'Weapon type'
        ),

        aimbot = {
            enabled = {
                ui.reference('Rage', 'Aimbot', 'Enabled')
            },

            double_tap = {
                ui.reference('Rage', 'Aimbot', 'Double tap')
            },

            double_tap_fake_lag_limit = ui.reference(
                'Rage', 'Aimbot', 'Double tap fake lag limit'
            ),

            force_body_aim = ui.reference(
                'Rage', 'Aimbot', 'Force body aim'
            ),

            minimum_hit_chance = ui.reference(
                'Rage', 'Aimbot', 'Minimum hit chance'
            ),

            minimum_damage = ui.reference(
                'Rage', 'Aimbot', 'Minimum damage'
            ),

            minimum_damage_override = {
                ui.reference('Rage', 'Aimbot', 'Minimum damage override')
            }
        },

        other = {
            quick_peek_assist = {
                ui.reference('Rage', 'Other', 'Quick peek assist')
            },

            duck_peek_assist = ui.reference(
                'Rage', 'Other', 'Duck peek assist'
            )
        }
    }

    software.antiaimbot = {
        angles = {
            enabled = ui.reference(
                'AA', 'Anti-aimbot angles', 'Enabled'
            ),

            pitch = {
                ui.reference('AA', 'Anti-aimbot angles', 'Pitch')
            },

            yaw_base = ui.reference(
                'AA', 'Anti-aimbot angles', 'Yaw base'
            ),

            yaw = {
                ui.reference('AA', 'Anti-aimbot angles', 'Yaw')
            },

            yaw_jitter = {
                ui.reference('AA', 'Anti-aimbot angles', 'Yaw jitter')
            },

            body_yaw = {
                ui.reference('AA', 'Anti-aimbot angles', 'Body yaw')
            },

            freestanding_body_yaw = ui.reference(
                'AA', 'Anti-aimbot angles', 'Freestanding body yaw'
            ),

            edge_yaw = ui.reference(
                'AA', 'Anti-aimbot angles', 'Edge yaw'
            ),

            freestanding = {
                ui.reference('AA', 'Anti-aimbot angles', 'Freestanding')
            },

            roll = ui.reference(
                'AA', 'Anti-aimbot angles', 'Roll'
            )
        },

        fake_lag = {
            enabled = {
                ui.reference('AA', 'Fake lag', 'Enabled')
            },

            amount = ui.reference(
                'AA', 'Fake lag', 'Amount'
            ),

            variance = ui.reference(
                'AA', 'Fake lag', 'Variance'
            ),

            limit = ui.reference(
                'AA', 'Fake lag', 'Limit'
            ),
        },

        other = {
            slow_motion = {
                ui.reference('AA', 'Other', 'Slow motion')
            },

            on_shot_antiaim = {
                ui.reference('AA', 'Other', 'On shot anti-aim')
            },

            leg_movement = ui.reference(
                'AA', 'Other', 'Leg movement'
            ),

            fake_peek = {
                ui.reference('AA', 'Other', 'Fake peek')
            }
        }
    }

    software.visuals = {
        effects = {
            remove_scope_overlay = ui.reference(
                'Visuals', 'Effects', 'Remove scope overlay'
            )
        }
    }

    software.misc = {
        miscellaneous = {
            draw_console_output = ui.reference(
                'Misc', 'Miscellaneous', 'Draw console output'
            )
        },

        settings = {
            menu_color = ui.reference(
                'Misc', 'Settings', 'Menu color'
            ),

            dpi_scale = ui.reference(
                'Misc', 'Settings', 'DPI scale'
            )
        }
    }

    function software.get_dpi()
        local matched = string.match(
            ui.get(software.misc.settings.dpi_scale), '(%d+)%%'
        )

        if not matched then
            return 0
        end

        return matched * 0.01
    end

    function software.get_color(to_hex)
        if to_hex then
            return utils.to_hex(ui.get(software.misc.settings.menu_color))
        end

        return ui.get(software.misc.settings.menu_color)
    end

    function software.get_override_damage()
        return ui.get(software.ragebot.aimbot.minimum_damage_override[3])
    end

    function software.get_minimum_damage()
        return ui.get(software.ragebot.aimbot.minimum_damage)
    end

    function software.is_freestanding()
        return ui.get(software.antiaimbot.angles.freestanding[1])
            and ui.get(software.antiaimbot.angles.freestanding[2])
    end

    function software.is_slow_motion()
        return ui.get(software.antiaimbot.other.slow_motion[1])
            and ui.get(software.antiaimbot.other.slow_motion[2])
    end

    function software.is_double_tap_active()
        return ui.get(software.ragebot.aimbot.double_tap[1])
            and ui.get(software.ragebot.aimbot.double_tap[2])
    end

    function software.is_override_minimum_damage()
        return ui.get(software.ragebot.aimbot.minimum_damage_override[1])
            and ui.get(software.ragebot.aimbot.minimum_damage_override[2])
    end

    function software.is_on_shot_antiaim_active()
        return ui.get(software.antiaimbot.other.on_shot_antiaim[1])
            and ui.get(software.antiaimbot.other.on_shot_antiaim[2])
    end

    function software.is_duck_peek_assist()
        return ui.get(software.ragebot.other.duck_peek_assist)
    end

    function software.is_quick_peek_assist()
        return ui.get(software.ragebot.other.quick_peek_assist[1])
            and ui.get(software.ragebot.other.quick_peek_assist[2])
    end

    return software
end

return M
