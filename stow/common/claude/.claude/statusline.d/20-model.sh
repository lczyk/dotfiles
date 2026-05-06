#!/usr/bin/env bash
# model-name badge. prints [<model-display-name>] from the json payload claude
# code pipes on stdin. silent when stdin is empty or the field is missing.
#
# add aliases below to render shorter labels for known display names. anything
# not in the map falls back to the raw display name, capped at 20 chars.

# NOTE: case-statement instead of `declare -A` -- macos ships bash 3.2 which
# doesn't have associative arrays, and the script needs to work under it.
alias_for() {
    case "$1" in
        "Opus 4.7")                echo "O47" ;;
        "Opus 4.7 (1M context)")   echo "O47-1M" ;;
        "Opus 4.6")                echo "O46" ;;
        "Sonnet 4.6")              echo "S46" ;;
        "Sonnet 4.6 (1M context)") echo "S46-1M" ;;
        "Haiku 4.5")               echo "H45" ;;
        "deepseek-v4-pro1m")       echo "DS4-1M" ;;
        *)                         echo "$1" ;;
    esac
}

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

if command -v jq >/dev/null 2>&1; then
    name=$(printf '%s' "$INPUT" | jq -r '.model.display_name // .model.id // empty' 2>/dev/null)
else
    name=$(printf '%s' "$INPUT" \
        | tr '\n' ' ' \
        | sed -n 's/.*"model"[^{]*{[^}]*"display_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi

[ -z "$name" ] && exit 0

label=$(alias_for "$name")

# whitelist + length cap. blocks ansi-escape injection if a future claude build
# ever surfaces user-controlled strings in the model field.
label=$(printf '%s' "$label" | tr -cd 'A-Za-z0-9 ._-' | head -c 20)
[ -z "$label" ] && exit 0

printf '\033[38;5;39m[%s]\033[0m' "$label"
