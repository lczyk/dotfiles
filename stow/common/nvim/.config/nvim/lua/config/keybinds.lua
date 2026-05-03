vim.g.mapleader = " "
vim.keymap.set("n", "<leader>cd", vim.cmd.Ex)

-- wildmenu arrow keys
-- see:
-- https://vi.stackexchange.com/questions/22627/switching-arrow-key-mappings-for-wildmenu-tab-completion
-- https://stackoverflow.com/questions/76352066/nvim-autocomplete-menu-arrow-selection-invert-left-right-up-down-functions

vim.cmd([[
  set wildcharm=<C-Z>
  cnoremap <expr> <up> wildmenumode() ? "\<left>" : "\<up>"
  cnoremap <expr> <down> wildmenumode() ? "\<right>" : "\<down>"
  cnoremap <expr> <left> wildmenumode() ? "\<up>" : "\<left>"
  cnoremap <expr> <right> wildmenumode() ? " \<bs>\<C-Z>" : "\<right>"
]])

-- sometimes i accidentally press shift+; for collon and then keep the shift pressed
-- and type q to quit. this ends up erroring with 'no such command', so why not make it opne?
-- vim.api.nvim_create_user_command('Q', 'q', {})


-- vim.api.nvim_create_user_command('q', 'q!', {})
vim.cmd([[
cnoreabbrev q q!
cnoreabbrev Q q!
cnoreabbrev W w
cnoreabbrev Wq wq!
cnoreabbrev WQ wq!
cnoreabbrev wq wq!
]])
-- vim.api.nvim_create_user_command('Q', 'q!', {})


-- vim.api.nvim_set_keymap('i', '<C-/>', 'copilot#Accept("<CR>")', {expr=true, silent=true})
