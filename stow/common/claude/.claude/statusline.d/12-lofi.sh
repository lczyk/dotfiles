#!/usr/bin/env bash
# lofi badge. [L] when the lofi style hooks are wired in settings.json and
# not switched off, [x] otherwise. off-state = marker file ~/.claude/.lofi-off
# (written by the /lofi skill; the hooks gate on it too).

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="${CONFIG_DIR}/settings.json"
OFF_MARKER="${CONFIG_DIR}/.lofi-off"
# shellcheck source-path=SCRIPTDIR source=../statusline-colour.sh
. "$(dirname "${BASH_SOURCE[0]}")/../statusline-colour.sh"


badge() { sl_paint '5;110' "[$1]"; }

if [ -f "$SETTINGS" ] && grep -q 'styles/lofi' "$SETTINGS" 2>/dev/null && [ ! -f "$OFF_MARKER" ]; then
    badge "L"
else
    badge "x"
fi
