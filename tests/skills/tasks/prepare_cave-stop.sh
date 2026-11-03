#!/bin/sh -e
# cave-stop: caveman on. a bare "normal mode" prompt must switch it off.
# shellcheck source-path=SCRIPTDIR source=_lib.sh
. "$(dirname "$0")/_lib.sh"

_seed_home
_lay ratelimit
_init_repo
