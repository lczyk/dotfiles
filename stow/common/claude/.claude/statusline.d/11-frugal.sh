#!/usr/bin/env bash
# frugal badge. silent when off / not configured.
# [f] lite, [F] full.

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
FLAG="${CONFIG_DIR}/.frugal-active"

badge() { printf '\033[38;5;111m[%s]\033[0m' "$1"; }

[ -f "$FLAG" ] || exit 0
[ -L "$FLAG" ] && exit 0

mode=$(head -c 32 "$FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]')
mode=$(printf '%s' "$mode" | tr -cd 'a-z0-9-')

case "$mode" in
    lite) badge "f" ;;
    full) badge "F" ;;
    *)    exit 0   ;;
esac
