#!/bin/bash
#
# launch a program using dmenu and fzf

# --tac

# call dmanu_path and filter some entries out
# for example we don't really want '[' in the launcher since
# it is not a gui app
SKIP=(
    '\['
    'cacafire'
    'firefox.geckodriver'
)
DMENU_PATH=$(dmenu_path | grep -v -E "$(printf "%s|" "${SKIP[@]}" | sed 's/|$//')")
RESP=$(echo "$DMENU_PATH" | fzf +s --exact --no-multi)

if [ -n "$RESP" ]; then
    if command -v "$RESP" &> /dev/null; then
        swaymsg exec -- "$RESP"
    else
        echo "Command not found: $RESP"
    fi
else
    echo "No command selected."
fi
