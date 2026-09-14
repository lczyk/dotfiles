#!/usr/bin/env bats
# tests for stow/common/agent-hooks/.config/agent-hooks/discourage-bare-tail.sh
# the policy reads a neutral shell request and exits 0 with a hint for a bare `| tail`
# / `| head` (or process substitution) that isn't tee'd to /tmp/ai/log/.

setup() {
    HOOK="$BATS_TEST_DIRNAME/../../stow/common/agent-hooks/.config/agent-hooks/discourage-bare-tail.sh"
}

# pipe a neutral shell request with the given command. RE_ENGINE is retained
# for parity checks across available regex implementations.
fire() {
    local cmd="$1"
    printf '{"version":1,"operation":"shell","command":%s}' "$(printf '%s' "$cmd" | jq -Rs .)" \
        | "$HOOK"
}

# -- hints: bare pipe to tail / head ----------------------------------

@test "hints for bare | tail" {
    run fire "cat big.log | tail"
    [ "$status" -eq 0 ]
    [[ "$output" == HINT:* ]]
}

@test "hints for bare | tail -50" {
    run fire "cat big.log | tail -50"
    [ "$status" -eq 0 ]
    [[ "$output" == HINT:* ]]
}

@test "hints for bare | head" {
    run fire "grep foo big.log | head -20"
    [ "$status" -eq 0 ]
    [[ "$output" == HINT:* ]]
}

@test "hints for | tail with no space before flag" {
    run fire "cmd |tail"
    [ "$status" -eq 0 ]
    [[ "$output" == HINT:* ]]
}

# -- hints: process-substitution forms --------------------------------

@test "hints for tail <(...)" {
    run fire "tail <(cmd)"
    [ "$status" -eq 0 ]
    [[ "$output" == HINT:* ]]
}

@test "hints for head <(...)" {
    run fire "head -5 <(cmd)"
    [ "$status" -eq 0 ]
    [[ "$output" == HINT:* ]]
}

# -- allowed: tee'd into the log dir ------------------------------------

@test "allows tee to log dir then tail" {
    run fire "cmd 2>&1 | tee /tmp/ai/log/x.log | tail -50"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "allows tee -a (append) to log dir then tail" {
    run fire "cmd 2>&1 | tee -a /tmp/ai/log/x.log | tail"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "allows tee to quoted log path then tail" {
    run fire "cmd | tee \"/tmp/ai/log/x.log\" | tail -20"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "allows multi-file tee where log dir is not first then head" {
    run fire "cmd | tee out.txt /tmp/ai/log/x.log | head"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# -- allowed: no tail / head at all -------------------------------------

@test "allows plain command" {
    run fire "ls -la"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "allows tail as a substring of another word" {
    run fire "cat detail.txt"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "allows heading as a substring of another word" {
    run fire "echo heading | cat"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# -- the tee must be in the SAME pipeline as the tail --------------------

@test "hints for a second, un-tee'd pipeline after && " {
    run fire "cmd | tee /tmp/ai/log/x.log | tail -5 && other | tail -5"
    [ "$status" -eq 0 ]
    [[ "$output" == HINT:* ]]
}

@test "hints for a second, un-tee'd pipeline after ;" {
    run fire "cmd | tee /tmp/ai/log/x.log | tail -5; other | head -5"
    [ "$status" -eq 0 ]
    [[ "$output" == HINT:* ]]
}

@test "hints for a second, un-tee'd pipeline after ||" {
    run fire "cmd | tee /tmp/ai/log/x.log | tail -5 || other | tail -5"
    [ "$status" -eq 0 ]
    [[ "$output" == HINT:* ]]
}

@test "allows chained pipelines when each tees" {
    run fire "cmd | tee /tmp/ai/log/a.log | tail -5 && other | tee /tmp/ai/log/b.log | tail -5"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "allows a tee'd pipeline chained with a plain command" {
    run fire "cmd | tee /tmp/ai/log/x.log | tail -5 && echo done"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# -- wrapped lines must not open a hole ---------------------------------

@test "hints for a pipe to tail split across lines" {
    run fire "cmd |
tail -5"
    [ "$status" -eq 0 ]
    [[ "$output" == HINT:* ]]
}

@test "hints for a line-continued pipe to tail" {
    run fire "cmd | \\
tail -5"
    [ "$status" -eq 0 ]
    [[ "$output" == HINT:* ]]
}

# -- regex engine cascade: same verdict under rg / grep / awk -----------

@test "rg engine: hints for bare tail, allows tee'd tail" {
    RE_ENGINE=rg run fire "cmd | tail"
    [ "$status" -eq 0 ]
    [[ "$output" == HINT:* ]]
    RE_ENGINE=rg run fire "cmd | tee /tmp/ai/log/x.log | tail"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "grep engine: hints for bare tail, allows tee'd tail" {
    RE_ENGINE=grep run fire "cmd | tail"
    [ "$status" -eq 0 ]
    [[ "$output" == HINT:* ]]
    RE_ENGINE=grep run fire "cmd | tee /tmp/ai/log/x.log | tail"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "awk engine: hints for bare tail, allows tee'd tail" {
    RE_ENGINE=awk run fire "cmd | tail"
    [ "$status" -eq 0 ]
    [[ "$output" == HINT:* ]]
    RE_ENGINE=awk run fire "cmd | tee /tmp/ai/log/x.log | tail"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "awk engine: hints for procsub tail" {
    RE_ENGINE=awk run fire "tail <(cmd)"
    [ "$status" -eq 0 ]
    [[ "$output" == HINT:* ]]
}

@test "quoted pipeline text stays advisory" {
    run fire 'rg "tee|head|tail" file'
    [ "$status" -eq 0 ]
    [[ "$output" == HINT:* ]]
}
