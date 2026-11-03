#!/bin/sh -e
# uniform across tasks: hook markers and skill state from the agent's HOME,
# and the fixture repo's git state relative to the seed commit.
# shellcheck source-path=SCRIPTDIR source=_lib.sh
. "$(dirname "$0")/_lib.sh"

_copy_dir() {
    mkdir -p "${PATS_OUTPUT_DIR}/$2"
    if [ -d "${PATS_AGENT_HOME}/$1" ]; then
        cp -R "${PATS_AGENT_HOME}/$1/." "${PATS_OUTPUT_DIR}/$2/"
    fi
}

_copy_dir .pats-canary canary
_copy_dir .config/agent-state agent-state

_git log --format='%H%n%B%n--' >"${PATS_OUTPUT_DIR}/git-log.txt"
_git status --porcelain >"${PATS_OUTPUT_DIR}/git-status.txt"
_git branch --format='%(refname:short)' >"${PATS_OUTPUT_DIR}/git-branches.txt"

SEED=$(cat "${PATS_OUTPUT_DIR}/seed.sha")
# messages of the commits the agent made, oldest first.
_git log --reverse --format='%B%n--' "${SEED}..HEAD" >"${PATS_OUTPUT_DIR}/new-commits.txt"
# everything the agent changed since the seed, committed or not. intent-to-add
# first so new files show up too.
_git add -N .
# fixed prefixes, since the seeded config sets diff.mnemonicPrefix.
_git diff --src-prefix=a/ --dst-prefix=b/ "${SEED}" >"${PATS_OUTPUT_DIR}/diff.txt"
