#!/bin/sh -e
# lofi-docs-match: ratelimit plus a cli and formally capitalised docs. the doc
# edit should match the docs, the chat reply should stay lofi.
# shellcheck source-path=SCRIPTDIR source=_lib.sh
. "$(dirname "$0")/_lib.sh"

_seed_home
_lay ratelimit
_lay lofi-docs-match/files
_init_repo
