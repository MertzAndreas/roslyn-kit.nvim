---@class RoslynState
---@field csproj string
---@field sln string
---@field all_projects string[]
---@field test_projects string[]

---@type table<integer, RoslynState>
local M = {}

function M.get(client_id)
	return M._store and M._store[client_id]
end

function M.set(client_id, s)
	M._store = M._store or {}
	M._store[client_id] = s
end

function M.clear(client_id)
	if M._store then
		M._store[client_id] = nil
	end
end

return M
