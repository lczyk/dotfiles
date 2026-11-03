#!/bin/sh -e
# lofi-long: fix, test, docs, commit, summary. many tool calls before the
# last reply, to see whether the style wears off.
# shellcheck source-path=SCRIPTDIR source=_lib.sh
. "$(dirname "$0")/_lib.sh"

_seed_home
_lay ratelimit
_init_repo
