#!/usr/bin/env bash
# caveman badge. Kimi hooks are configured in config.toml; mode state is shared
# through agent-state. [C] full, [c] lite, [C!] ultra, [x] off/missing.

CONFIG_DIR="${KIMI_CODE_HOME:-$HOME/.kimi-code}"
STATE_DIR="${AGENT_STATE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/agent-state}"
FLAG="${STATE_DIR}/caveman-active"
SETTINGS="${CONFIG_DIR}/config.toml"
# shellcheck source-path=SCRIPTDIR source=../statusline-colour.sh
. "$(dirname "${BASH_SOURCE[0]}")/../statusline-colour.sh"

badge() { sl_paint "$SL_BYELLOW" "[$1]"; }

if ! grep -Eq 'caveman-(activate|mode-tracker)' "$SETTINGS" 2>/dev/null; then
    badge "x"
    exit 0
fi

[ -f "$FLAG" ] || { badge "x"; exit 0; }
[ -L "$FLAG" ] && { badge "x"; exit 0; }

mode=$(head -c 64 "$FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]')
mode=$(printf '%s' "$mode" | tr -cd 'a-z0-9-')

case "$mode" in
    ""|full)   badge "C"  ;;
    lite)      badge "c"  ;;
    ultra)     badge "C!" ;;
    commit)    badge "Cc" ;;
    compress)  badge "Cp" ;;
    off)       badge "x"  ;;
    *)         badge "C"  ;;
esac
