#!/bin/sh -e
# uniform across tasks: hook markers from the agent's HOME and the fixture
# repo's git state.
# shellcheck source-path=SCRIPTDIR source=_lib.sh
. "$(dirname "$0")/_lib.sh"

mkdir -p "${PATS_OUTPUT_DIR}/canary"
if [ -d "${PATS_AGENT_HOME}/.pats-canary" ]; then
    cp -R "${PATS_AGENT_HOME}/.pats-canary/." "${PATS_OUTPUT_DIR}/canary/"
fi

_git log --format='%H%n%B%n--' >"${PATS_OUTPUT_DIR}/git-log.txt"
_git status --porcelain >"${PATS_OUTPUT_DIR}/git-status.txt"
_git branch --format='%(refname:short)' >"${PATS_OUTPUT_DIR}/git-branches.txt"
