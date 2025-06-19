local function enable_transparency()
    vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
end

return {
--    {
--	"folke/tokyonight.nvim",
--	config = function()
--	    vim.cmd.colorscheme "tokyonight"
--	end
--   }
     {
	 "diegoulloao/neofusion.nvim",
	 config = function()
	     vim.cmd.colorscheme "neofusion"
	     vim.o.background = "dark" 
	     enable_transparency()
	 end
     },
     {
	 "nvim-lualine/lualine.nvim",
	 dependencies = {
	     "nvim-tree/nvim-web-devicons"
	 },
	 opts = {
	     theme = "neofusion",
	 },
     },
}
