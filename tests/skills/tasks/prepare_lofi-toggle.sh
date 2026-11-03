#!/bin/sh -e
# lofi-toggle: does "lofi off" reach the lofi skill and flip its state file?
# shellcheck source-path=SCRIPTDIR source=_lib.sh
. "$(dirname "$0")/_lib.sh"

_seed_home
_lay ratelimit
_init_repo
