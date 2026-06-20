#!/usr/bin/env bash
# ponytail badge. reads mode flag file, renders short badge.
# [P] full, [p] lite, [P!] ultra, [Pr] review, [x] off/missing.
#
# detection: plugin (ponytail@ponytail in enabledPlugins) OR vendored
# (hooks referencing ponytail-activate / ponytail-mode-tracker).
#
# state vs badge:
#   configured      + flag present  -> normal badge per mode
#   configured      + flag missing  -> [x] (hooks should've written it)
#   plugin disabled explicitly      -> [-] (deliberate)
#   not configured at all           -> [x]
#   flag says off                   -> [x] (mode off, but hooks are there)

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
FLAG="${CONFIG_DIR}/.ponytail-active"
SETTINGS="${CONFIG_DIR}/settings.json"

badge() { printf '\033[38;5;108m[%s]\033[0m' "$1"; }

_ponytail_configured() {
    [ -f "$SETTINGS" ] || return 1
    # plugin path
    grep -q '"ponytail@ponytail"[[:space:]]*:[[:space:]]*true' "$SETTINGS" 2>/dev/null && return 0
    # vendored path: hooks reference ponytail activate/tracker
    grep -q 'ponytail-activate' "$SETTINGS" 2>/dev/null && return 0
    return 1
}

if [ -f "$SETTINGS" ]; then
    if grep -q '"ponytail@ponytail"[[:space:]]*:[[:space:]]*false' "$SETTINGS" 2>/dev/null; then
        badge "-"
        exit 0
    fi
fi

if ! _ponytail_configured; then
    badge "x"
    exit 0
fi

# configured. flag should exist.
[ -f "$FLAG" ] || { badge "x"; exit 0; }
# refuse symlinks -- security hardening
[ -L "$FLAG" ] && { badge "x"; exit 0; }

mode=$(head -c 64 "$FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]')
mode=$(printf '%s' "$mode" | tr -cd 'a-z0-9-')

case "$mode" in
    ""|full)  badge "P"  ;;
    lite)     badge "p"  ;;
    ultra)    badge "P!" ;;
    review)   badge "Pr" ;;
    off)      badge "x"  ;;
    *)        badge "P"  ;;  # unknown mode, assume full
esac
