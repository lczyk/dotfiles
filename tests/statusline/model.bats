#!/usr/bin/env bats
# tests for stow/common/claude/.claude/statusline.d/20-model.sh

setup() {
    BADGE="$BATS_TEST_DIRNAME/../../stow/common/claude/.claude/statusline.d/20-model.sh"
}

# strip ansi escape sequences so assertions can match plain text
strip_ansi() {
    sed 's/\x1b\[[0-9;]*m//g'
}

@test "prints display_name from json" {
    run bash -c "echo '{\"model\":{\"display_name\":\"Opus 4.7\"}}' | '$BADGE'"
    [ "$status" -eq 0 ]
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[Opus 4.7]" ]
}

@test "falls back to model.id when no display_name" {
    run bash -c "echo '{\"model\":{\"id\":\"claude-opus-4-7\"}}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[claude-opus-4-7]" ]
}

@test "silent on empty stdin" {
    run bash -c "printf '' | '$BADGE'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "silent when model field absent" {
    run bash -c "echo '{}' | '$BADGE'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "strips characters outside whitelist" {
    run bash -c "echo '{\"model\":{\"display_name\":\"weird\$\$name\"}}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[weirdname]" ]
}

@test "caps name length at 32 chars" {
    long=$(printf 'A%.0s' {1..50})
    run bash -c "echo '{\"model\":{\"display_name\":\"$long\"}}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    inside=${out#[}; inside=${inside%]}
    [ "${#inside}" -eq 32 ]
}

@test "blocks ansi-escape injection in name" {
    # name with a `[31m`-shaped substring that's not a real ansi escape;
    # whitelist allows the chars but no esc byte ever reaches stdout.
    run bash -c "echo '{\"model\":{\"display_name\":\"[31mevil\"}}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[31mevil]" ]
    # no real escape byte should appear anywhere in raw output beyond the badge's own colour codes
    raw_no_colour=$(printf '%s' "$output" | sed 's/\x1b\[38;5;[0-9]*m//g; s/\x1b\[0m//g')
    [[ "$raw_no_colour" != *$'\x1b'* ]]
}
