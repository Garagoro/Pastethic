local M = {}

-- Loads external Lua bundles from pasthetic\bundles first, with optional patch hooks.
-- This module only reads/compiles/runs a bundle requested by the entrypoint.

function M.load(deps, label, paths)
    deps = deps or {}
    paths = paths or {}

    local client = deps.client
    local readfile = deps.readfile
    local loadstring = deps.loadstring
    local patches = deps.patches

    if loadstring == nil then
        if client ~= nil and client.log ~= nil then
            client.log(('[%s] cannot load bundled %s: loadstring unavailable'):format('Pasthetic', label))
        end

        return false
    end
    local bundled_path = 'pasthetic\\bundles\\' .. label
    local search_paths = { bundled_path }

    for i = 1, #paths do
        search_paths[#search_paths + 1] = paths[i]
    end
    if readfile == nil then
        if client ~= nil and client.log ~= nil then
            client.log(('[%s] failed to find embedded %s and readfile is unavailable'):format('Pasthetic', label))
        end

        return false
    end

    for i = 1, #search_paths do
        local ok_read, source = pcall(readfile, search_paths[i])

        if ok_read and type(source) == 'string' and #source > 0 then
            if label == 'colorskinscsgo.lua' and patches ~= nil and patches.patch_colorskins ~= nil then
                source = patches.patch_colorskins(source)
            end

            local chunk, load_error = loadstring(source, '@' .. search_paths[i])

            if chunk ~= nil then
                local ok, runtime_error = pcall(chunk)

                if ok then
                    return true
                end

                if client ~= nil and client.log ~= nil then
                    client.log(('[%s] failed to run bundled %s: %s'):format('Pasthetic', label, tostring(runtime_error)))
                end

                return false
            end

            if client ~= nil and client.log ~= nil then
                client.log(('[%s] failed to compile bundled %s: %s'):format('Pasthetic', label, tostring(load_error)))
            end

            return false
        elseif i == #search_paths and client ~= nil and client.log ~= nil then
            client.log(('[%s] failed to find bundled %s'):format('Pasthetic', label))
        end
    end

    return false
end


return M
