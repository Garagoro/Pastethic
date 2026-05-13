local M = {}

function M.start(deps)
    local resource = assert(deps.resource, 'misc_sync_ragebot_hotkeys: resource dependency is required')
    local ui = assert(deps.ui, 'misc_sync_ragebot_hotkeys: ui dependency is required')
    local ui_callback = assert(deps.ui_callback, 'misc_sync_ragebot_hotkeys: ui_callback dependency is required')

    local ref = resource.main.miscellaneous.sync_ragebot_hotkeys

    local weapons = {
        'Global',
        'G3SG1 / SCAR-20',
        'SSG 08',
        'AWP',
        'R8 Revolver',
        'Desert Eagle',
        'Pistol',
        'Zeus',
        'Rifle',
        'Shotgun',
        'SMG',
        'Machine gun'
    }

    local ref_weapon_type = ui.reference('Rage', 'Weapon type', 'Weapon type')
    local ref_enabled = { ui.reference('Rage', 'Aimbot', 'Enabled') }
    local ref_multipoint = { ui.reference('Rage', 'Aimbot', 'Multi-point') }
    local ref_minimum_damage_override = { ui.reference('Rage', 'Aimbot', 'Minimum damage override') }
    local ref_force_safe_point = ui.reference('Rage', 'Aimbot', 'Force safe point')
    local ref_force_body_aim = ui.reference('Rage', 'Aimbot', 'Force body aim')
    local ref_quick_stop = { ui.reference('Rage', 'Aimbot', 'Quick stop') }
    local ref_double_tap = { ui.reference('Rage', 'Aimbot', 'Double tap') }

    local function set_callback(item, callback, value)
        if value ~= false then
            ui_callback.set(item, callback)
        else
            ui_callback.unset(item, callback)
        end
    end

    local function on_hotkey(item)
        local _, _, key = ui.get(item)
        local old_weapon = ui.get(ref_weapon_type)

        for i = 1, #weapons do
            local weapon = weapons[i]

            ui.set(ref_weapon_type, weapon)

            local _, state = ui.get(item)
            ui.set(item, state, key or 0)
        end

        ui.set(ref_weapon_type, old_weapon)
    end

    local function on_enabled(item)
        local value = item:get()

        set_callback(ref_enabled[2], on_hotkey, value)
        set_callback(ref_multipoint[2], on_hotkey, value)
        set_callback(ref_minimum_damage_override[2], on_hotkey, value)
        set_callback(ref_force_safe_point, on_hotkey, value)
        set_callback(ref_force_body_aim, on_hotkey, value)
        set_callback(ref_quick_stop[2], on_hotkey, value)
        set_callback(ref_double_tap[2], on_hotkey, value)
    end

    ref.enabled:set_callback(on_enabled, true)
end

return M
