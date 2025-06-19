return {
    'gelguy/wilder.nvim',
    config = function()
        local wilder = require("wilder")
        wilder.setup({
            modes = { ':', '/', '?' },
            next_key = '<Down>',
            previous_key = '<Up>',
            accept_key = '<Right>',
            reject_key = '<Left>',
        })
        wilder.set_option('renderer', wilder.renderer_mux({
            [':'] = wilder.popupmenu_renderer({
                highlighter = wilder.basic_highlighter(),
            }),
            ['/'] = wilder.wildmenu_renderer({
                highlighter = wilder.basic_highlighter(),
            }),
        }))
        wilder.set_option('renderer', wilder.popupmenu_renderer({
            pumblend = 20,
        }))
        --         wilder.set_option('renderer', wilder.wildmenu_renderer({
        --             highlighter = wilder.basic_highlighter(),
        --             separator = ' · ',
        --             left = { ' ', wilder.wildmenu_spinner(), ' ' },
        --             right = { ' ', wilder.wildmenu_index() },
        --         }))
    end,
}
