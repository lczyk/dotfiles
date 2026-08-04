#!/usr/bin/env bats
# tests for stow/common/claude/.claude/statusline.d/14-unfence.sh

setup() {
    # badge colours are contrast-adjusted against the terminal background;
    # pin "unknown background" so assertions see the plain-foreground form.
    unset ALACRITTY_WINDOW_ID CLAUDE_STATUSLINE_BG
    unset AGENT_UNFENCE
    BADGE="$BATS_TEST_DIRNAME/../../stow/common/claude/.claude/statusline.d/14-unfence.sh"
}

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

fire() { printf '{}' | "$BADGE"; }

@test "silent when AGENT_UNFENCE is unset" {
    run fire
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "silent when AGENT_UNFENCE is empty" {
    AGENT_UNFENCE= run fire
    [ "$status" -eq 0 ]
    [ -z "$output" ]
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

@test "silent when the value is only separators" {
    AGENT_UNFENCE=',,,' run fire
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "squeezes and trims stray commas" {
    AGENT_UNFENCE=',branch,,meta,' run fire
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[U:branch,meta]" ]
}
