#!/usr/bin/env bash
# predicate: exit 0 if the command line is a recursive-force `rm` worth dropping
# from shell history, exit 1 otherwise. matches combined (`rm -rf`), split
# (`rm -r -f`), long (`rm --recursive --force`), capital `-R`, flags in any
# order, and occurrences inside pipelines / chains (`ls | xargs -r rm -rf`).
# needing BOTH a recursive and a force flag spares innocuous `rm -f` / `rm -r`.
#
# single source of truth: the fish history hook (conf.d/scrub_history.fish)
# calls this, and tests/fish/scrub-history.bats exercises it directly.
cmd="${1-}"
[[ -n $cmd ]] || exit 1
# a bare `rm`, not a substring like `confirm` / `perm` / `alarm`
[[ $cmd =~ (^|[^[:alnum:]_])rm([^[:alnum:]_]|$) ]] || exit 1
# recursive flag: a -...r / -...R short bundle, or --recursive
[[ $cmd =~ (^|[[:space:]])-[a-zA-Z]*[rR] || $cmd =~ --recursive([^a-zA-Z]|$) ]] || exit 1
# force flag: a -...f short bundle, or --force
[[ $cmd =~ (^|[[:space:]])-[a-zA-Z]*f || $cmd =~ --force([^a-zA-Z]|$) ]] || exit 1
exit 0
