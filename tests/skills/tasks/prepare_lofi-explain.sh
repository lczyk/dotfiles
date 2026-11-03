#!/bin/sh -e
# lofi-explain: the ratelimit repo as is. the agent walks through it in chat.
# shellcheck source-path=SCRIPTDIR source=_lib.sh
. "$(dirname "$0")/_lib.sh"

_seed_home
_lay ratelimit
_init_repo
