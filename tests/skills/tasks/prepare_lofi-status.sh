#!/bin/sh -e
# lofi-status: lofi starts off. asking for the status must not flip it.
# shellcheck source-path=SCRIPTDIR source=_lib.sh
. "$(dirname "$0")/_lib.sh"

_seed_home
_styles off off
_lay ratelimit
_init_repo
