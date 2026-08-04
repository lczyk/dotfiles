#!/usr/bin/env bash
# unfence badge. [U:branch,meta] when the session was launched with
# AGENT_UNFENCE capabilities, silent otherwise. the failure mode this guards
# is forgetting a fence is down -- so the badge only ever shows the granted
# state, never a quiet default.

# shellcheck source-path=SCRIPTDIR source=../statusline-colour.sh
. "$(dirname "${BASH_SOURCE[0]}")/../statusline-colour.sh"

[ -n "$AGENT_UNFENCE" ] || exit 0

# normalise: drop anything but token chars, squeeze stray separators.
caps=$(printf '%s' "$AGENT_UNFENCE" | tr -cd 'A-Za-z0-9,_-' | tr -s ',')
caps=${caps#,}; caps=${caps%,}
[ -n "$caps" ] || exit 0

sl_paint '5;208' "[U:${caps:0:40}]"
