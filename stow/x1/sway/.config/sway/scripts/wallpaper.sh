#!/bin/bash
# A script to manage wallpaper selection using wallpaper_handler.py

function main() {
    local handler_path="${BASH_SOURCE[0]%/*}/wallpaper_handler.py"
    if [ ! -f "$handler_path" ]; then
        echo "Error: wallpaper_handler.py not found at $handler_path" >&2
        exit 1
    fi

    # Generate the list of wallpapers
    local wallpapers
    wallpapers=$(find ~/.local/share/backgrounds/ -type f -not -name '_*')

    # Pass the list to the handler and get the selected wallpaper
    local selected_wallpaper
    selected_wallpaper=$("$handler_path" select $wallpapers)

    if [ -n "$selected_wallpaper" ]; then
        echo "$selected_wallpaper"
    else
        echo "Error: No wallpaper selected." >&2
        exit 1
    fi
}

main "$@"
