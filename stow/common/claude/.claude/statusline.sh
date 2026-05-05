#!/usr/bin/env bash
# statusline badges for Claude Code: [CAVEMAN] (when caveman mode active) +
# [MODEL:<display-name>] (always, from the json payload claude pipes on stdin).
#
# wire up via ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "bash $HOME/.claude/statusline.sh" }

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
FLAG="$CONFIG_DIR/.caveman-active"
SAVINGS_FILE="$CONFIG_DIR/.caveman-statusline-suffix"

# read stdin once. claude pipes a json blob; an empty stdin (manual run) is fine.
INPUT=$(cat)

function _caveman_badge() {
    # NOTE: refuse symlinks -- mirrors the upstream caveman script. a local
    # attacker could otherwise point the flag at e.g. ~/.ssh/id_rsa and have us
    # spit its bytes (incl. ansi escapes) to the terminal every keystroke.
    [ -L "$FLAG" ] && return
    [ ! -f "$FLAG" ] && return

    local mode
    mode=$(head -c 64 "$FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]')
    mode=$(printf '%s' "$mode" | tr -cd 'a-z0-9-')

    case "$mode" in
        (off|lite|full|ultra|wenyan-lite|wenyan|wenyan-full|wenyan-ultra|commit|review|compress) ;;
        (*) return ;;
    esac

    if [ -z "$mode" ] || [ "$mode" = "full" ]; then
        printf '\033[38;5;172m[CAVEMAN]\033[0m'
    else
        local suffix
        suffix=$(printf '%s' "$mode" | tr '[:lower:]' '[:upper:]')
        printf '\033[38;5;172m[CAVEMAN:%s]\033[0m' "$suffix"
    fi

    if [ "${CAVEMAN_STATUSLINE_SAVINGS:-1}" != "0" ] \
        && [ -f "$SAVINGS_FILE" ] && [ ! -L "$SAVINGS_FILE" ]; then
        local savings
        savings=$(head -c 64 "$SAVINGS_FILE" 2>/dev/null | tr -d '\000-\037')
        [ -n "$savings" ] && printf ' \033[38;5;172m%s\033[0m' "$savings"
    fi
}

function _model_badge() {
    [ -z "$INPUT" ] && return

    local name=""
    if command -v jq >/dev/null 2>&1; then
        name=$(printf '%s' "$INPUT" | jq -r '.model.display_name // .model.id // empty' 2>/dev/null)
    else
        name=$(printf '%s' "$INPUT" \
            | tr '\n' ' ' \
            | sed -n 's/.*"model"[^{]*{[^}]*"display_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    fi

    # whitelist + length cap. blocks ansi-escape injection if a future claude
    # build ever surfaces user-controlled strings in the model field.
    name=$(printf '%s' "$name" | tr -cd 'A-Za-z0-9 ._-' | head -c 32)
    [ -z "$name" ] && return

    printf '\033[38;5;39m[%s]\033[0m' "$name"
}

function main() {
    local cave model
    cave=$(_caveman_badge)
    model=$(_model_badge)

    [ -n "$cave" ] && printf '%s' "$cave"
    [ -n "$cave" ] && [ -n "$model" ] && printf ' '
    [ -n "$model" ] && printf '%s' "$model"
}

main "$@"
