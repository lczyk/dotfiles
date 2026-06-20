#!/usr/bin/env bats
# tests for stow/common/claude/.claude/hooks/enforce-log-suffix.sh
# the hook reads claude-code's PreToolUse JSON on stdin and exits 2 to block
# any write under /tmp/claude/log/ whose final path component is not *.log.

setup() {
    HOOK="$BATS_TEST_DIRNAME/../../stow/common/claude/.claude/hooks/enforce-log-suffix.sh"
}

# pipe a fake PreToolUse payload with the given Bash command. RE_ENGINE (if
# exported) forces a specific regex engine; otherwise the hook auto-picks.
fire() {
    local cmd="$1"
    printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$cmd" | jq -Rs .)" \
        | "$HOOK"
}

# -- blocked: non-.log file under the log dir ---------------------------

@test "blocks .txt under log dir" {
    run fire "cmd 2>&1 | tee /tmp/claude/log/foo.txt"
    [ "$status" -eq 2 ]
}

@test "blocks extensionless file under log dir" {
    run fire "cmd > /tmp/claude/log/foo 2>&1"
    [ "$status" -eq 2 ]
}

@test "blocks .json redirect under log dir" {
    run fire "cmd >/tmp/claude/log/out.json"
    [ "$status" -eq 2 ]
}

@test "blocks file not ending in .log even if .log appears earlier" {
    run fire "cmd 2>&1 | tee /tmp/claude/log/foo.log.txt | tail -5"
    [ "$status" -eq 2 ]
}

@test "blocks quoted non-.log path" {
    run fire "cmd | tee \"/tmp/claude/log/foo.txt\""
    [ "$status" -eq 2 ]
}

@test "blocks non-.log path with trailing semicolon" {
    run fire "cmd >/tmp/claude/log/x.txt;"
    [ "$status" -eq 2 ]
}

@test "blocks non-.log path inside subshell parens" {
    run fire "(cmd > /tmp/claude/log/x.txt)"
    [ "$status" -eq 2 ]
}

@test "blocks when one of several log paths is non-.log" {
    run fire "cmd | tee /tmp/claude/log/a.log /tmp/claude/log/b.txt"
    [ "$status" -eq 2 ]
}

# -- allowed: .log files ------------------------------------------------

@test "allows .log via tee" {
    run fire "cmd 2>&1 | tee /tmp/claude/log/foo.log | tail -50"
    [ "$status" -eq 0 ]
}

@test "allows .log via redirect" {
    run fire "cmd > /tmp/claude/log/foo.log 2>&1"
    [ "$status" -eq 0 ]
}

@test "allows quoted .log path" {
    run fire "cmd | tee '/tmp/claude/log/foo.log'"
    [ "$status" -eq 0 ]
}

@test "allows .log with trailing semicolon" {
    run fire "cmd > /tmp/claude/log/foo.log;"
    [ "$status" -eq 0 ]
}

@test "allows multiple .log files" {
    run fire "cmd | tee /tmp/claude/log/a.log /tmp/claude/log/b.log"
    [ "$status" -eq 0 ]
}

@test "allows reading an existing .log" {
    run fire "tail /tmp/claude/log/foo.log"
    [ "$status" -eq 0 ]
}

# -- allowed: the dir itself --------------------------------------------

@test "allows mkdir of the log dir" {
    run fire "mkdir -p /tmp/claude/log"
    [ "$status" -eq 0 ]
}

@test "allows the log dir with trailing slash" {
    run fire "mkdir -p /tmp/claude/log/"
    [ "$status" -eq 0 ]
}

@test "allows ls of the log dir" {
    run fire "ls /tmp/claude/log/"
    [ "$status" -eq 0 ]
}

# -- allowed: nothing under the log dir ---------------------------------

@test "allows non-log-dir paths" {
    run fire "cmd > /tmp/other/foo.txt"
    [ "$status" -eq 0 ]
}

@test "allows /var/log paths" {
    run fire "cmd > /var/log/foo.txt"
    [ "$status" -eq 0 ]
}

@test "allows plain command" {
    run fire "ls -la"
    [ "$status" -eq 0 ]
}

# -- regex engine cascade: same verdict under rg / grep / awk -----------

@test "rg engine: blocks .txt, allows .log" {
    RE_ENGINE=rg run fire "cmd > /tmp/claude/log/foo.txt"
    [ "$status" -eq 2 ]
    RE_ENGINE=rg run fire "cmd > /tmp/claude/log/foo.log"
    [ "$status" -eq 0 ]
}

@test "grep engine: blocks .txt, allows .log" {
    RE_ENGINE=grep run fire "cmd > /tmp/claude/log/foo.txt"
    [ "$status" -eq 2 ]
    RE_ENGINE=grep run fire "cmd > /tmp/claude/log/foo.log"
    [ "$status" -eq 0 ]
}

@test "awk engine: blocks .txt, allows .log" {
    RE_ENGINE=awk run fire "cmd > /tmp/claude/log/foo.txt"
    [ "$status" -eq 2 ]
    RE_ENGINE=awk run fire "cmd > /tmp/claude/log/foo.log"
    [ "$status" -eq 0 ]
}

@test "awk engine: blocks second of two log paths" {
    RE_ENGINE=awk run fire "cmd | tee /tmp/claude/log/a.log /tmp/claude/log/b.txt"
    [ "$status" -eq 2 ]
}
