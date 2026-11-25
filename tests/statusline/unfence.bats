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

@test "drops tokens no capability check can match" {
    AGENT_UNFENCE='branch;$(rm x),meta' run fire
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[U:meta]" ]
}

@test "a spaced token is not shown: the fences don't honour it either" {
    AGENT_UNFENCE='branch, meta' run fire
    [ "$output" = $'\033[91m[U:branch]\033[0m' ]
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

@test "only the word meta gets the loud fable-style background" {
    AGENT_UNFENCE=branch,meta run fire
    [ "$output" = $'\033[91m[U:branch,\033[0m\033[1;97;41mmeta\033[0m\033[91m]\033[0m' ]
}

@test "history gets the loud background too" {
    AGENT_UNFENCE=history,push run fire
    [ "$output" = $'\033[91m[U:\033[0m\033[1;97;41mhistory\033[0m\033[91m,push]\033[0m' ]
}

@test "meta and history are each loud, the comma between them is not" {
    AGENT_UNFENCE=meta,history run fire
    [ "$output" = $'\033[91m[U:\033[0m\033[1;97;41mmeta\033[0m\033[91m,\033[0m\033[1;97;41mhistory\033[0m\033[91m]\033[0m' ]
}

@test "long capability lists are cut at 40 visible chars" {
    AGENT_UNFENCE=branch,history,remote,push,pr,issue,labels,meta run fire
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[U:branch,history,remote,push,pr,issue,labe]" ]
}

@test "a token cut down to meta by the length cap stays plain" {
    AGENT_UNFENCE=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,metal run fire
    [ "$output" = $'\033[91m[U:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,meta]\033[0m' ]
}

@test "non-meta capabilities keep the bright red badge" {
    AGENT_UNFENCE=branch,push run fire
    [ "$output" = $'\033[91m[U:branch,push]\033[0m' ]
}

@test "metadata-looking token does not count as meta" {
    AGENT_UNFENCE=metal run fire
    [ "$output" = $'\033[91m[U:metal]\033[0m' ]
}
