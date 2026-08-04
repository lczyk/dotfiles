#!/usr/bin/env bash
# hat badge. [H:yolo] (coloured) when this session's hat is yolo, plain [h]
# (no colour) otherwise -- unlike caveman/lofi/unfence, hat always renders
# once session_id is resolvable, so default is visibly "no colour" rather
# than absent.
#
# session correlation: hat state is per-session (one file per session_id, see
# hat-config.js), so the badge has to pull session_id out of its own stdin
# payload to look up the right file -- unlike caveman/lofi's single shared flag.

STATE_DIR="${AGENT_STATE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/agent-state}"
HATS_DIR="${STATE_DIR}/hats"
# shellcheck source-path=SCRIPTDIR source=../statusline-colour.sh
. "$(dirname "${BASH_SOURCE[0]}")/../statusline-colour.sh"

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

if command -v jq >/dev/null 2>&1; then
    session_id=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
else
    session_id=$(printf '%s' "$INPUT" \
        | tr '\n' ' ' \
        | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi
[ -z "$session_id" ] && exit 0

# sanitize the same way hat-config.js's sanitizeSessionId does -- defence in
# depth against a crafted id reaching a path.
safe_id=$(printf '%s' "$session_id" | tr -cd 'A-Za-z0-9_-' | head -c 128)
[ -z "$safe_id" ] && exit 0

FLAG="${HATS_DIR}/${safe_id}"

hat=""
if [ -f "$FLAG" ] && [ ! -L "$FLAG" ]; then
    hat=$(head -c 64 "$FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]')
    hat=$(printf '%s' "$hat" | tr -cd 'a-z0-9-')
fi

case "$hat" in
    yolo) sl_paint '5;165' "[H:yolo]" ;;
    *)    printf '[h]' ;;
esac
