#!/usr/bin/env bash
# statusline dispatcher. runs every executable in $CONFIG_DIR/statusline.d in
# lex order, pipes the same stdin payload to each, joins non-empty stdout
# results with a single space. each child decides whether to render a badge
# (print to stdout) or stay silent (print nothing / exit non-zero).
#
# wire up via ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "bash $HOME/.claude/statusline.sh" }

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
BADGE_DIR="$CONFIG_DIR/statusline.d"

INPUT=$(cat)

function main() {
    [ -d "$BADGE_DIR" ] || return 0

    local first=1
    local script out
    for script in "$BADGE_DIR"/*; do
        [ -f "$script" ] && [ -x "$script" ] || continue
        out=$(printf '%s' "$INPUT" | "$script" 2>/dev/null)
        [ -z "$out" ] && continue
        if [ "$first" -eq 1 ]; then
            first=0
        else
            printf ' '
        fi
        printf '%s' "$out"
    done
}

main "$@"
