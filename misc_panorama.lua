local M = {}

local OPTION_CSLOGO = 'CS:GO Logo'
local OPTION_NEWS = 'Remove News and Shop'
local OPTION_SERVER_BROWSER = 'Server Browser'
local OPTION_BACKGROUND = 'Change background'
local OPTION_STATS = 'Remove stats button'
local OPTION_WATCH = 'Remove watch button'
local OPTION_SIDEBAR = 'Remove sidebar'
local OPTION_MODEL = 'Remove model in mainmenu'

local LOGO_OUTDATED_URL = 'https://raw.githubusercontent.com/Garagoro/Pasthetic/refs/heads/main/logo%202.png'
local LOGO_DEFAULT_URL = 'https://raw.githubusercontent.com/Garagoro/Pasthetic/refs/heads/main/logo%203.png'

local function array_contains(array, value)
    if type(array) ~= 'table' then
        return false
    end

    for i = 1, #array do
        if array[i] == value then
            return true
        end
    end

    return false
end

function M.start(deps)
    local panorama = assert(deps.panorama, 'misc_panorama: panorama dependency is required')
    local get_options = assert(deps.get_options, 'misc_panorama: get_options dependency is required')
    local has_update = deps.has_update or function()
        return false
    end

    local creator_logo_url = deps.creator_logo_url
    if creator_logo_url == nil then
        local ok, creator_logo = pcall(require, 'pasthetic/creator_logo')
        if ok then
            if type(creator_logo) == 'string' then
                creator_logo_url = creator_logo
            elseif type(creator_logo) == 'table' then
                creator_logo_url = creator_logo.url or (type(creator_logo.get_url) == 'function' and creator_logo.get_url())
            end
        end
    end

    local function get_logo_url()
        if type(creator_logo_url) == 'string' and creator_logo_url ~= '' then
            return creator_logo_url
        end

        return has_update() and LOGO_OUTDATED_URL or LOGO_DEFAULT_URL
    end

    local state = {
        cslogo = false,
        logo_url = nil,
        news = false,
        background = false,
        stats = false,
        watch = false,
        sidebar = false,
        model = false
    }

    local cs_logo = panorama.loadstring([[
        var panel = null;
        var cs_logo = null;
        var original_transform = null;
        var original_visibility = null;

        var _Create = function(imageUrl) {
            cs_logo = $.GetContextPanel().FindChildTraverse("MainMenuNavBarHome");
            if (!cs_logo) {
                return;
            }

            original_transform = cs_logo.style.transform || 'none';
            original_visibility = cs_logo.style.visibility || 'visible';

            cs_logo.style.transform = 'translate3d(-9999px, -9999px, 0)';
            cs_logo.style.visibility = 'collapse';

            var parent = cs_logo.GetParent();
            if (!parent) {
                return;
            }

            panel = $.CreatePanel("Panel", parent, "CustomPanel");
            if (!panel) {
                return;
            }

            if (!panel.BLoadLayoutFromString(
            `<root>
                <Panel class="mainmenu-navbar__btn-small mainmenu-navbar__btn-home MainMenuModeOnly">
                    <RadioButton id="main_menu"
                        style="width: 100%; height: 100%; horizontal-align: center; vertical-align: center;"
                        onactivate="MainMenu.OnHomeButtonPressed(); $.DispatchEvent( 'PlaySoundEffect', 'UIPanorama.mainmenu_press_home', 'MOUSE' ); $.DispatchEvent('PlayMainMenuMusic', true, true); GameInterfaceAPI.SetSettingString('panorama_play_movie_ambient_sound', '1');"
                        oncancel="MainMenu.OnEscapeKeyPressed();"
                        onmouseover="UiToolkitAPI.ShowTextTooltip('main_menu', 't.me/debugoverlay');"
                        onmouseout="UiToolkitAPI.HideTextTooltip();">
                        <Image textureheight="55" texturewidth="-1" src="${imageUrl}"
                            style="horizontal-align: center; vertical-align: center;" />
                    </RadioButton>
                </Panel>
            </root>`,
        false, false)) {
            panel.DeleteAsync(0);
            panel = null;
            return;
            }

            parent.MoveChildBefore(panel, parent.GetChild(0));
        };

        var _Destroy = function() {
            if (cs_logo) {
            if (panel) {
                panel.DeleteAsync(0.0);
                panel = null;
            }

            cs_logo.style.transform = original_transform;
            cs_logo.style.visibility = original_visibility;
            }
        };

        return {
            create: _Create,
            destroy: _Destroy,
        };
    ]], 'CSGOMainMenu')()

    local news_container = panorama.loadstring([[
        var panel = null;
        var js_news = null;
        var original_transform = null;
        var original_visibility = null;

        var _Create = function() {
            js_news = $.GetContextPanel().FindChildTraverse("JsNewsContainer");
            if (!js_news) {
                return;
            }

            original_transform = js_news.style.transform || 'none';
            original_visibility = js_news.style.visibility || 'visible';

            js_news.style.transform = 'translate3d(-9999px, -9999px, 0)';
            js_news.style.visibility = 'collapse';

            var parent = js_news.GetParent();
            if (!parent) {
                return;
            }

            panel = $.CreatePanel("Panel", parent, "news_panel");
            if(!panel) {
                return;
            }

            parent.MoveChildBefore(panel, js_news);
        };

        var _Destroy = function() {
            if (js_news) {
                if (panel) {
                    panel.DeleteAsync(0.0);
                    panel = null;
                }

                js_news.style.transform = original_transform;
                js_news.style.visibility = original_visibility;
            }
        };

        return {
            create: _Create,
            destroy: _Destroy,
        };
    ]], 'CSGOMainMenu')()

    local background = panorama.loadstring([[
        var _ChangeBackground = function(imageUrl) {
            var movieElements = [
                "MainMenuMovie",
                "MainMenuMovieParent",
                "MoviePlayer"
            ];

            movieElements.forEach(function(id) {
                var element = $.GetContextPanel().FindChildTraverse(id);
                if (element) {
                    element.style.opacity = "0";
                    element.style.visibility = "collapse";
                }
            });

            var bgElements = [
                "MainMenuBackground",
                "MainMenu",
                "MainMenuContainerPanel"
            ];

            bgElements.forEach(function(id) {
                var panel = $.GetContextPanel().FindChildTraverse(id);
                if (panel) {
                    panel.style.backgroundImage = 'url("' + imageUrl + '")';
                    panel.style.backgroundPosition = 'center';
                    panel.style.backgroundSize = 'cover';
                    panel.style.backgroundRepeat = 'no-repeat';
                    panel.style.opacity = "1";
                }
            });
        };

        var _RestoreDefault = function() {
            var movieElements = [
                "MainMenuMovie",
                "MainMenuMovieParent",
                "MoviePlayer"
            ];

            movieElements.forEach(function(id) {
                var element = $.GetContextPanel().FindChildTraverse(id);
                if (element) {
                    element.style.opacity = "1";
                    element.style.visibility = "visible";
                }
            });

            var bgElements = [
                "MainMenuBackground",
                "MainMenu",
                "MainMenuContainerPanel"
            ];

            bgElements.forEach(function(id) {
                var panel = $.GetContextPanel().FindChildTraverse(id);
                if (panel) {
                    panel.style.backgroundImage = 'none';
                }
            });
        };

        return {
            change: _ChangeBackground,
            restore: _RestoreDefault
        };
    ]], 'CSGOMainMenu')()

    local stats_button = panorama.loadstring([[
        var panel = null;
        var watch_btn = null;
        var original_transform = null;
        var original_visibility = null;

        var _Create = function() {
            watch_btn = $.GetContextPanel().FindChildTraverse("MainMenuNavBarStats");

            if (!watch_btn) {
                return;
            }

            original_transform = watch_btn.style.transform || 'none';
            original_visibility = watch_btn.style.visibility || 'visible';

            watch_btn.style.transform = 'translate3d(-9999px, -9999px, 0)';
            watch_btn.style.visibility = 'collapse';

            var parent = watch_btn.GetParent();
            if (!parent) {
                return;
            }

            panel = $.CreatePanel("RadioButton", parent, "custom_stats_button");
            if (!panel) {
                return;
            }

            parent.MoveChildBefore(panel, watch_btn);
        };

        var _Destroy = function() {
            if (watch_btn) {
                if (panel) {
                    panel.DeleteAsync(0.0);
                    panel = null;
                }
                watch_btn.style.transform = original_transform;
                watch_btn.style.visibility = original_visibility;
            }
        };

        return {
            hide: _Create,
            show: _Destroy
        };
    ]], 'CSGOMainMenu')()

    local watch_button = panorama.loadstring([[
        var panel = null;
        var watch_btn = null;
        var original_transform = null;
        var original_visibility = null;

        var _Create = function() {
            watch_btn = $.GetContextPanel().FindChildTraverse("MainMenuNavBarWatch");

            if (!watch_btn) {
                return;
            }

            original_transform = watch_btn.style.transform || 'none';
            original_visibility = watch_btn.style.visibility || 'visible';

            watch_btn.style.transform = 'translate3d(-9999px, -9999px, 0)';
            watch_btn.style.visibility = 'collapse';

            var parent = watch_btn.GetParent();
            if (!parent) {
                return;
            }

            panel = $.CreatePanel("RadioButton", parent, "custom_watch_button");
            if (!panel) {
                return;
            }

            parent.MoveChildBefore(panel, watch_btn);
        };

        var _Destroy = function() {
            if (watch_btn) {
                if (panel) {
                    panel.DeleteAsync(0.0);
                    panel = null;
                }
                watch_btn.style.transform = original_transform;
                watch_btn.style.visibility = original_visibility;
            }
        };

        return {
            hide: _Create,
            show: _Destroy
        };
    ]], 'CSGOMainMenu')()

    local remove_sidebar = panorama.loadstring([[
        var panel = null;
        var original_panel = null;

        var _Create = function() {
            original_panel = $.GetContextPanel().FindChildTraverse("JsMainMenuSidebar");

            if (!original_panel) return;

            original_panel.style.visibility = "collapse";
            var parent = original_panel.GetParent();
            if (!parent) return;

            panel = $.CreatePanel("Panel", parent, "custom_sidebar_panel");
            if (!panel) return;
        };

        var _Destroy = function() {
            if (panel) {
                panel.DeleteAsync(0.0);
                panel = null;
            }
            if (original_panel) {
                original_panel.style.visibility = "visible";
            }
        };

        return {
            hide: _Create,
            show: _Destroy
        };
    ]], 'CSGOMainMenu')()

    local remove_model = panorama.loadstring([[
        var panel = null;
        var original_panel = null;

        var _Create = function() {
            original_panel = $.GetContextPanel().FindChildTraverse("MainMenuVanityParent");

            if (!original_panel) return;

            original_panel.style.visibility = "collapse";
            var parent = original_panel.GetParent();
            if (!parent) return;

            panel = $.CreatePanel("Panel", parent, "custom_model_panel");
            if (!panel) return;
        };

        var _Destroy = function() {
            if (panel) {
                panel.DeleteAsync(0.0);
                panel = null;
            }
            if (original_panel) {
                original_panel.style.visibility = "visible";
            }
        };

        return {
            hide: _Create,
            show: _Destroy
        };
    ]], 'CSGOMainMenu')()

    local api = {}

    function api.create()
        local options = get_options()
        local logo_url = get_logo_url()
        local settings = {
            cslogo = array_contains(options, OPTION_CSLOGO),
            logo_url = logo_url,
            news = array_contains(options, OPTION_NEWS) or array_contains(options, OPTION_SERVER_BROWSER),
            background = array_contains(options, OPTION_BACKGROUND),
            stats = array_contains(options, OPTION_STATS),
            watch = array_contains(options, OPTION_WATCH),
            sidebar = array_contains(options, OPTION_SIDEBAR),
            model = array_contains(options, OPTION_MODEL)
        }

        if settings.cslogo ~= state.cslogo or (settings.cslogo and settings.logo_url ~= state.logo_url) then
            if settings.cslogo then
                cs_logo.destroy()
                cs_logo.create(settings.logo_url)
            else
                cs_logo.destroy()
            end
            state.cslogo = settings.cslogo
            state.logo_url = settings.logo_url
        end

        if settings.news ~= state.news then
            if settings.news then
                news_container.create()
            else
                news_container.destroy()
            end
            state.news = settings.news
        end

        if settings.background ~= state.background then
            if settings.background then
                background.change('https://raw.githubusercontent.com/uwukson4800/paranoia-gs/refs/heads/main/background.png')
            else
                background.restore()
            end
            state.background = settings.background
        end

        if settings.stats ~= state.stats then
            if settings.stats then
                stats_button.hide()
            else
                stats_button.show()
            end
            state.stats = settings.stats
        end

        if settings.watch ~= state.watch then
            if settings.watch then
                watch_button.hide()
            else
                watch_button.show()
            end
            state.watch = settings.watch
        end

        if settings.sidebar ~= state.sidebar then
            if settings.sidebar then
                remove_sidebar.hide()
            else
                remove_sidebar.show()
            end
            state.sidebar = settings.sidebar
        end

        if settings.model ~= state.model then
            if settings.model then
                remove_model.hide()
            else
                remove_model.show()
            end
            state.model = settings.model
        end
    end

    function api.shutdown()
        cs_logo.destroy()
        news_container.destroy()
        background.restore()
        stats_button.show()
        watch_button.show()
        remove_sidebar.show()
        remove_model.show()
    end

    return api
end

return M
