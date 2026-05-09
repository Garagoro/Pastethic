-- Pasthetic Server Browser visual draft
-- GameSense / CS:GO Panorama / CSGOMainMenu

local M = {}

function M.start(deps)
deps = deps or {}

local ffi = deps.ffi or require 'ffi'
local client = deps.client or client
local globals = deps.globals or globals
local panorama = deps.panorama or panorama
local is_enabled = deps.is_enabled or function()
    return true
end

local MODULE_UNLOAD_KEY = '__pasthetic_server_browser_unload'
local previous_unload = rawget(_G, MODULE_UNLOAD_KEY)

if type(previous_unload) == 'function' then
    pcall(previous_unload, 'reload')
end

local state = {
    alive = true
}

local ok_steamworks, steamworks = pcall(require, 'gamesense/steamworks')

if not ok_steamworks then
    ok_steamworks, steamworks = pcall(require, 'steamworks')
end

if not ok_steamworks then
    error('server browser: failed to load steamworks library')
end

local DEBUG = false

local function debug_log(message)
    if DEBUG then
        client.log('[SB] ', tostring(message))
    end
end

local SERVER_ADDRESSES = {
    '194.93.2.30:1337',
    '82.147.67.182:27015',
    '170.168.115.50:27315',
    '37.230.162.58:1488',
    '62.122.215.105:6666',
    '194.93.2.41:6666',
    '46.174.52.167:1337',
    '152.89.199.120:27115',
    '46.174.49.245:1337',
    '46.174.51.137:7777',
    '46.174.52.177:1337',
    '37.230.162.128:27015',
    '62.122.214.55:27015',
    '51.77.47.242:27015',
    '45.95.31.113:27315',
    '46.174.50.210:27015',
    '82.208.123.206:27070',
    '46.174.48.195:27015',
    '46.174.53.235:27015',
    '46.174.55.52:1488',
    '185.9.145.160:28541',
    '46.174.50.65:4242',
    '82.208.123.206:27069',
    '46.174.52.69:27015',
    '46.174.55.231:27015',
    '82.147.67.190:27415',
    '195.178.17.11:27015',
    '91.211.118.49:27040',
    '185.248.101.137:30007',
    '46.174.50.130:7777',
    '5.180.82.67:27015',
    '37.230.228.148:27015',
    '46.174.51.108:27015'
}

-- PASTHETIC_SERVER_BROWSER_CACHE_BEGIN
local SERVER_CACHE = {
}
-- PASTHETIC_SERVER_BROWSER_CACHE_END

local SERVERS = {}
local SERVERS_BY_ADDRESS = {}

for i = 1, #SERVER_ADDRESSES do
    local address = SERVER_ADDRESSES[i]
    local cached = SERVER_CACHE[address]

    SERVERS[i] = {
        name = cached and cached.name or address,
        players = cached and cached.players or '-',
        map = cached and cached.map or '-',
        address = address,
        online = cached ~= nil
    }

    SERVERS_BY_ADDRESS[address] = SERVERS[i]
end

local function get_player_count(server)
    local players = tostring(server.players or '')
    local current = players:match('^(%d+)%s*/')

    return tonumber(current) or -1
end

local function visible_servers()
    local visible = {}

    for i = 1, #SERVERS do
        local server = SERVERS[i]

        if server.online and server.players ~= '-' and server.map ~= '-' then
            visible[#visible + 1] = server
        end
    end

    table.sort(visible, function(a, b)
        local a_players = get_player_count(a)
        local b_players = get_player_count(b)

        if a_players ~= b_players then
            return a_players > b_players
        end

        return tostring(a.name) < tostring(b.name)
    end)

    return visible
end

local matchmaking_servers = steamworks.ISteamMatchmakingServers
local ping_response_type = steamworks.ISteamMatchmakingPingResponse
local ping_server = matchmaking_servers and (matchmaking_servers.PingServer or matchmaking_servers.ping_server) or nil
local cancel_server_query = matchmaking_servers and (matchmaking_servers.CancelServerQuery or matchmaking_servers.cancel_server_query) or nil
local make_ping_response = ping_response_type and ping_response_type.new or nil

debug_log('loaded steamworks=' .. tostring(ok_steamworks))
debug_log('matchmaking_servers=' .. tostring(matchmaking_servers) .. ', ping_response_type=' .. tostring(ping_response_type))
debug_log('methods ping=' .. tostring(ping_server) .. ', cancel=' .. tostring(cancel_server_query) .. ', response_new=' .. tostring(make_ping_response))
debug_log('server count=' .. tostring(#SERVER_ADDRESSES))

local steam_query = {
    callback = nil,
    queue_index = 1,
    last_send = 0,
    last_cache_save = 0,
    tick_count = 0,
    pending_address = nil,
    pending_handle = nil,
    pending_started = 0,
    dirty = false,
    cache_dirty = false
}

local save_cache

local function get_script_candidates()
    local candidates = {
        'pasthetic\\server_browser_mainmenu.lua',
        'pasthetic/server_browser_mainmenu.lua',
        'server_browser_mainmenu.lua',
        '.\\server_browser_mainmenu.lua',
        './server_browser_mainmenu.lua'
    }

    local ok, info = pcall(debug.getinfo, 1, 'S')
    if ok and info and type(info.source) == 'string' and info.source:sub(1, 1) == '@' then
        candidates[#candidates + 1] = info.source:sub(2)
    end

    return candidates
end

local function read_script_source()
    if not readfile then
        return nil, nil
    end

    local candidates = get_script_candidates()
    for i = 1, #candidates do
        local path = candidates[i]
        local ok, data = pcall(readfile, path)

        if ok and type(data) == 'string' then
            return data, path
        end
    end

    return nil, nil
end

local function build_cache_block()
    local lines = {
        '-- PASTHETIC_SERVER_BROWSER_CACHE_BEGIN',
        'local SERVER_CACHE = {'
    }

    for i = 1, #SERVERS do
        local server = SERVERS[i]

        if server.name ~= server.address or server.players ~= '-' or server.map ~= '-' then
            lines[#lines + 1] = string.format(
                '    [%q] = { name = %q, players = %q, map = %q },',
                server.address,
                server.name,
                server.players,
                server.map
            )
        end
    end

    lines[#lines + 1] = '}'
    lines[#lines + 1] = '-- PASTHETIC_SERVER_BROWSER_CACHE_END'

    return table.concat(lines, '\n')
end

save_cache = function(force)
    if not force and not steam_query.cache_dirty then
        return false
    end

    if not writefile or not readfile then
        debug_log('cache save unavailable: readfile/writefile missing')
        return false
    end

    local source, path = read_script_source()
    if not source or not path then
        debug_log('cache save failed: script source not found')
        return false
    end

    local block = build_cache_block()
    local pattern = '%-%- PASTHETIC_SERVER_BROWSER_CACHE_BEGIN.-%-%- PASTHETIC_SERVER_BROWSER_CACHE_END'
    local updated, count = source:gsub(pattern, function()
        return block
    end, 1)

    if count == 0 then
        debug_log('cache save failed: markers not found')
        return false
    end

    local ok, err = pcall(writefile, path, updated)
    if not ok then
        debug_log('cache save failed: ' .. tostring(err))
        return false
    end

    steam_query.cache_dirty = false
    debug_log('cache saved to ' .. tostring(path))
    return true
end

local function make_query_callback()
    if steam_query.callback then
        return steam_query.callback
    end

    if not make_ping_response then
        debug_log('cannot create ping response: new method missing')
        return nil
    end

    steam_query.callback = make_ping_response({
        ServerResponded = function(_, item)
            local address = steam_query.pending_address
            debug_log('responded raw for pending=' .. tostring(address))
            steam_query.pending_address = nil
            steam_query.pending_handle = nil
            steam_query.pending_started = 0
 
            if not address then
                return
            end

            local server = SERVERS_BY_ADDRESS[address]
            if not server then
                return
            end

            local name = ffi.string(item.m_szServerName)
            local map = ffi.string(item.m_szMap)
            local players = tonumber(item.m_nPlayers) or 0
            local max_players = tonumber(item.m_nMaxPlayers) or 0

            debug_log(string.format(
                'server ok %s | name="%s" map="%s" players=%d/%d ping=%s',
                address,
                name,
                map,
                players,
                max_players,
                tostring(tonumber(item.m_nPing) or item.m_nPing)
            ))

            if name ~= '' then
                server.name = name
            end

            if map ~= '' then
                server.map = map
            end

            server.players = string.format('%d/%d', players, max_players)
            server.online = true
            steam_query.dirty = true
            steam_query.cache_dirty = true
        end,
        ServerFailedToRespond = function()
            local address = steam_query.pending_address
            debug_log('failed pending=' .. tostring(address))

            if address and SERVERS_BY_ADDRESS[address] then
                SERVERS_BY_ADDRESS[address].online = false
                steam_query.dirty = true
            end

            steam_query.pending_address = nil
            steam_query.pending_handle = nil
            steam_query.pending_started = 0
        end
    })

    return steam_query.callback
end

local function steam_query_tick()
    steam_query.tick_count = steam_query.tick_count + 1

    if steam_query.tick_count <= 3 then
        debug_log('tick #' .. tostring(steam_query.tick_count) .. ' time=' .. tostring(globals.realtime()))
    end

    if not ping_server or not make_ping_response then
        debug_log('steam api missing: ping=' .. tostring(ping_server) .. ' response_new=' .. tostring(make_ping_response))
        return false
    end

    local now = globals.realtime()

    if steam_query.cache_dirty and now - steam_query.last_cache_save > 5.0 then
        steam_query.last_cache_save = now
        save_cache(false)
    end

    if steam_query.pending_address and now - steam_query.pending_started > 2.0 then
        local address = steam_query.pending_address
        debug_log('timeout pending=' .. tostring(address) .. ' handle=' .. tostring(steam_query.pending_handle))
        if steam_query.pending_handle and cancel_server_query then
            pcall(function()
                cancel_server_query(steam_query.pending_handle)
            end)
        end

        if address and SERVERS_BY_ADDRESS[address] then
            SERVERS_BY_ADDRESS[address].online = false
            steam_query.dirty = true
        end

        steam_query.pending_address = nil
        steam_query.pending_handle = nil
        steam_query.pending_started = 0
    end

    if not steam_query.pending_address and now - steam_query.last_send >= 0.20 and #SERVERS > 0 then
        local server = SERVERS[steam_query.queue_index]
        steam_query.queue_index = steam_query.queue_index + 1

        if steam_query.queue_index > #SERVERS then
            steam_query.queue_index = 1
        end

        if server then
            local ip, port = server.address:match('^(%d+%.%d+%.%d+%.%d+):(%d+)$')

            if ip and port then
                debug_log('ping ' .. server.address)
                local ok, handle = pcall(function()
                    return ping_server(ip, tonumber(port), make_query_callback())
                end)

                if ok and handle and handle ~= 0 then
                    debug_log('ping handle ' .. tostring(handle) .. ' for ' .. server.address)
                    steam_query.pending_address = server.address
                    steam_query.pending_handle = handle
                    steam_query.pending_started = now
                else
                    debug_log('ping failed call for ' .. server.address .. ' ok=' .. tostring(ok) .. ' handle=' .. tostring(handle))
                end
            else
                debug_log('invalid address ' .. tostring(server.address))
            end
        end

        steam_query.last_send = now
    end

    if steam_query.dirty then
        steam_query.dirty = false
        return true
    end

    return false
end

local server_browser
local panel_visible = false

local function update_panel_visibility()
    if not state.alive or not server_browser then
        return false
    end

    local in_main_menu = true
    if type(server_browser.is_main_menu) == 'function' then
        local ok, result = pcall(server_browser.is_main_menu)
        in_main_menu = ok and result == true
    end

    local enabled = is_enabled() == true and in_main_menu

    if enabled and not panel_visible then
        server_browser.create(visible_servers())
        panel_visible = true
        return true
    end

    if not enabled and panel_visible then
        server_browser.destroy()
        panel_visible = false
        return true
    end

    if enabled and panel_visible and type(server_browser.update_hittest) == 'function' then
        pcall(server_browser.update_hittest)
    end

    return enabled
end

local function run_query_tick(source)
    if not state.alive then
        return
    end

    local can_render = update_panel_visibility()

    local ok, changed_or_err = xpcall(steam_query_tick, function(err)
        return tostring(err) .. '\n' .. debug.traceback()
    end)

    if not ok then
        debug_log('tick error from ' .. tostring(source) .. ': ' .. tostring(changed_or_err))
        return
    end

    if changed_or_err and can_render and state.alive and server_browser then
        pcall(function()
            server_browser.render(visible_servers())
        end)
    end
end

server_browser = panorama.loadstring([[
    var root = $.GetContextPanel();
    var mainMenu = root;

    while (mainMenu && mainMenu.id !== 'CSGOMainMenu') {
        mainMenu = mainMenu.GetParent();
    }

    if (!mainMenu) {
        mainMenu = root.GetParent() || root;
    }

    var PANEL_ID = 'PastheticSimpleServerBrowser';
    var SHOW_LAYOUT_GUIDES = false;
    var hostPanel = null;

    var C = {
        panel: 'rgba(8, 10, 14, 0.70)',
        line: 'rgba(255,255,255,0.115)',
        name: '#edf3fb',
        meta: '#8994a5',
        connect: '#d8aa63',
        connectHover: '#e8bd78',
        guide: 'rgba(255, 80, 80, 0.55)'
    };

    function cleanup() {
        var old = (hostPanel || mainMenu).FindChildTraverse(PANEL_ID);
        if (old && old.IsValid()) {
            old.DeleteAsync(0.0);
        }
    }

    function resolveHostPanel() {
        var news = mainMenu.FindChildTraverse('JsNewsContainer');

        if (news && news.IsValid()) {
            hostPanel = news;
        } else {
            hostPanel = mainMenu;
        }

        return hostPanel;
    }

    function getNewsPanel() {
        var news = mainMenu.FindChildTraverse('JsNewsContainer');
        return news && news.IsValid() ? news : null;
    }

    function isPanelActuallyVisible(panel) {
        if (!panel || !panel.IsValid()) {
            return false;
        }

        var current = panel;
        while (current && current.IsValid()) {
            try {
                if (current.visible === false) {
                    return false;
                }
            } catch (e) {}

            try {
                if (current.style.visibility === 'collapse' || current.style.opacity === '0') {
                    return false;
                }
            } catch (e) {}

            current = current.GetParent();
        }

        return true;
    }

    function isPanelVisible(panel) {
        if (!panel || !panel.IsValid()) {
            return false;
        }

        try {
            if (panel.visible === false) {
                return false;
            }
        } catch (e) {}

        try {
            if (panel.style.visibility === 'collapse' || panel.style.opacity === '0') {
                return false;
            }
        } catch (e) {}

        return true;
    }

    function getPanelRect(panel) {
        var x = 0;
        var y = 0;

        try {
            var pos = panel.GetPositionWithinWindow();
            if (pos) {
                x = Number(pos.x !== undefined ? pos.x : pos[0]) || 0;
                y = Number(pos.y !== undefined ? pos.y : pos[1]) || 0;
            }
        } catch (e) {
            var current = panel;
            while (current && current.IsValid()) {
                x += Number(current.actualxoffset) || 0;
                y += Number(current.actualyoffset) || 0;
                current = current.GetParent();
            }
        }

        return {
            x: x,
            y: y,
            w: Number(panel.actuallayoutwidth || panel.actualwidth) || 0,
            h: Number(panel.actuallayoutheight || panel.actualheight) || 0
        };
    }

    function rectsOverlap(a, b) {
        if (a.w <= 0 || a.h <= 0 || b.w <= 0 || b.h <= 0) {
            return false;
        }

        return a.x < b.x + b.w &&
            a.x + a.w > b.x &&
            a.y < b.y + b.h &&
            a.y + a.h > b.y;
    }

    function isCoveredByUpperLayer(rootPanel) {
        var targetRect = getPanelRect(rootPanel);
        var current = rootPanel;
        var parent = current.GetParent();

        while (parent && parent.IsValid()) {
            var seenCurrent = false;

            for (var i = 0; i < parent.GetChildCount(); i++) {
                var child = parent.GetChild(i);

                if (child === current) {
                    seenCurrent = true;
                    continue;
                }

                if (!seenCurrent || !child || child === rootPanel || child.id === PANEL_ID) {
                    continue;
                }

                if (isPanelActuallyVisible(child) && rectsOverlap(getPanelRect(child), targetRect)) {
                    return true;
                }
            }

            if (parent === mainMenu) {
                break;
            }

            current = parent;
            parent = current.GetParent();
        }

        return false;
    }

    function setBrowserHitTest(rootPanel, enabled) {
        var value = enabled ? 'true' : 'false';

        try { rootPanel.hittest = enabled; } catch (e) {}
        try { rootPanel.hittestchildren = enabled; } catch (e) {}
        try { rootPanel.style.hittest = value; } catch (e) {}
        try { rootPanel.style.hittestchildren = value; } catch (e) {}
    }

    function updateHitTest() {
        var rootPanel = (hostPanel || mainMenu).FindChildTraverse(PANEL_ID);
        if (!rootPanel || !rootPanel.IsValid()) {
            return false;
        }

        var enabled = !isCoveredByUpperLayer(rootPanel);
        setBrowserHitTest(rootPanel, enabled);
        return enabled;
    }

    function isMainMenu() {
        try {
            if (typeof GameStateAPI !== 'undefined' &&
                GameStateAPI.IsLocalPlayerPlayingMatch &&
                GameStateAPI.IsLocalPlayerPlayingMatch()) {
                return false;
            }
        } catch (e) {}

        return true;
    }

    function panel(parent, id) {
        return $.CreatePanel('Panel', parent, id);
    }

    function label(parent, id, text, color, size, weight) {
        var el = $.CreatePanel('Label', parent, id);
        el.text = text || '';
        el.style.color = color || C.name;
        el.style.fontSize = size || '14px';
        el.style.fontWeight = weight || 'normal';
        el.style.textOverflow = 'ellipsis';
        el.style.whiteSpace = 'nowrap';
        try { el.hittest = false; } catch (e) {}
        try { el.hittestchildren = false; } catch (e) {}
        return el;
    }

    function copyAddress(address, sourcePanel) {
        var copied = false;
        var command = 'connect ' + address;

        try {
            if (typeof SteamOverlayAPI !== 'undefined' && SteamOverlayAPI.CopyTextToClipboard) {
                SteamOverlayAPI.CopyTextToClipboard(command);
                copied = true;
            }
        } catch (e) {}

        try {
            if (!copied && $.DispatchEvent) {
                $.DispatchEvent('CopyToClipboard', command);
                copied = true;
            }
        } catch (e) {}

        UiToolkitAPI.ShowTextTooltip(sourcePanel.id, copied ? 'connect copied' : command);
        $.Schedule(1.15, function() {
            UiToolkitAPI.HideTextTooltip();
        });
    }

    var clickState = {};

    function makeConnectText(parent, id, address) {
        var btn = $.CreatePanel('Button', parent, id);
        btn.style.width = '118px';
        btn.style.height = '18px';
        btn.style.verticalAlign = 'center';
        btn.style.padding = '0px';
        btn.style.backgroundColor = 'rgba(0,0,0,0)';
        btn.style.border = '0px solid rgba(0,0,0,0)';

        var text = label(btn, id + 'Text', address, C.connect, '13px', 'normal');
        text.style.horizontalAlign = 'left';
        text.style.verticalAlign = 'center';
        text.style.textAlign = 'left';
        text.style.width = '100%';
        text.style.height = '18px';

        btn.SetPanelEvent('onmouseover', function() {
            text.style.color = C.connectHover;
        });

        btn.SetPanelEvent('onmouseout', function() {
            text.style.color = C.connect;
        });

        btn.SetPanelEvent('onactivate', function() {
            var now = Date.now();
            var state = clickState[id] || { last: 0, token: 0 };

            if (now - state.last < 320) {
                state.token++;
                state.last = 0;
                clickState[id] = state;

                if (address && address.indexOf(':') !== -1) {
                    GameInterfaceAPI.ConsoleCommand('connect ' + address);
                }
                return;
            }

            state.last = now;
            state.token++;
            var token = state.token;
            clickState[id] = state;

            $.Schedule(0.34, function() {
                var current = clickState[id];
                if (!current || current.token !== token) {
                    return;
                }

                current.last = 0;
                clickState[id] = current;
                copyAddress(address, btn);
            });
        });

        return btn;
    }

    function makeServer(parent, server, index, last) {
        var row = panel(parent, 'PastheticServerRow' + index);
        row.style.width = '100%';
        row.style.height = '46px';
        row.style.flowChildren = 'right';
        row.style.padding = '0px 2px';

        var name = label(row, 'PastheticServerName' + index, server.name, C.name, '17px', 'bold');
        name.style.width = 'fill-parent-flow(1.0)';
        name.style.verticalAlign = 'center';

        if (SHOW_LAYOUT_GUIDES) {
            var nameGuide = panel(row, 'PastheticGuideName' + index);
            nameGuide.style.width = '1px';
            nameGuide.style.height = '100%';
            nameGuide.style.backgroundColor = C.guide;
            nameGuide.style.marginLeft = '0px';
        }

        var players = label(row, 'PastheticServerPlayers' + index, server.players, C.meta, '13px', 'normal');
        players.style.width = '42px';
        players.style.verticalAlign = 'center';
        players.style.marginLeft = '20px';

        if (SHOW_LAYOUT_GUIDES) {
            var playersGuide = panel(row, 'PastheticGuidePlayers' + index);
            playersGuide.style.width = '1px';
            playersGuide.style.height = '100%';
            playersGuide.style.backgroundColor = C.guide;
            playersGuide.style.marginLeft = '0px';
        }

        var map = label(row, 'PastheticServerMap' + index, server.map, C.meta, '13px', 'normal');
        map.style.marginLeft = '14px';
        map.style.width = '82px';
        map.style.verticalAlign = 'center';

        if (SHOW_LAYOUT_GUIDES) {
            var mapGuide = panel(row, 'PastheticGuideMap' + index);
            mapGuide.style.width = '1px';
            mapGuide.style.height = '100%';
            mapGuide.style.backgroundColor = C.guide;
            mapGuide.style.marginLeft = '0px';
        }

        var actions = panel(row, 'PastheticServerActions' + index);
        actions.style.height = '100%';
        actions.style.width = '118px';
        actions.style.flowChildren = 'right';
        actions.style.verticalAlign = 'center';

        if (SHOW_LAYOUT_GUIDES) {
            var actionGuide = panel(row, 'PastheticGuideAction' + index);
            actionGuide.style.width = '1px';
            actionGuide.style.height = '100%';
            actionGuide.style.backgroundColor = C.guide;
            actionGuide.style.marginLeft = '0px';
        }

        makeConnectText(actions, 'PastheticConnectText' + index, server.address);

        if (!last) {
            var line = panel(parent, 'PastheticServerLine' + index);
            line.style.width = '100%';
            line.style.height = '1px';
            line.style.backgroundColor = C.line;
        }
    }

    function create(servers) {
        cleanup();

        var host = resolveHostPanel();
        var news = getNewsPanel();
        var insideNews = news && host === news;
        var rootPanel = panel(host, PANEL_ID);
        rootPanel.style.width = '719px';
        rootPanel.style.height = '1000px';
        rootPanel.style.horizontalAlign = 'left';
        rootPanel.style.verticalAlign = 'top';
        rootPanel.style.marginLeft = insideNews ? '0px' : '130px';
        rootPanel.style.marginTop = insideNews ? '0px' : '55px';
        rootPanel.style.flowChildren = 'down';
        rootPanel.style.overflow = 'clip';
        rootPanel.style.padding = '20px 22px';
        rootPanel.style.backgroundColor = C.panel;
        rootPanel.style.border = '0px solid rgba(0,0,0,0)';
        rootPanel.style.borderRadius = '0px';
        rootPanel.style.boxShadow = 'none';

        if (news && !insideNews) {
            host.MoveChildBefore(rootPanel, news);
        } else if (!insideNews) {
            host.MoveChildBefore(rootPanel, host.GetChild(0));
        }

        render(servers);
        updateHitTest();
    }

    function render(servers) {
        var rootPanel = (hostPanel || mainMenu).FindChildTraverse(PANEL_ID);

        if (!rootPanel) {
            create(servers);
            return;
        }

        rootPanel.RemoveAndDeleteChildren();

        for (var i = 0; i < servers.length; i++) {
            makeServer(rootPanel, servers[i], i, i === servers.length - 1);
        }

        updateHitTest();
    }

    return {
        create: create,
        render: render,
        update_hittest: updateHitTest,
        is_main_menu: isMainMenu,
        destroy: cleanup
    };
]], 'CSGOMainMenu')()

local function unload(reason)
    if not state.alive then
        return
    end

    state.alive = false

    pcall(function()
        save_cache(true)
    end)

    if steam_query.pending_handle and cancel_server_query then
        pcall(function()
            cancel_server_query(steam_query.pending_handle)
        end)
    end

    steam_query.pending_address = nil
    steam_query.pending_handle = nil
    steam_query.pending_started = 0
    steam_query.callback = nil

    if server_browser then
        pcall(function()
            server_browser.destroy()
        end)
    end

    if rawget(_G, MODULE_UNLOAD_KEY) == unload then
        _G[MODULE_UNLOAD_KEY] = nil
    end
end

_G[MODULE_UNLOAD_KEY] = unload

update_panel_visibility()

client.set_event_callback('paint', function()
    if state.alive then
        run_query_tick('paint')
    end
end)

client.set_event_callback('paint_ui', function()
    if state.alive then
        run_query_tick('paint_ui')
    end
end)

client.set_event_callback('shutdown', function()
    unload('shutdown')
end)

end

return M
