#!/bin/bash
#spellchecker: ignore dmenu cacafire geckodriver swaymsg
#spellchecker: ignore Marcin Konowalczyk lczyk
#
# Launch a program using dmenu and fzf
#
# Written by Marcin Konowalczyk @lczyk 2025
# License: MIT-0

# Pick one line from stdin. Prefer ff (gitgum fuzzyfinder), fall back to fzf.
# Any args are fzf-only extras (e.g. +s) and are ignored when ff is used.
# NOTE: sway's env may lack ~/.local/bin (added by ~/.profile, which fish
# doesn't source), so check there explicitly before falling back to fzf.
function pick() {
    local ff_bin
    if command -v ff &> /dev/null; then
        ff_bin=ff
    elif [ -x "$HOME/.local/bin/ff" ]; then
        ff_bin="$HOME/.local/bin/ff"
    fi
    if [ -n "$ff_bin" ]; then
        "$ff_bin" --fast
    else
        fzf --exact --no-multi "$@"
    fi
}

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
        response=$(echo "$choices" | pick +s)
    else
        # use handler
        local choices
        #shellcheck disable=SC2046
        choices=$("$handler_path" list --counts $(dmenu_path))
        response=$(echo "$choices" | pick | sed 's/ (.*)//')
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