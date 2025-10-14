#!/bin/bash
#spellchecker: ignore dmenu cacafire geckodriver swaymsg
#spellchecker: ignore Marcin Konowalczyk lczyk
#
# Launch a program using dmenu and fzf
#
# Written by Marcin Konowalczyk @lczyk 2025
# License: MIT-0

function main() {
    local handler_path="${BASH_SOURCE[0]%/*}/launcher_handler.py"
    local response
    if [ ! -f "$handler_path" ]; then
        # no handler, use default
        # Add programs to skip here
        SKIP=(
            '\['
            'cacafire'
            'firefox.geckodriver'
            'aa-decode'
        )
        local choices
        choices=$(dmenu_path | grep -v -E "$(printf "%s|" "${SKIP[@]}" | sed 's/|$//')")
        response=$(echo "$choices" | fzf +s --exact --no-multi)
    else
        # use handler
        local choices
        #shellcheck disable=SC2046
        choices=$("$handler_path" list --counts $(dmenu_path))
        response=$(echo "$choices" | fzf --exact --no-multi | sed 's/ (.*)//')
        "$handler_path" record "$response"
    fi
    if [ -n "$response" ]; then
        if command -v "$response" &> /dev/null; then
            swaymsg exec -- "$response"
        else
            echo "Command not found: $response"
        fi
    else
        echo "No command selected."
    fi
}

main "$@"