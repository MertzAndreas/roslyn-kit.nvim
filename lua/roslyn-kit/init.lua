local state_store = require("roslyn-kit.state")
local project = require("roslyn-kit.project")
local build = require("roslyn-kit.build")
local test = require("roslyn-kit.test")
local nuget = require("roslyn-kit.nuget")

local M = {}

---@param client_id integer
---@param bufnr number
---@param client vim.lsp.Client
---@param cb fun(s: RoslynState)
local function get_or_init_state(client_id, bufnr, client, cb)
	local cached = state_store.get(client_id)
	if cached then
		return cb(cached)
	end

	project.get_csproj(bufnr, client, function(csproj, err)
		if not csproj then
			vim.notify("roslyn-tools: " .. (err or "Could not resolve project"), vim.log.levels.WARN)
			return
		end

		local sln, sln_err = project.find_sln(csproj)
		if not sln then
			vim.notify("roslyn-tools: " .. (sln_err or "Could not find solution"), vim.log.levels.WARN)
			return
		end

		local all_projects = project.get_projects_from_sln(sln)
		local test_projects = vim.tbl_filter(project.is_test_project, all_projects)

		local s = {
			csproj = csproj,
			sln = sln,
			all_projects = all_projects,
			test_projects = test_projects,
		}
		state_store.set(client_id, s)
		cb(s)
	end)
end

local function setup_buffer_autocmds(client, buf)
	local augroup = vim.api.nvim_create_augroup("RoslynTools_buf_" .. buf, { clear = true })

	-- Refresh diagnostics on enter
	vim.api.nvim_create_autocmd("BufEnter", {
		group = augroup,
		buffer = buf,
		callback = function()
			vim.diagnostic.reset(nil, buf)
			vim.lsp.buf_request(
				buf,
				"textDocument/diagnostic",
				{ textDocument = vim.lsp.util.make_text_document_params() },
				nil
			)
		end,
	})

	-- Refresh all CS buffers on write
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = augroup,
		buffer = buf,
		callback = function()
			for _, b in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == "cs" then
					vim.lsp.buf_request(
						b,
						"textDocument/diagnostic",
						{ textDocument = { uri = vim.uri_from_bufnr(b) } },
						nil
					)
				end
			end
		end,
	})

	-- -- Codelens refresh
	-- vim.api.nvim_create_autocmd({ "BufEnter", "InsertLeave" }, {
	-- 	group = augroup,
	-- 	buffer = buf,
	-- 	callback = function()
	-- 		vim.lsp.codelens.refresh()
	-- 	end,
	-- })
	--
	-- XML doc comment expansion on ///
	vim.api.nvim_create_autocmd("InsertCharPre", {
		group = augroup,
		buffer = buf,
		desc = "Roslyn: expand /// into XML doc comment",
		callback = function()
			if vim.v.char ~= "/" then
				return
			end
			local row, col = unpack(vim.api.nvim_win_get_cursor(0))
			local params = {
				_vs_textDocument = { uri = vim.uri_from_bufnr(buf) },
				_vs_position = { line = row - 1, character = col + 1 },
				_vs_ch = "/",
				_vs_options = {
					tabSize = vim.bo[buf].tabstop,
					insertSpaces = vim.bo[buf].expandtab,
				},
			}
			vim.defer_fn(function()
				if not vim.api.nvim_buf_is_valid(buf) then
					return
				end
				client:request("textDocument/_vs_onAutoInsert", params, function(err, result)
					if err or not result then
						return
					end
					local edit = result._vs_textEdit
					if not edit then
						return
					end
					local r = edit.range
					local newText = edit.newText:gsub("\r\n", "\n"):gsub("\r", "\n")
					vim.api.nvim_buf_set_text(
						buf,
						r.start.line,
						r.start.character,
						r["end"].line,
						r["end"].character,
						{ "" }
					)
					vim.api.nvim_win_set_cursor(0, { r.start.line + 1, r.start.character })
					vim.snippet.expand(newText)
				end, buf)
			end, 50)
		end,
	})
end

local function setup_keymaps(client, buf)
	---@param fn fun(s: RoslynState)
	---@return function
	local function with_state(fn)
		return function()
			get_or_init_state(client.id, buf, client, fn)
		end
	end

	vim.keymap.set(
		"n",
		"<leader>tw",
		with_state(function(s)
			build.build_diagnostics(s.sln)
		end),
		{ buffer = buf, desc = "roslyn-tools: Solution warnings" }
	)

	vim.keymap.set(
		"n",
		"<leader>tn",
		with_state(function(s)
			nuget.install_package(s.all_projects)
		end),
		{ buffer = buf, desc = "roslyn-tools: Search nuget packages" }
	)

	vim.keymap.set(
		"n",
		"<leader>tg",
		with_state(function(s)
			test.generate(s, buf)
		end),
		{ buffer = buf, desc = "roslyn-tools: Generate test" }
	)

	vim.keymap.set(
		"n",
		"<leader>tr",
		with_state(function(s)
			test.run(s)
		end),
		{ buffer = buf, desc = "roslyn-tools: Run tests" }
	)
end

function M.setup()
	vim.api.nvim_create_autocmd("VimEnter", {
		once = true,
		desc = "Initialise roslyn early if in cs project",
		callback = function()
			vim.schedule(function()
				if not project.in_csharp_project() then
					return
				end
				local cs_file = project.find_cs_file()
				if not cs_file then
					return
				end

				local buf = vim.fn.bufadd(cs_file)
				vim.bo[buf].buflisted = false
				vim.bo[buf].swapfile = false
				vim.fn.bufload(buf)
				vim.bo[buf].filetype = "cs"
			end)
		end,
	})

	vim.api.nvim_create_autocmd("LspDetach", {
		desc = "Clear state",
		callback = function(args)
			state_store.clear(args.data.client_id)
		end,
	})

	vim.api.nvim_create_autocmd("LspAttach", {
		callback = function(args)
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if not client or client.name ~= "roslyn" then
				return
			end
			local buf = args.buf
			setup_buffer_autocmds(client, buf)
			setup_keymaps(client, buf)
		end,
	})
end

return M
