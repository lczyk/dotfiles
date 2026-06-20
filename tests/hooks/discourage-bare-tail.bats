#!/usr/bin/env bats
# tests for stow/common/claude/.claude/hooks/discourage-bare-tail.sh
# the hook reads claude-code's PreToolUse JSON on stdin and exits 2 to block
# a bare `| tail` / `| head` (or `tail <(...)` procsub) that isn't tee'd to
# /tmp/claude/log/.

setup() {
    HOOK="$BATS_TEST_DIRNAME/../../stow/common/claude/.claude/hooks/discourage-bare-tail.sh"
}

# pipe a fake PreToolUse payload with the given Bash command. RE_ENGINE (if
# exported) forces a specific regex engine; otherwise the hook auto-picks.
fire() {
    local cmd="$1"
    printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$cmd" | jq -Rs .)" \
        | "$HOOK"
}

# -- blocked: bare pipe to tail / head ----------------------------------

@test "blocks bare | tail" {
    run fire "cat big.log | tail"
    [ "$status" -eq 2 ]
}

@test "blocks bare | tail -50" {
    run fire "cat big.log | tail -50"
    [ "$status" -eq 2 ]
}

@test "blocks bare | head" {
    run fire "grep foo big.log | head -20"
    [ "$status" -eq 2 ]
}

@test "blocks | tail with no space before flag" {
    run fire "cmd |tail"
    [ "$status" -eq 2 ]
}

# -- blocked: process-substitution forms --------------------------------

@test "blocks tail <(...)" {
    run fire "tail <(cmd)"
    [ "$status" -eq 2 ]
}

@test "blocks head <(...)" {
    run fire "head -5 <(cmd)"
    [ "$status" -eq 2 ]
}

# -- allowed: tee'd into the log dir ------------------------------------

@test "allows tee to log dir then tail" {
    run fire "cmd 2>&1 | tee /tmp/claude/log/x.log | tail -50"
    [ "$status" -eq 0 ]
}

@test "allows tee -a (append) to log dir then tail" {
    run fire "cmd 2>&1 | tee -a /tmp/claude/log/x.log | tail"
    [ "$status" -eq 0 ]
}

@test "allows tee to quoted log path then tail" {
    run fire "cmd | tee \"/tmp/claude/log/x.log\" | tail -20"
    [ "$status" -eq 0 ]
}

@test "allows multi-file tee where log dir is not first then head" {
    run fire "cmd | tee out.txt /tmp/claude/log/x.log | head"
    [ "$status" -eq 0 ]
}

# -- allowed: no tail / head at all -------------------------------------

@test "allows plain command" {
    run fire "ls -la"
    [ "$status" -eq 0 ]
}

@test "allows tail as a substring of another word" {
    run fire "cat detail.txt"
    [ "$status" -eq 0 ]
}

@test "allows heading as a substring of another word" {
    run fire "echo heading | cat"
    [ "$status" -eq 0 ]
}

# -- regex engine cascade: same verdict under rg / grep / awk -----------

@test "rg engine: blocks bare tail, allows tee'd tail" {
    RE_ENGINE=rg run fire "cmd | tail"
    [ "$status" -eq 2 ]
    RE_ENGINE=rg run fire "cmd | tee /tmp/claude/log/x.log | tail"
    [ "$status" -eq 0 ]
}

@test "grep engine: blocks bare tail, allows tee'd tail" {
    RE_ENGINE=grep run fire "cmd | tail"
    [ "$status" -eq 2 ]
    RE_ENGINE=grep run fire "cmd | tee /tmp/claude/log/x.log | tail"
    [ "$status" -eq 0 ]
}

@test "awk engine: blocks bare tail, allows tee'd tail" {
    RE_ENGINE=awk run fire "cmd | tail"
    [ "$status" -eq 2 ]
    RE_ENGINE=awk run fire "cmd | tee /tmp/claude/log/x.log | tail"
    [ "$status" -eq 0 ]
}

@test "awk engine: blocks procsub tail" {
    RE_ENGINE=awk run fire "tail <(cmd)"
    [ "$status" -eq 2 ]
}

# -- known gaps (xfail) -------------------------------------------------
# documented TODOs in the hook header -- both need real shell parsing the
# regex approach can't do, so they currently over-/under-match. each test
# asserts the IDEAL verdict and is skipped; drop the skip once the hook
# handles the case and it becomes a live regression guard.

@test "xfail: \$LOG-expanded tee path should be allowed" {
    skip "hook can't expand \$LOG -- over-blocks (currently exits 2)"
    run fire 'LOG=/tmp/claude/log/x.log; cmd | tee $LOG | tail'
    [ "$status" -eq 0 ]
}

@test "xfail: literal '| tail' inside a quoted string should be allowed" {
    skip "hook can't tell a quoted literal from a real pipe -- over-blocks (currently exits 2)"
    run fire 'git commit -m "fix | tail crash"'
    [ "$status" -eq 0 ]
}
