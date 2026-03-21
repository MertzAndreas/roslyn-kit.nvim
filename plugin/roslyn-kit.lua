-- Guard against double-loading
if vim.g.loaded_roslyn_tools then
	return
end
vim.g.loaded_roslyn_tools = true

require("roslyn-kit").setup()
