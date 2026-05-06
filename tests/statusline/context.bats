#!/usr/bin/env bats
# tests for stow/common/claude/.claude/statusline.d/30-context.sh

setup() {
    BADGE="$BATS_TEST_DIRNAME/../../stow/common/claude/.claude/statusline.d/30-context.sh"
}

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

run_badge() {
    run bash -c "printf '%s' \"\$1\" | '$BADGE'" _ "$1"
}

@test "uses used_percentage when present" {
    run_badge '{"context_window":{"used_percentage":42}}'
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[ctx 42%]" ]
}

@test "computes percentage from current_usage and size" {
    run_badge '{"context_window":{"current_usage":{"input_tokens":50,"cache_creation_input_tokens":25,"cache_read_input_tokens":25},"context_window_size":1000}}'
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[ctx 10%]" ]
}

@test "silent on empty stdin" {
    run bash -c "printf '' | '$BADGE'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "silent when context_window absent" {
    run_badge '{}'
    [ -z "$output" ]
}

@test "low usage uses green colour" {
    run_badge '{"context_window":{"used_percentage":10}}'
    [[ "$output" == *$'\x1b[38;5;71m'* ]]
}

@test "mid usage uses orange colour" {
    run_badge '{"context_window":{"used_percentage":60}}'
    [[ "$output" == *$'\x1b[38;5;214m'* ]]
}

@test "high usage uses red colour" {
    run_badge '{"context_window":{"used_percentage":85}}'
    [[ "$output" == *$'\x1b[38;5;196m'* ]]
}

@test "thresholds are inclusive at 50 and 80" {
    run_badge '{"context_window":{"used_percentage":50}}'
    [[ "$output" == *$'\x1b[38;5;214m'* ]]
    run_badge '{"context_window":{"used_percentage":80}}'
    [[ "$output" == *$'\x1b[38;5;196m'* ]]
}

@test "truncates fractional percentage" {
    run_badge '{"context_window":{"used_percentage":42.9}}'
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[ctx 42%]" ]
}

@test "silent on non-numeric used_percentage" {
    run_badge '{"context_window":{"used_percentage":"abc"}}'
    [ -z "$output" ]
}
