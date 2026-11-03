#!/bin/sh -e
# lofi-off-then: "lofi off", then a walk-through in the same prompt. the
# reply should already be in normal capitalisation.
# shellcheck source-path=SCRIPTDIR source=_lib.sh
. "$(dirname "$0")/_lib.sh"

_seed_home
_lay ratelimit
_init_repo
