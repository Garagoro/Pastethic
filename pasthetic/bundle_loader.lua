local M = {}

-- Loads external Lua bundles from pasthetic\bundles first, with optional patch hooks.
-- This module only reads/compiles/runs a bundle requested by the entrypoint.

local function log_err(client, msg)
    if client == nil then return end
    client.color_log(250, 50, 75, '[Pasthetic] \0')
    client.color_log(255, 255, 255, msg)
end

function M.load(deps, label, paths)
    deps = deps or {}
    paths = paths or {}

    local client = deps.client
    local readfile = deps.readfile
    local loadstring = deps.loadstring
    local local_path = deps.local_path or function(path) return path end
    local patches = deps.patches

    if loadstring == nil then
        log_err(client, 'cannot load bundled ' .. label .. ': loadstring unavailable')
        return false
    end
    local bundled_path = local_path('pasthetic\\bundles\\' .. label)
    local search_paths = { bundled_path }

    for i = 1, #paths do
        search_paths[#search_paths + 1] = paths[i]
    end
    if readfile == nil then
        log_err(client, 'cannot load bundled ' .. label .. ': readfile unavailable')
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

                log_err(client, 'failed to run bundled ' .. label .. ': ' .. tostring(runtime_error))
                return false
            end

            log_err(client, 'failed to compile bundled ' .. label .. ': ' .. tostring(load_error))
            return false
        elseif i == #search_paths then
            log_err(client, 'failed to find bundled ' .. label .. ' (tried: ' .. bundled_path .. ')')
        end
    end

    return false
end


return M
