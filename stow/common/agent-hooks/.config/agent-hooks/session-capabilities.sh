#!/usr/bin/env bash
# session-start context: the AGENT_UNFENCE capabilities this session carries,
# so an agent reads the fact instead of having to remember to check it.
# the tokens come from the fences' own lib, so the line lists exactly what a
# fence would honour, and free env text never reaches the context.

# shellcheck source-path=SCRIPTDIR source=lib.sh
if ! . "$(dirname "$(readlink -f "$0")")/lib.sh" 2>/dev/null; then
    echo "AGENT_UNFENCE: unknown (agent-hooks lib.sh is missing) -- run printenv AGENT_UNFENCE before saying what this session can or can't do."
    exit 0
fi

caps=$(_unfence_tokens | paste -sd, -)
if [ -n "$caps" ]; then
    echo "AGENT_UNFENCE: $caps -- this session carries these capabilities, so use them. no relaunch needed for anything they cover."
else
    echo "AGENT_UNFENCE: none -- a fenced write needs the user to relaunch with the matching capability."
fi
