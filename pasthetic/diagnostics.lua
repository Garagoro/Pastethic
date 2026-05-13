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
        if client ~= nil and client.color_log ~= nil then
            client.color_log(180, 100, 255, prefix .. ' \0')
            client.color_log(255, 255, 255, message)
        end
    end

    function diag:check(name, module, required_methods)
        if type(module) ~= 'table' then
            self.failed = self.failed + 1
            self.records[name] = { ok = false, error = 'module is not a table' }
            return false
        end

        if required_methods ~= nil then
            for i = 1, #required_methods do
                local method = required_methods[i]

                if type(module[method]) ~= 'function' then
                    self.failed = self.failed + 1
                    self.records[name] = { ok = false, error = 'missing method ' .. method }
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
            return result
        end

        self.failed = self.failed + 1
        self.records[name] = { ok = false, error = tostring(result) }
        return nil
    end

    function diag:health(name, module, ctx)
        if type(module) ~= 'table' or type(module.health) ~= 'function' then
            return true
        end

        local ok, result = pcall(module.health, ctx)

        if ok and result ~= false then
            return true
        end

        return false
    end

    function diag:summary()
        local total = self.ok + self.failed
        log(('loaded %d/%d. errors: %d'):format(self.ok, total, self.failed))
        if self.failed > 0 then
            for name, record in pairs(self.records) do
                if not record.ok then
                    log(('failed: %s: %s'):format(name, record.error or '?'))
                end
            end
        end
    end

    return diag
end

return M
