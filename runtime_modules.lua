local M = {}

function M.start(ctx)
    ctx = ctx or {}

    local require_pasthetic_module = assert(ctx.require_module, 'runtime_modules: require_module dependency is required')

    local pasthetic_rage_force_lethal = require_pasthetic_module 'pasthetic/rage_force_lethal'
    local pasthetic_rage_allow_duck_on_fd = require_pasthetic_module 'pasthetic/rage_allow_duck_on_fd'
    local pasthetic_rage_unsafe_recharge = require_pasthetic_module 'pasthetic/rage_unsafe_recharge'
    local pasthetic_rage_hideshots_fix = require_pasthetic_module 'pasthetic/rage_hideshots_fix'
    local pasthetic_rage_force_body_conditions = require_pasthetic_module 'pasthetic/rage_force_body_conditions'
    local pasthetic_rage_hitchance = require_pasthetic_module 'pasthetic/rage_hitchance'
    local pasthetic_rage_auto_whitelist_broken_lc = require_pasthetic_module 'pasthetic/rage_auto_whitelist_broken_lc'
    local pasthetic_rage_peek_assist = require_pasthetic_module 'pasthetic/rage_peek_assist'
    local pasthetic_misc_fast_ladder = require_pasthetic_module 'pasthetic/misc_fast_ladder'
    local pasthetic_misc_console_filter = require_pasthetic_module 'pasthetic/misc_console_filter'
    local pasthetic_misc_sync_ragebot_hotkeys = require_pasthetic_module 'pasthetic/misc_sync_ragebot_hotkeys'
    local pasthetic_misc_reveal_enemy_team_chat = require_pasthetic_module 'pasthetic/misc_reveal_enemy_team_chat'
    local pasthetic_clantag = require_pasthetic_module 'pasthetic/clantag'
    local pasthetic_automatic_purchase = require_pasthetic_module 'pasthetic/automatic_purchase'
    local pasthetic_anim_breaker = require_pasthetic_module 'pasthetic/anim_breaker'
    local pasthetic_logging_system = require_pasthetic_module 'pasthetic/logging_system'
    local pasthetic_antiaim = require_pasthetic_module 'pasthetic/antiaim'
    local pasthetic_antiaim_presets = require_pasthetic_module 'pasthetic/antiaim_presets'
    local pasthetic_item_crash_fix = require_pasthetic_module 'pasthetic/item_crash_fix'
    local pasthetic_world_enhancer = require_pasthetic_module 'pasthetic/world_enhancer'

    local script = ctx.script
    local resource = ctx.resource
    local diagnostics = assert(ctx.diagnostics, 'runtime_modules: diagnostics dependency is required')
    local ui = ctx.ui or ui
    local entity = ctx.entity or entity
    local client = ctx.client or client
    local globals = ctx.globals or globals
    local vector = ctx.vector
    local plist = ctx.plist or plist
    local csgo_weapons = ctx.csgo_weapons
    local ragebot = ctx.ragebot
    local utils = ctx.utils
    local unpack = ctx.unpack or unpack
    local session = ctx.session
    local renderer = ctx.renderer or renderer
    local software = ctx.software
    local exploit = ctx.exploit
    local localplayer = ctx.localplayer
    local override = ctx.override
    local bit = ctx.bit or bit
    local toticks = ctx.toticks or toticks
    local cvar = ctx.cvar or cvar
    local ui_callback = ctx.ui_callback
    local panorama = ctx.panorama or panorama
    local chat = ctx.chat
    local localize = ctx.localize
    local color = ctx.color
    local motion = ctx.motion
    local surface = ctx.surface
    local text_fmt = ctx.text_fmt
    local totime = ctx.totime or totime
    local c_entity = ctx.c_entity
    local statement = ctx.statement
    local ffi = ctx.ffi
    local materialsystem = ctx.materialsystem or materialsystem

    local main do
        local rage do
            diagnostics:start('rage_force_body_conditions', function()
                return pasthetic_rage_force_body_conditions.start({
                resource = resource,
                ui = ui,
                entity = entity,
                client = client,
                vector = vector,
                plist = plist,
                csgo_weapons = csgo_weapons,
                ragebot = ragebot,
                utils = utils,
                unpack = unpack
            })
            end)

            diagnostics:start('rage_force_lethal', function()
                return pasthetic_rage_force_lethal.start({
                resource = resource,
                session = session,
                ui = ui,
                entity = entity,
                client = client,
                renderer = renderer,
                csgo_weapons = csgo_weapons,
                software = software,
                exploit = exploit,
                ragebot = ragebot,
                utils = utils
            })
            end)


            diagnostics:start('rage_allow_duck_on_fd', function()
                return pasthetic_rage_allow_duck_on_fd.start({
                resource = resource,
                ui = ui,
                entity = entity,
                localplayer = localplayer,
                override = override,
                utils = utils
            })
            end)

            diagnostics:start('rage_unsafe_recharge', function()
                return pasthetic_rage_unsafe_recharge.start({
                resource = resource,
                bit = bit,
                ui = ui,
                globals = globals,
                entity = entity,
                client = client,
                csgo_weapons = csgo_weapons,
                exploit = exploit,
                ragebot = ragebot,
                utils = utils
            })
            end)

            diagnostics:start('rage_hideshots_fix', function()
                return pasthetic_rage_hideshots_fix.start({
                resource = resource,
                ui = ui,
                software = software,
                override = override,
                utils = utils
            })
            end)

            diagnostics:start('rage_hitchance', function()
                return pasthetic_rage_hitchance.start({
                resource = resource,
                session = session,
                ui = ui,
                entity = entity,
                client = client,
                vector = vector,
                renderer = renderer,
                csgo_weapons = csgo_weapons,
                software = software,
                exploit = exploit,
                localplayer = localplayer,
                ragebot = ragebot,
                utils = utils
            })
            end)

            diagnostics:start('rage_auto_whitelist_broken_lc', function()
                return pasthetic_rage_auto_whitelist_broken_lc.start({
                resource = resource,
                entity = entity,
                client = client,
                globals = globals,
                vector = vector,
                plist = plist,
                utils = utils,
                toticks = toticks,
                software = software
            })
            end)
            diagnostics:start('rage_peek_assist', function()
                return pasthetic_rage_peek_assist.start({
                resource = resource,
                ui = ui,
                entity = entity,
                csgo_weapons = csgo_weapons,
                software = software,
                localplayer = localplayer,
                ragebot = ragebot,
                utils = utils
            })
            end)
        end

        diagnostics:start('anim_breaker', function()
            return pasthetic_anim_breaker.start({
                resource = resource,
                ui = ui,
                entity = entity,
                client = client,
                globals = globals,
                utils = utils,
                localplayer = localplayer,
                software = software,
                override = override,
                ragebot = ragebot,
                c_entity = c_entity
            })
        end)
        diagnostics:health('anim_breaker', pasthetic_anim_breaker)
        local miscellaneous do

            diagnostics:start('misc_fast_ladder', function()
                return pasthetic_misc_fast_ladder.start({
                resource = resource,
                entity = entity,
                client = client,
                utils = utils
            })
            end)

            diagnostics:start('misc_console_filter', function()
                return pasthetic_misc_console_filter.start({
                resource = resource,
                cvar = cvar,
                client = client
            })
            end)

            diagnostics:start('misc_sync_ragebot_hotkeys', function()
                return pasthetic_misc_sync_ragebot_hotkeys.start({
                resource = resource,
                ui = ui,
                ui_callback = ui_callback
            })
            end)

            diagnostics:start('misc_reveal_enemy_team_chat', function()
                return pasthetic_misc_reveal_enemy_team_chat.start({
                resource = resource,
                panorama = panorama,
                cvar = cvar,
                client = client,
                entity = entity,
                globals = globals,
                chat = chat,
                localize = localize,
                utils = utils
            })
            end)

            diagnostics:start('clantag', function()
                return pasthetic_clantag.start({
                    resource = resource,
                    client = client,
                    globals = globals,
                    utils = utils
                })
            end)
        end

        diagnostics:start('logging_system', function()
            return pasthetic_logging_system.start({
                script = script,
                resource = resource,
                ui = ui,
                entity = entity,
                client = client,
                globals = globals,
                utils = utils,
                software = software,
                override = override,
                vector = vector,
                renderer = renderer,
                color = color,
                motion = motion,
                surface = surface,
                text_fmt = text_fmt
            })
        end)
        diagnostics:health('logging_system', pasthetic_logging_system)
        diagnostics:start('automatic_purchase', function()
            return pasthetic_automatic_purchase.start({
            resource = resource,
            cvar = cvar,
            entity = entity,
            client = client,
            csgo_weapons = csgo_weapons,
            utils = utils,
            totime = totime
        })
        end)
    end

    diagnostics:start('antiaim', function()
        return pasthetic_antiaim.start({
            resource = resource,
            ui = ui,
            entity = entity,
            client = client,
            globals = globals,
            utils = utils,
            localplayer = localplayer,
            software = software,
            override = override,
            vector = vector,
            c_entity = c_entity,
            statement = statement,
            csgo_weapons = csgo_weapons,
            exploit = exploit,
            bit = bit,
            toticks = toticks,
            presets = pasthetic_antiaim_presets
        })
    end)
    diagnostics:health('antiaim_presets', pasthetic_antiaim_presets)
    diagnostics:health('antiaim', pasthetic_antiaim)
    -- ============================================
    -- CRASH FIX (always enabled)
    -- ============================================
    local item_crash_fix = diagnostics:start('item_crash_fix', function()
        return pasthetic_item_crash_fix.start({
            ffi = ffi,
            client = client
        })
    end)


    diagnostics:start('world_enhancer', function()
        return pasthetic_world_enhancer.start({
            resource = resource,
            ui = ui,
            client = client,
            entity = entity,
            globals = globals,
            renderer = renderer,
            cvar = cvar,
            materialsystem = materialsystem,
            bit = bit
        })
    end)
    diagnostics:health('world_enhancer', pasthetic_world_enhancer)

    diagnostics:summary()

end

return M
