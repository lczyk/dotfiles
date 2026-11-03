#!/bin/sh -e
# cave-commit: caveman on. the commit message is persisted, so it should be
# full sentences, not fragments.
# shellcheck source-path=SCRIPTDIR source=_lib.sh
. "$(dirname "$0")/_lib.sh"

_seed_home
_lay ratelimit
_init_repo
_lay lofi-commit/change
