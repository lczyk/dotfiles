#!/bin/sh -e
# lofi-commit: ratelimit with the limit-check fix left uncommitted in the
# worktree. the agent writes the commit message.
# shellcheck source-path=SCRIPTDIR source=_lib.sh
. "$(dirname "$0")/_lib.sh"

_seed_home
_lay ratelimit
_init_repo
_lay lofi-commit/change
