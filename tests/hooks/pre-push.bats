#!/usr/bin/env bats
# tests for stow/common/git/.config/git/hooks/pre-push

setup() {
    HOOK="$BATS_TEST_DIRNAME/../../stow/common/git/.config/git/hooks/pre-push"
}

@test "blocks push under CLAUDECODE=1" {
    CLAUDECODE=1 run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "passes when CLAUDECODE unset" {
    unset CLAUDECODE
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "passes when CLAUDECODE is empty" {
    CLAUDECODE="" run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "passes when CLAUDECODE is some other value" {
    CLAUDECODE=0 run "$HOOK"
    [ "$status" -eq 0 ]
}
