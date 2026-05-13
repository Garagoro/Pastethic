local M = {}

function M.new_globalvars(deps)
    deps = deps or {}

    local ffi = deps.ffi or ffi
    local utils = deps.utils

    local globalvars_t = ffi.typeof [[
        struct {
            float   realtime;
            int     framecount;
            float   absoluteframetime;
            float   absoluteframestarttimestddev;
            float   curtime;
            float   frametime;
            int     max_clients;
            int     tickcount;
            float   interval_per_tick;
            float   interpolation_amount;
            int     simTicksThisFrame;
            int     network_protocol;
            void*   pSaveData;
            bool    m_bClient;
            bool    m_bRemoteClient;
        } ***
    ]]

    local globalvars_ptr = utils.find_signature(
        'client.dll', '\xA1\xCC\xCC\xCC\xCC\x5E\x8B\x40\x10', 0x1
    )

    if globalvars_ptr == nil then
        error 'Unable to find CGlobalVarsBase'
    end

    return ffi.cast(globalvars_t, globalvars_ptr)[0][0]
end

function M.new_ilocalize(deps)
    deps = deps or {}

    local vtable_bind = deps.vtable_bind or vtable_bind
    local ilocalize = {}
    local ConvertAnsiToUnicode = vtable_bind(
        'localize.dll', 'Localize_001', 15, 'int(__thiscall*)(void*, const char *ansi, wchar_t *unicode, int buffer_size)'
    )

    function ilocalize.ansi_to_unicode(ansi, unicode, buffer_size)
        return ConvertAnsiToUnicode(ansi, unicode, buffer_size)
    end

    return ilocalize
end

function M.new_ifilesystem(deps)
    deps = deps or {}

    local ffi = deps.ffi or ffi
    local vtable_bind = deps.vtable_bind or vtable_bind
    local ifilesystem = {}

    local AddSearchPath = vtable_bind('filesystem_stdio.dll', 'VFileSystem017', 11, ffi.typeof [[
        void(__thiscall*)(void*, const char *pPath, const char *pathID, int addType)
    ]])

    local RemoveSearchPath = vtable_bind('filesystem_stdio.dll', 'VFileSystem017', 12, ffi.typeof [[
        bool(__thiscall*)(void*, const char *pPath, const char *pathID)
    ]])

    local CurrentDirectory = vtable_bind('filesystem_stdio.dll', 'VFileSystem017', 40, ffi.typeof [[
        bool(__thiscall*)(void*, char* pDirectory, int maxlen)
    ]])

    local FindFirst = vtable_bind('filesystem_stdio.dll', 'VFileSystem017', 32, ffi.typeof [[
        const char*(__thiscall*)(void*, const char *pWildCard, int *pHandle)
    ]])

    local FindNext = vtable_bind('filesystem_stdio.dll', 'VFileSystem017', 33, ffi.typeof [[
        const char*(__thiscall*)(void*, int handle)
    ]])

    local FindIsDirectory = vtable_bind('filesystem_stdio.dll', 'VFileSystem017', 34, ffi.typeof [[
        bool(__thiscall*)(void*, int handle)
    ]])

    local FindClose = vtable_bind('filesystem_stdio.dll', 'VFileSystem017', 35, ffi.typeof [[
        void(__thiscall*)(void*, int handle)
    ]])

    local FindFirstEx = vtable_bind('filesystem_stdio.dll', 'VFileSystem017', 36, ffi.typeof [[
        const char*(__thiscall*)(void*, const char *pWildCard, const char *pathID, int *pHandle)
    ]])

    function ifilesystem.add_search_path(path, path_id, add_type)
        AddSearchPath(path, path_id, add_type)
    end

    function ifilesystem.remove_search_path(path, path_id)
        return RemoveSearchPath(path, path_id)
    end

    function ifilesystem.current_directory(buffer, maxlen)
        return CurrentDirectory(buffer, maxlen)
    end

    function ifilesystem.find_first(wild_card, handle)
        return FindFirst(wild_card, handle)
    end

    function ifilesystem.find_next(handle)
        return FindNext(handle)
    end

    function ifilesystem.find_is_directory(handle)
        return FindIsDirectory(handle)
    end

    function ifilesystem.find_close(handle)
        FindClose(handle)
    end

    function ifilesystem.find_first_ex(wild_card, path_id, handle)
        return FindFirstEx(wild_card, path_id, handle)
    end

    return ifilesystem
end

function M.new_surface(deps)
    deps = deps or {}

    local ffi = deps.ffi or ffi
    local vtable_bind = deps.vtable_bind or vtable_bind
    local ilocalize = deps.ilocalize
    local surface = {}

    local wide = ffi.new 'int[1]'
    local tall = ffi.new 'int[1]'

    local SetColor = vtable_bind('vguimatsurface.dll', 'VGUI_Surface031', 15, 'void(__thiscall*)(void* thisptr, int r, int g, int b, int a)')

    local SetTextFont = vtable_bind('vguimatsurface.dll', 'VGUI_Surface031', 23, 'void(__thiscall*)(void*, unsigned int font_id)')
    local SetTextColor = vtable_bind('vguimatsurface.dll', 'VGUI_Surface031', 25, 'void(__thiscall*)(void*, int r, int g, int b, int a)')
    local SetTextPos = vtable_bind('vguimatsurface.dll', 'VGUI_Surface031', 26, 'void(__thiscall*)(void*, int x, int y)')
    local DrawPrintText = vtable_bind('vguimatsurface.dll', 'VGUI_Surface031', 28, 'void(__thiscall*)(void*, const wchar_t *text, int maxlen, int draw_type)')

    local GetFontTall = vtable_bind('vguimatsurface.dll', 'VGUI_Surface031', 74, 'int(__thiscall*)(void*, unsigned int font)')
    local GetTextSize = vtable_bind('vguimatsurface.dll', 'VGUI_Surface031', 79, 'void(__thiscall*)(void*, unsigned int font, const wchar_t *text, int &wide, int &tall)')

    local DrawFilledRectFade = vtable_bind('vguimatsurface.dll', 'VGUI_Surface031', 123, 'void(__thiscall*)(void*, int x0, int y0, int x1, int y1, unsigned int alpha0, unsigned int alpha1, bool bHorizontal)')

    function surface.text_tall(font)
        return GetFontTall(font)
    end

    function surface.measure_text(font, text)
        local buffer = ffi.new 'wchar_t[2048]'

        ilocalize.ansi_to_unicode(text, buffer, 2048)
        GetTextSize(font, buffer, wide, tall)

        return wide[0], tall[0]
    end

    function surface.text(font, x, y, r, g, b, a, text)
        local len = #text

        if len <= 0 then
            return
        end

        local buffer = ffi.new 'wchar_t[2048]'

        ilocalize.ansi_to_unicode(text, buffer, 2048)

        SetTextFont(font)

        SetTextPos(x, y)
        SetTextColor(r, g, b, a)

        DrawPrintText(buffer, len, 0)
    end

    function surface.fade(x, y, w, h, r0, g0, b0, a0, r1, g1, b1, a1, horizontal)
        SetColor(r0, g0, b0, a0)
        DrawFilledRectFade(x, y, x + w, y + h, 255, 0, horizontal)

        SetColor(r1, g1, b1, a1)
        DrawFilledRectFade(x, y, x + w, y + h, 0, 255, horizontal)
    end

    return surface
end

return M
