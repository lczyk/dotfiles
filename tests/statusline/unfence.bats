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

@test "meta gets the loud fable-style badge" {
    AGENT_UNFENCE=branch,meta run fire
    [ "$output" = $'\033[1;97;41m[U:branch,meta]\033[0m' ]
}

@test "non-meta capabilities keep the bright red badge" {
    AGENT_UNFENCE=branch,push run fire
    [ "$output" = $'\033[91m[U:branch,push]\033[0m' ]
}

@test "metadata-looking token does not count as meta" {
    AGENT_UNFENCE=metal run fire
    [ "$output" = $'\033[91m[U:metal]\033[0m' ]
}
