#!/usr/bin/env bash
# lofi badge. [L] when Kimi's config.toml wires the shared style hooks and the
# shared agent-state off marker is absent, [x] otherwise.

CONFIG_DIR="${KIMI_CODE_HOME:-$HOME/.kimi-code}"
SETTINGS="${CONFIG_DIR}/config.toml"
STATE_DIR="${AGENT_STATE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/agent-state}"
OFF_MARKER="${STATE_DIR}/lofi-off"
# shellcheck source-path=SCRIPTDIR source=../statusline-colour.sh
. "$(dirname "${BASH_SOURCE[0]}")/../statusline-colour.sh"

badge() { sl_paint "$SL_CYAN" "[$1]"; }

if grep -q 'agent-styles/lofi' "$SETTINGS" 2>/dev/null && [ ! -f "$OFF_MARKER" ]; then
    badge "L"
else
    badge "x"
fi
