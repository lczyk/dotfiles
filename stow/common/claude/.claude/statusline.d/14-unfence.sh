#!/usr/bin/env bash
# unfence badge. [U:branch,meta] (coloured) when the session was launched
# with AGENT_UNFENCE capabilities, plain [u] (no colour) otherwise -- the
# failure mode this guards is forgetting a fence is down, so the badge always
# renders and a plain [u] still says "no fence lifted" rather than nothing.

# shellcheck source-path=SCRIPTDIR source=../statusline-colour.sh
. "$(dirname "${BASH_SOURCE[0]}")/../statusline-colour.sh"

# the tokens come from the fences' own lib, so the badge lists exactly the
# capabilities a fence would honour. without the lib the fences deny
# everything, so say that rather than [u].
_lib="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../../agent-hooks/.config/agent-hooks/lib.sh"
[ -r "$_lib" ] || _lib="$HOME/.config/agent-hooks/lib.sh"
# shellcheck source-path=SCRIPTDIR source=../../../agent-hooks/.config/agent-hooks/lib.sh
if ! . "$_lib" 2>/dev/null; then
    sl_paint "$SL_BRED" "[U:?]"
    exit 0
fi

caps=$(_unfence_tokens | tr '\n' ',')
caps=${caps%,}

if [ -n "$caps" ]; then
    # meta lifts the hook fence itself, so it gets the same loud bold white on red as fable 5
    if _unfenced meta; then
        printf '\033[1;%s;4%sm[U:%s]\033[0m' "$SL_BWHITE" "${SL_RED#3}" "${caps:0:40}"
    else
        sl_paint "$SL_BRED" "[U:${caps:0:40}]"
    fi
else
    printf '[u]'
fi
