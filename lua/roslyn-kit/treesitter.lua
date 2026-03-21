local M = {}

---@return string|nil method_name
---@return string|nil class_name
---@return string|nil restricted_modifier
function M.get_method_context()
	local ok = pcall(vim.treesitter.get_parser, 0, "c_sharp")
	if not ok then
		vim.notify(
			"roslyn-tools: requires nvim-treesitter with c_sharp parser. Run :TSInstall c_sharp",
			vim.log.levels.ERROR
		)
		return nil, nil, nil
	end

	local parser = vim.treesitter.get_parser(0, "c_sharp")
	if not parser then
		return nil, nil, nil
	end

	local root = parser:parse()[1]:root()
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	local node = root:named_descendant_for_range(row - 1, col, row - 1, col)

	local method_name, class_name, restricted_modifier = nil, nil, nil
	local restricted = { private = true, protected = true }

	local current = node
	while current do
		if current:type() == "method_declaration" then
			for child in current:iter_children() do
				if child:type() == "modifier" then
					local mod = vim.treesitter.get_node_text(child, 0)
					if restricted[mod] then
						restricted_modifier = mod
					end
				end
				if child:type() == "identifier" and not method_name then
					method_name = vim.treesitter.get_node_text(child, 0)
				end
			end
			break
		end
		current = current:parent()
	end

	if not method_name then
		return nil, nil, nil
	end

	current = node
	while current do
		if current:type() == "class_declaration" then
			for child in current:iter_children() do
				if child:type() == "identifier" then
					class_name = vim.treesitter.get_node_text(child, 0)
					break
				end
			end
			break
		end
		current = current:parent()
	end

	return method_name, class_name, restricted_modifier
end

return M
