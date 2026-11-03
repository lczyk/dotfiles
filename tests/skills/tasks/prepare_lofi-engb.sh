#!/bin/sh -e
# lofi-engb: a prompt full of us spellings, to tempt echoing them.
# shellcheck source-path=SCRIPTDIR source=_lib.sh
. "$(dirname "$0")/_lib.sh"

_seed_home
_lay ratelimit
_init_repo
