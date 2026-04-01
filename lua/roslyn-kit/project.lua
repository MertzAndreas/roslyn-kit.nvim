local M = {}

---@param bufnr number
---@param client vim.lsp.Client
---@param cb fun(csproj_path: string|nil, err : string|nil)
function M.get_csproj(bufnr, client, cb)
	local params = { _vs_textDocument = { uri = vim.uri_from_bufnr(bufnr) } }
	client:request("textDocument/_vs_getProjectContexts", params, function(err, result)
		if err or not result then
			return cb(nil, "LSP request failed")
		end
		local ctx = result._vs_projectContexts and result._vs_projectContexts[(result._vs_defaultIndex or 0) + 1]
		if not ctx then
			return cb(nil, "No project context returned")
		end
		local csproj = ctx._vs_id:match("|(.+%.csproj)")
		if not csproj then
			return cb(nil, "Could not parse csproj path from context")
		end
		cb(csproj, nil)
	end, bufnr)
end

---@param csproj_path string
---@return string|nil, string|nil errmsg
function M.find_sln(csproj_path)
	local result = vim.fs.find(function(name)
		return name:match("%.slnx?$")
	end, { path = vim.fs.dirname(csproj_path), upward = true, limit = 1 })
	if not result[1] then
		return nil, "No .sln/.slnx found above " .. csproj_path
	end
	return result[1], nil
end

---@return string|nil
function M.find_cs_file()
	local found = vim.fs.find(function(name)
		return name:match("%.cs$")
	end, { path = vim.uv.cwd(), type = "file", limit = 1 })
	return found[1]
end

--- Check if cwd contains a C# project without needing an LSP client
---@return boolean
function M.in_csharp_project()
	local found = vim.fs.find(function(name)
		return name:match("%.slnx?$") or name:match("%.csproj$")
	end, { path = vim.uv.cwd(), upward = true, stop = vim.env.HOME, type = "file", limit = 1 })
	return #found > 0
end

---@param sln_path string
---@return string[]
function M.get_projects_from_sln(sln_path)
	local projects = {}
	local sln_dir = vim.fs.dirname(sln_path)
	local ext = vim.fn.fnamemodify(sln_path, ":e")

	if ext == "slnx" then
		-- .slnx is XML: <Project Path="Foo/Foo.csproj" />
		for _, line in ipairs(vim.fn.readfile(sln_path)) do
			local rel = line:match('Path="([^"]+%.csproj)"')
			if rel then
				table.insert(projects, vim.fs.normalize(sln_dir .. "/" .. rel:gsub("\\", "/")))
			end
		end
	else
		-- classic .sln text format
		for _, line in ipairs(vim.fn.readfile(sln_path)) do
			local rel = line:match(', "([^"]+%.csproj)"')
			if rel then
				table.insert(projects, vim.fs.normalize(sln_dir .. "/" .. rel:gsub("\\", "/")))
			end
		end
	end

	return projects
end

---@param csproj_path string
---@return boolean
function M.is_test_project(csproj_path)
	if vim.fn.filereadable(csproj_path) == 0 then
		return false
	end
	local content = table.concat(vim.fn.readfile(csproj_path), "\n"):lower()
	return content:find("xunit") ~= nil or content:find("nunit") ~= nil or content:find("mstest") ~= nil
end

---@param csproj_path string
---@return "xunit"|"nunit"|"mstest"|"unknown"
function M.detect_test_framework(csproj_path)
	local content = table.concat(vim.fn.readfile(csproj_path), "\n"):lower()
	if content:find("xunit") then
		return "xunit"
	end
	if content:find("nunit") then
		return "nunit"
	end
	if content:find("mstest") then
		return "mstest"
	end
	return "unknown"
end

---@param source_csproj string
---@param test_csproj string
---@param source_file string
---@return string
function M.derive_namespace(source_csproj, test_csproj, source_file)
	local test_name = vim.fn.fnamemodify(test_csproj, ":t:r")
	local source_dir = vim.fs.normalize(vim.fs.dirname(source_csproj))
	-- ensure trailing sep is stripped before slicing
	local norm_file = vim.fs.normalize(source_file)
	local relative = norm_file:sub(#source_dir + 2) -- +2 to skip the separator
	local subdir = vim.fs.dirname(relative)
	if not subdir or subdir == "." then
		return test_name
	end
	return test_name .. "." .. subdir:gsub("/", ".")
end

---@param source_csproj string
---@param test_csproj string
---@param source_file string
---@param class_name string
---@return string
function M.derive_test_file_path(source_csproj, test_csproj, source_file, class_name)
	local source_dir = vim.fs.normalize(vim.fs.dirname(source_csproj))
	local test_dir = vim.fs.normalize(vim.fs.dirname(test_csproj))
	local norm_file = vim.fs.normalize(source_file)
	local relative = norm_file:sub(#source_dir + 2)
	local subdir = vim.fs.dirname(relative)
	if not subdir or subdir == "." then
		return vim.fs.joinpath(test_dir, class_name .. "Tests.cs")
	end
	return vim.fs.joinpath(test_dir, subdir, class_name .. "Tests.cs")
end

return M
