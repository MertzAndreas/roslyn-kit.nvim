local M = {}

---@param package string
---@param project string
---@param version string | nil
---@return boolean
local install_nuget_package = function(package, project, version)
	local cmd = { "dotnet", "add", "package", package, "--project", project }
	if version ~= nil then
		vim.list_extend(cmd, { "--version", version })
	end
	local result = vim.system(cmd):wait()
	return result.code == 0
end

---@param projects string[]
M.install_package = function(projects)
	local snacks = require("snacks")
	snacks.picker({
		live = true,
		supports_live = true,
		preview = "preview",
		format = function(item, _picker)
			local pkg = item.item
			local verified = pkg.verified and " ✓" or ""
			return {
				{ pkg.title, "SnacksPickerLabel" },
				{ " v" .. pkg.version, "Comment" },
				{ verified, "DiagnosticOk" },
			}
		end,
		finder = function(_, ctx)
			local query = ctx.filter.search
			if not query or query == "" then
				return {}
			end
			return function(cb)
				local output = {}
				ctx.async:schedule(function()
					vim.fn.jobstart({
						"curl",
						"-s",
						"https://azuresearch-usnc.nuget.org/query?take=5&q=" .. query,
					}, {
						on_stdout = function(_, data)
							for _, line in ipairs(data) do
								if line ~= "" then
									table.insert(output, line)
								end
							end
						end,
						on_exit = function()
							ctx.async:resume()
						end,
					})
				end)
				ctx.async:suspend()
				local raw = table.concat(output, "")
				local ok, data = pcall(vim.json.decode, raw)
				if ok and data and data.data then
					for _, pkg in ipairs(data.data) do
						local downloads = pkg.totalDownloads
						local dl_str
						if downloads >= 1e9 then
							dl_str = string.format("%.1fb", downloads / 1e9)
						elseif downloads >= 1e6 then
							dl_str = string.format("%.1fm", downloads / 1e6)
						else
							dl_str = string.format("%.1fk", downloads / 1e3)
						end
						local authors = table.concat(pkg.authors or {}, ", ")
						local verified = pkg.verified and "✓ Verified" or "✗ Unverified"
						local lines = {
							"# " .. pkg.title .. " v" .. pkg.version,
							verified,
							"",
							"**Authors:** " .. authors,
							"**Downloads:** " .. dl_str,
							"",
							"## Description",
							pkg.description,
						}
						cb({
							text = pkg.id,
							item = pkg,
							preview = {
								text = table.concat(lines, "\n"),
								ft = "markdown",
							},
						})
					end
				end
			end
		end,
		actions = {
			confirm = function(picker, item)
				picker:close()
				vim.ui.select(projects, {
					prompt = "Select project:",
					format_item = function(p)
						return vim.fn.fnamemodify(p, ":t:r")
					end,
				}, function(project)
					if project then
						local ok = install_nuget_package(item.item.id, project, item.item.version)
						if ok then
							vim.notify("Installed " .. item.text, vim.log.levels.INFO)
						else
							vim.notify("Failed to install " .. item.text, vim.log.levels.ERROR)
						end
					end
				end)
			end,
		},
	})
end

return M
