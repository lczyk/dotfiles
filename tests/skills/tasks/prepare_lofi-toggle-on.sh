#!/bin/sh -e
# lofi-toggle-on: lofi starts off. "lofi on" must remove the marker.
# shellcheck source-path=SCRIPTDIR source=_lib.sh
. "$(dirname "$0")/_lib.sh"

_seed_home
_styles off off
_lay ratelimit
_init_repo
