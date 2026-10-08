#!/usr/bin/env bash
# unfence badge. [U:branch,meta] (coloured) when the session was launched
# with AGENT_UNFENCE capabilities, plain [u] (no colour) otherwise -- the
# failure mode this guards is forgetting a fence is down, so the badge always
# renders and a plain [u] still says "no fence lifted" rather than nothing.

# shellcheck source-path=SCRIPTDIR source=../statusline-colour.sh
. "$(dirname "${BASH_SOURCE[0]}")/../statusline-colour.sh"

if [ -n "$AGENT_UNFENCE" ]; then
    # normalise: drop anything but token chars, squeeze stray separators.
    caps=$(printf '%s' "$AGENT_UNFENCE" | tr -cd 'A-Za-z0-9,_-' | tr -s ',')
    caps=${caps#,}; caps=${caps%,}
fi

if [ -n "$caps" ]; then
    # meta lifts the hook fence itself, so it gets the same loud bold white on red as fable 5
    case ",$caps," in
        *,meta,*) printf '\033[1;%s;4%sm[U:%s]\033[0m' "$SL_BWHITE" "${SL_RED#3}" "${caps:0:40}" ;;
        *)        sl_paint "$SL_BRED" "[U:${caps:0:40}]" ;;
    esac
else
    printf '[u]'
fi
