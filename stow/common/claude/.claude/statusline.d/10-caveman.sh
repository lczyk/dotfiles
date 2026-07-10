#!/usr/bin/env bash
# caveman badge. reads mode flag file, renders short badge.
# [C] full, [c] lite, [C!] ultra, [Cc] commit, [Cp] compress, [x] off/missing.
#
# detection: plugin (caveman@caveman in enabledPlugins) OR vendored
# (hooks referencing caveman-activate / caveman-mode-tracker).
#
# state vs badge:
#   configured      + flag present  -> normal badge per mode
#   configured      + flag missing  -> [x] (hooks should've written it)
#   plugin disabled explicitly      -> [-] (deliberate)
#   not configured at all           -> [x]
#   flag says off                   -> [x] (mode off, but hooks are there)

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATE_DIR="${AGENT_STATE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/agent-state}"
FLAG="${STATE_DIR}/caveman-active"
SETTINGS="${CONFIG_DIR}/settings.json"
# shellcheck source-path=SCRIPTDIR source=../statusline-colour.sh
. "$(dirname "${BASH_SOURCE[0]}")/../statusline-colour.sh"


badge() { sl_paint '5;172' "[$1]"; }

_caveman_configured() {
    [ -f "$SETTINGS" ] || return 1
    # plugin path
    grep -q '"caveman@caveman"[[:space:]]*:[[:space:]]*true' "$SETTINGS" 2>/dev/null && return 0
    # vendored path: hooks reference caveman activate/tracker
    grep -q 'caveman-activate' "$SETTINGS" 2>/dev/null && return 0
    return 1
}

if [ -f "$SETTINGS" ]; then
    if grep -q '"caveman@caveman"[[:space:]]*:[[:space:]]*false' "$SETTINGS" 2>/dev/null; then
        badge "-"
        exit 0
    fi
fi

if ! _caveman_configured; then
    badge "x"
    exit 0
fi

# plugin is enabled. flag should exist.
[ -f "$FLAG" ] || { badge "x"; exit 0; }
# refuse symlinks -- security hardening
[ -L "$FLAG" ] && { badge "x"; exit 0; }

mode=$(head -c 64 "$FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]')
mode=$(printf '%s' "$mode" | tr -cd 'a-z0-9-')

case "$mode" in
    ""|full)           badge "C"    ;;
    lite)              badge "c"    ;;
    ultra)             badge "C!"   ;;
    commit)            badge "Cc"   ;;
    compress)          badge "Cp"   ;;
    off)               badge "x"    ;;
    *)                 badge "C"    ;;  # unknown mode, assume full
esac
