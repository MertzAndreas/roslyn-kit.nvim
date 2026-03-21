local project = require("roslyn-kit.project")
local ts = require("roslyn-kit.treesitter")

local M = {}

---@param framework string
---@param test_name string
---@param namespace string
---@param class_name string
---@return string
local function build_test_file(framework, test_name, namespace, class_name)
	local attribute, using
	if framework == "nunit" then
		attribute, using = "[Test]", "using NUnit.Framework;"
	elseif framework == "mstest" then
		attribute, using = "[TestMethod]", "using Microsoft.VisualStudio.TestTools.UnitTesting;"
	else
		attribute, using = "[Fact]", "using Xunit;"
	end
	return string.format(
		[[%s
namespace %s;
public class %sTests
{
    %s
    public void %s()
    {
        // Arrange
        // Act
        // Assert
        throw new NotImplementedException();
    }
}
]],
		using,
		namespace,
		class_name,
		attribute,
		test_name
	)
end

---@param framework string
---@param test_name string
---@return string
local function build_test_stub(framework, test_name)
	local attribute
	if framework == "nunit" then
		attribute = "[Test]"
	elseif framework == "mstest" then
		attribute = "[TestMethod]"
	else
		attribute = "[Fact]"
	end
	return string.format(
		[[
    %s
    public void %s()
    {
        // Arrange
        // Act
        // Assert
        throw new NotImplementedException();
    }
]],
		attribute,
		test_name
	)
end

--- Finds the closing brace of the outermost class using treesitter,
--- falling back to the naive last-} scan only if parsing fails.
---@param test_file_path string
---@param stub string
---@return boolean
local function append_test_stub(test_file_path, stub)
	local lines = vim.fn.readfile(test_file_path)

	-- Try treesitter first for accuracy
	local bufnr = vim.fn.bufadd(test_file_path)
	vim.fn.bufload(bufnr)
	local insert_at = nil

	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "c_sharp")
	if ok and parser then
		local root = parser:parse()[1]:root()
		-- find the last class_declaration node's closing brace line
		for node in root:iter_children() do
			if node:type() == "class_declaration" then
				local _, _, end_row, _ = node:range()
				insert_at = end_row + 1 -- 0-indexed end_row → 1-indexed line number
			end
		end
	end

	-- fallback: last line that is a bare closing brace
	if not insert_at then
		for i = #lines, 1, -1 do
			if lines[i]:match("^}%s*$") then
				insert_at = i
				break
			end
		end
	end

	if not insert_at then
		vim.notify("roslyn-tools: Could not find closing brace in test file", vim.log.levels.WARN)
		return false
	end

	local stub_lines = vim.split(stub, "\n")
	for j = #stub_lines, 1, -1 do
		table.insert(lines, insert_at, stub_lines[j])
	end
	vim.fn.writefile(lines, test_file_path)
	return true
end

---@param file_path string
---@param test_name string
local function open_at_assert(file_path, test_name)
	vim.cmd("edit " .. vim.fn.fnameescape(file_path))
	local in_target = false
	for i, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
		if line:find(test_name, 1, true) then
			in_target = true
		end
		if in_target and line:find("// Assert", 1, true) then
			vim.api.nvim_win_set_cursor(0, { i, 8 })
			break
		end
	end
end

---@param s RoslynState
---@param buf number
function M.generate(s, buf)
	local method_name, class_name, restricted = ts.get_method_context()
	if not method_name then
		vim.notify("roslyn-tools: No method found at cursor", vim.log.levels.WARN)
		return
	end
	if restricted then
		vim.notify("roslyn-tools: Method is " .. restricted .. " — not directly testable", vim.log.levels.WARN)
		return
	end
	if #s.test_projects == 0 then
		vim.notify("roslyn-tools: No test projects found in solution", vim.log.levels.WARN)
		return
	end

	local source_project_name = vim.fn.fnamemodify(s.csproj, ":t:r"):lower()
	local sorted = vim.deepcopy(s.test_projects)
	table.sort(sorted, function(a)
		return vim.fs.basename(a):lower():find(source_project_name, 1, true) ~= nil
	end)

	local function do_generate(test_csproj)
		local framework = project.detect_test_framework(test_csproj)
		local source_file = vim.api.nvim_buf_get_name(buf)
		local test_file = project.derive_test_file_path(s.csproj, test_csproj, source_file, class_name)
		local namespace = project.derive_namespace(s.csproj, test_csproj, source_file)

		if vim.fn.filereadable(test_file) == 1 then
			local stub = build_test_stub(framework, method_name)
			if append_test_stub(test_file, stub) then
				open_at_assert(test_file, method_name)
			end
		else
			vim.fn.mkdir(vim.fs.dirname(test_file), "p")
			local content = build_test_file(framework, method_name, namespace, class_name)
			vim.fn.writefile(vim.split(content, "\n"), test_file)
			open_at_assert(test_file, method_name)
		end
	end

	if #sorted == 1 then
		do_generate(sorted[1])
	else
		vim.ui.select(sorted, {
			prompt = "Select test project:",
			format_item = function(p)
				return vim.fn.fnamemodify(p, ":t:r")
			end,
		}, function(choice)
			if choice then
				do_generate(choice)
			end
		end)
	end
end

---@param s RoslynState
function M.run(s)
	if #s.test_projects == 0 then
		vim.notify("roslyn-tools: No test projects found", vim.log.levels.WARN)
		return
	end
	vim.ui.select(s.test_projects, {
		prompt = "Run tests in:",
		format_item = function(p)
			return vim.fn.fnamemodify(p, ":t:r")
		end,
	}, function(choice)
		if not choice then
			return
		end
		local output = {}
		vim.fn.jobstart({ "dotnet", "test", choice, "--no-build", "--logger", "console;verbosity=normal" }, {
			stdout_buffered = true,
			stderr_buffered = true,
			on_stdout = function(_, data)
				vim.list_extend(output, data)
			end,
			on_exit = function(_, code)
				vim.schedule(function()
					local out_buf = vim.api.nvim_create_buf(false, true)
					vim.api.nvim_buf_set_lines(out_buf, 0, -1, false, output)
					vim.bo[out_buf].filetype = "text"
					vim.cmd("botright split")
					vim.api.nvim_win_set_buf(0, out_buf)
					if code == 0 then
						vim.notify("roslyn-tools: Tests passed", vim.log.levels.INFO)
					else
						vim.notify("roslyn-tools: Tests failed", vim.log.levels.WARN)
					end
				end)
			end,
		})
		vim.notify("roslyn-tools: Running tests in " .. vim.fn.fnamemodify(choice, ":t:r") .. "...")
	end)
end

return M
