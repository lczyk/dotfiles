#!/bin/sh -e
# lofi-repo-rules: an AGENTS.md asks for capitalised commit bodies. the
# commit follows the repo, the chat reply stays lofi.
# shellcheck source-path=SCRIPTDIR source=_lib.sh
. "$(dirname "$0")/_lib.sh"

_seed_home
_lay ratelimit
_lay lofi-repo-rules/files
_init_repo
_lay lofi-commit/change
