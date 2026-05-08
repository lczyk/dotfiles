#!/usr/bin/env bash
# caveman badge. reads mode flag file, renders short badge.
# [C] full, [c] lite, [C!] ultra, [W]/[w]/[W!] wenyan, [x] off/missing.
#
# plugin state vs badge:
#   plugin enabled  + flag present  ->normal badge per mode
#   plugin enabled  + flag missing  ->[x] (something wrong, plugin should've written it)
#   plugin disabled explicitly      ->[-] (deliberate)
#   plugin missing from settings    ->[x] (not installed/configured)
#   flag says off                   ->[x] (mode off, but plugin is there)

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
FLAG="${CONFIG_DIR}/.caveman-active"
SETTINGS="${CONFIG_DIR}/settings.json"

badge() { printf '\033[38;5;172m[%s]\033[0m' "$1"; }

if [ -f "$SETTINGS" ]; then
    if grep -q '"caveman@caveman"[[:space:]]*:[[:space:]]*false' "$SETTINGS" 2>/dev/null; then
        badge "-"  # deliberately disabled
        exit 0
    fi
    if ! grep -q '"caveman@caveman"' "$SETTINGS" 2>/dev/null; then
        badge "x"  # plugin not installed/configured
        exit 0
    fi
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
    wenyan-lite)       badge "w"    ;;
    wenyan|wenyan-full) badge "W"   ;;
    wenyan-ultra)      badge "W!"   ;;
    commit)            badge "Cc"   ;;
    review)            badge "Cr"   ;;
    compress)          badge "Cp"   ;;
    off)               badge "x"    ;;
    *)                 badge "C"    ;;  # unknown mode, assume full
esac
