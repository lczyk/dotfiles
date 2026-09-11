#!/usr/bin/env bats
# tests for stow/common/claude/.claude/statusline.d/14-unfence.sh

setup() {
    unset AGENT_UNFENCE
    BADGE="$BATS_TEST_DIRNAME/../../stow/common/claude/.claude/statusline.d/14-unfence.sh"
}

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

fire() { printf '{}' | "$BADGE"; }

@test "[u] plain when AGENT_UNFENCE is unset" {
    run fire
    [ "$status" -eq 0 ]
    [ "$output" = "[u]" ]
}

@test "[u] plain when AGENT_UNFENCE is empty" {
    AGENT_UNFENCE= run fire
    [ "$status" -eq 0 ]
    [ "$output" = "[u]" ]
}

@test "shows a single capability" {
    AGENT_UNFENCE=branch run fire
    [ "$status" -eq 0 ]
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[U:branch]" ]
}

@test "shows multiple capabilities" {
    AGENT_UNFENCE=branch,meta run fire
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[U:branch,meta]" ]
}

@test "strips junk characters from the value" {
    AGENT_UNFENCE='branch;$(rm x),meta' run fire
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[U:branchrmx,meta]" ]
}

@test "[u] plain when the value is only separators" {
    AGENT_UNFENCE=',,,' run fire
    [ "$status" -eq 0 ]
    [ "$output" = "[u]" ]
}

@test "squeezes and trims stray commas" {
    AGENT_UNFENCE=',branch,,meta,' run fire
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[U:branch,meta]" ]
}
