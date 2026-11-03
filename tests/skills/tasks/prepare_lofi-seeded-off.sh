#!/bin/sh -e
# lofi-seeded-off: lofi starts off, so the hooks stay quiet and the walk-
# through should come back in normal capitalisation.
# shellcheck source-path=SCRIPTDIR source=_lib.sh
. "$(dirname "$0")/_lib.sh"

_seed_home
_styles off off
_lay ratelimit
_init_repo
