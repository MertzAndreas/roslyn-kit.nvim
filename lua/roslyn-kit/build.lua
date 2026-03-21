local M = {}

---@param sln_path string
function M.build_diagnostics(sln_path)
	local qf_items = {}
	vim.fn.jobstart({ "dotnet", "build", "--no-restore" }, {
		cwd = vim.fs.dirname(sln_path),
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			for _, line in ipairs(data) do
				local file, row, col, severity, code, msg =
					line:match("^(.+)%((%d+),(%d+)%)%s*:%s*(%w+)%s+(%w+):%s*(.+)$")
				if file and (severity == "warning" or severity == "error") then
					table.insert(qf_items, {
						filename = file,
						lnum = tonumber(row),
						col = tonumber(col),
						type = severity == "error" and "E" or "W",
						text = code .. ": " .. msg,
					})
				end
			end
		end,
		on_exit = function()
			if #qf_items == 0 then
				vim.notify("roslyn-tools: No warnings or errors found", vim.log.levels.INFO)
				return
			end
			vim.schedule(function()
				vim.fn.setqflist(qf_items)
				vim.cmd("copen")
			end)
		end,
	})
	vim.notify("roslyn-tools: Building solution...")
end

return M
