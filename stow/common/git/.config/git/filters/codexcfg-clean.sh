#!/bin/sh -e

# git clean filter for Codex config.toml. Codex persists machine-local state in
# the same file as user settings; keep that state live while excluding it from
# commits.

awk '
function is_transient_table(line) {
    return line ~ /^\[projects\./ ||
        line == "[tui.model_availability_nux]" ||
        line == "[hooks.state]" ||
        line ~ /^\[hooks\.state\./
}

# top-level model pin is machine-local: the /model picker rewrites it. only
# top-level -- a model key inside a named table (e.g. a profile) stays.
!seen_table && /^model(_reasoning_effort)?[ \t]*=/ {
    next
}

/^\[/ {
    seen_table = 1
}

is_transient_table($0) {
    skipping = 1
    next
}

/^\[/ {
    if (skipping) {
        if (emitted) print ""
        skipping = 0
    }
}

!skipping {
    print
    emitted = 1
}
'
