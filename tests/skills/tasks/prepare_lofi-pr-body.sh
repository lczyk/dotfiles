#!/bin/sh -e
# lofi-pr-body: ratelimit plus one feature commit on top, for the agent to
# describe as a PR.
# shellcheck source-path=SCRIPTDIR source=_lib.sh
. "$(dirname "$0")/_lib.sh"

_seed_home
_lay ratelimit
_init_repo
_lay lofi-pr-body/feature
_git add -A
_git commit -q -m "feat: retry refused calls with backoff"
_mark_seed
