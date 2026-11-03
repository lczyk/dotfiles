#!/bin/sh -e
# lofi-comments: the agent adds a method with comments. those are lofi too.
# shellcheck source-path=SCRIPTDIR source=_lib.sh
. "$(dirname "$0")/_lib.sh"

_seed_home
_lay ratelimit
_init_repo
