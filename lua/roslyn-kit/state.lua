---@class RoslynState
---@field csproj string
---@field sln string
---@field all_projects string[]
---@field test_projects string[]

---@class RoslynStateStore
---@field private _store table<integer, RoslynState>|nil
local M = {}

---@param client_id integer
---@return RoslynState|nil
function M.get(client_id)
	return M._store and M._store[client_id] or nil
end

---@param client_id integer
---@param s RoslynState
---@return nil
function M.set(client_id, s)
	M._store = M._store or {}
	M._store[client_id] = s
end

---@param client_id integer
---@return nil
function M.clear(client_id)
	if M._store then
		M._store[client_id] = nil
	end
end

return M
