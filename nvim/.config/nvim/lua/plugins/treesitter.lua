return {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
	local configs = require("nvim-treesitter.configs")
	configs.setup({
	    higlight = { enable = true },
	    indent = { enable = true },
	    autotag = { enable = true },
	    ensure_installed = {
		"c",
		"lua",
		"markdown",
		"markdown_inline",
		"python",
		"go",
	    },
	})
    end
}


