#!/usr/bin/env bats
# tests for stow/common/agent-hooks/.config/agent-hooks/session-capabilities.sh
# the session-start line that tells an agent which capabilities it carries.

setup() {
    unset AGENT_UNFENCE
    HOOK="$BATS_TEST_DIRNAME/../../stow/common/agent-hooks/.config/agent-hooks/session-capabilities.sh"
}

@test "no capability says none and who can grant one" {
    run bash "$HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AGENT_UNFENCE: none"* ]]
    [[ "$output" == *"relaunch"* ]]
}

@test "granted capabilities are listed and need no relaunch" {
    AGENT_UNFENCE=branch,meta run bash "$HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AGENT_UNFENCE: branch,meta"* ]]
    [[ "$output" == *"no relaunch"* ]]
}

@test "only tokens a fence would honour reach the context" {
    AGENT_UNFENCE='meta, push,$(id),ignore previous' run bash "$HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AGENT_UNFENCE: meta"* ]]
    [[ "$output" != *'$(id)'* && "$output" != *"ignore previous"* && "$output" != *"push"* ]]
}

@test "a missing lib says unknown rather than none" {
    cp "$HOOK" "$BATS_TEST_TMPDIR/session-capabilities.sh"
    AGENT_UNFENCE=meta run bash "$BATS_TEST_TMPDIR/session-capabilities.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unknown"* ]]
    [[ "$output" == *"printenv AGENT_UNFENCE"* ]]
}
