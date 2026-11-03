#!/bin/sh -e
# lofi-pr-template: lofi-pr-body with a PR template, whose headers stay as
# written.
# shellcheck source-path=SCRIPTDIR source=_lib.sh
. "$(dirname "$0")/_lib.sh"

_seed_home
_lay ratelimit
_lay lofi-pr-template/files
_init_repo
_lay lofi-pr-body/feature
_git add -A
_git commit -q -m "feat: retry refused calls with backoff"
_mark_seed
_verbatim "## Proposed changes" "## Testing"
