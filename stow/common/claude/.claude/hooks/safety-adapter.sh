#!/usr/bin/env bash
# Claude PreToolUse hook. the shared adapter next to the agent policies owns
# the payload and verdict translation; found through this file's real path,
# then through the installed dir.

adapter="$(dirname "$(readlink -f "$0")")/../../../agent-hooks/.config/agent-hooks/adapter.sh"
[ -r "$adapter" ] || adapter="$HOME/.config/agent-hooks/adapter.sh"
[ -r "$adapter" ] || { echo "BLOCKED: agent-hooks adapter.sh not found (stow agent-hooks)" >&2; exit 2; }
exec bash "$adapter" claude "$@"
