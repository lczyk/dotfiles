#!/usr/bin/env bash
# caveman badge. reads mode flag file, renders short badge.
# [c] full, [cl] lite, [cu] ultra, [cw] wenyan, etc.

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
FLAG="${CONFIG_DIR}/.caveman-active"

[ -f "$FLAG" ] || exit 0
# refuse symlinks -- security hardening
[ -L "$FLAG" ] && exit 0

mode=$(head -c 64 "$FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]')
mode=$(printf '%s' "$mode" | tr -cd 'a-z0-9-')

case "$mode" in
    ""|full)           printf '\033[38;5;172m[C]\033[0m'   ;;
    lite)              printf '\033[38;5;172m[c]\033[0m'   ;;
    ultra)             printf '\033[38;5;172m[C!]\033[0m'  ;;
    wenyan-lite)       printf '\033[38;5;172m[w]\033[0m'   ;;
    wenyan|wenyan-full) printf '\033[38;5;172m[W]\033[0m'  ;;
    wenyan-ultra)      printf '\033[38;5;172m[W!]\033[0m'  ;;
    commit)            printf '\033[38;5;172m[Cc]\033[0m'  ;;
    review)            printf '\033[38;5;172m[Cr]\033[0m'  ;;
    compress)          printf '\033[38;5;172m[Cp]\033[0m'  ;;
    off)               exit 0                              ;;
    *)                 printf '\033[38;5;172m[C]\033[0m'   ;;
esac
