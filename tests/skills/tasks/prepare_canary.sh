#!/bin/sh -e
# canary: a one-file repo. the task only checks the seeded hooks fire.
# shellcheck source-path=SCRIPTDIR source=_lib.sh
. "$(dirname "$0")/_lib.sh"

_seed_home
printf '# canary\n' >"${PATS_WORKDIR}/README.md"
_init_repo
