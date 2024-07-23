local M={}

function M._begin()
	print("Project minesweeper begin")
	vim.opt.expandtab = false
	dove.toggle.register_quick_command("Build", function ()
		vim.cmd("!odin build .")
	end)
	print("- use tab")
end

function M._end()
	print("Project minesweeper end")
end

return M

