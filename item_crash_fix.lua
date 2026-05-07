local M = {}

function M.start(deps)
    deps = deps or {}

    local ffi = deps.ffi or ffi
    local client = deps.client or client
    local state = {}

    local CS_UM_SendPlayerItemFound = 63

    local DispatchUserMessage_t = ffi.typeof [[
        bool(__thiscall*)(void*, int msg_type, int nFlags, int size, const void* msg)
    ]]

    local VClient018 = client.create_interface("client.dll", "VClient018")

    local pointer = ffi.cast("uintptr_t**", VClient018)
    local vtable = ffi.cast("uintptr_t*", pointer[0])

    local vtsize = 0
    while vtable[vtsize] ~= 0x0 do
       vtsize = vtsize + 1
    end

    local hooked_vtable = ffi.new("uintptr_t[?]", vtsize)
    for i = 0, vtsize - 1 do
        hooked_vtable[i] = vtable[i]
    end
    pointer[0] = hooked_vtable

    local oDispatch = ffi.cast(DispatchUserMessage_t, vtable[38])

    local function hkDispatch(thisptr, msg_type, nFlags, sz, msg)
        if msg_type == CS_UM_SendPlayerItemFound then
            return false
        end
        return oDispatch(thisptr, msg_type, nFlags, sz, msg)
    end

    client.set_event_callback("shutdown", function()
        hooked_vtable[38] = vtable[38]
        pointer[0] = vtable
    end)

    hooked_vtable[38] = ffi.cast("uintptr_t", ffi.cast(DispatchUserMessage_t, hkDispatch))

    state.pointer = pointer
    state.vtable = vtable
    state.hooked_vtable = hooked_vtable
    state.dispatch = oDispatch
    state.hook = hkDispatch

    return state
end

return M
