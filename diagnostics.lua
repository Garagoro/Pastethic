local M = {}

function M.new(deps)
    local client = deps.client
    local prefix = deps.prefix or '[Pasthetic]'
    local diag = {
        ok = 0,
        failed = 0,
        records = {}
    }

    local function log(message)
        if client ~= nil and client.log ~= nil then
            client.log(prefix .. ' ' .. message)
        end
    end

    function diag:check(name, module, required_methods)
        if type(module) ~= 'table' then
            self.failed = self.failed + 1
            self.records[name] = { ok = false, error = 'module is not a table' }
            log(('module %s: failed: module is not a table'):format(name))
            return false
        end

        if required_methods ~= nil then
            for i = 1, #required_methods do
                local method = required_methods[i]

                if type(module[method]) ~= 'function' then
                    self.failed = self.failed + 1
                    self.records[name] = { ok = false, error = 'missing method ' .. method }
                    log(('module %s: failed: missing method %s'):format(name, method))
                    return false
                end
            end
        end

        return true
    end

    function diag:start(name, fn)
        local ok, result = pcall(fn)

        if ok then
            self.ok = self.ok + 1
            self.records[name] = { ok = true, result = result }
            log(('module %s: ok'):format(name))
            return result
        end

        self.failed = self.failed + 1
        self.records[name] = { ok = false, error = tostring(result) }
        log(('module %s: failed: %s'):format(name, tostring(result)))
        return nil
    end

    function diag:health(name, module, ctx)
        if type(module) ~= 'table' or type(module.health) ~= 'function' then
            return true
        end

        local ok, result = pcall(module.health, ctx)

        if ok and result ~= false then
            log(('module %s health: ok'):format(name))
            return true
        end

        log(('module %s health: failed: %s'):format(name, tostring(result)))
        return false
    end

    function diag:summary()
        log(('modules ok: %d, failed: %d'):format(self.ok, self.failed))
    end

    return diag
end

return M
