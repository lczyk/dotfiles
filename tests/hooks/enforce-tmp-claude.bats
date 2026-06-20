#!/usr/bin/env bats
# tests for stow/common/claude/.claude/hooks/enforce-tmp-claude.sh
# the hook reads claude-code's PreToolUse JSON on stdin and exits 2 to block
# any creation of a /tmp file outside /tmp/claude/. two channels: Bash
# (redirects / tee / mktemp) and Write|Edit|NotebookEdit (file_path).

setup() {
    HOOK="$BATS_TEST_DIRNAME/../../stow/common/claude/.claude/hooks/enforce-tmp-claude.sh"
}

# fire a Bash payload. RE_ENGINE (if exported) forces the regex engine.
fire() {
    local cmd="$1"
    printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$cmd" | jq -Rs .)" \
        | "$HOOK"
}

# fire a Write/Edit payload with the given file_path.
fire_write() {
    local path="$1"
    printf '{"tool_input":{"file_path":%s}}' "$(printf '%s' "$path" | jq -Rs .)" \
        | "$HOOK"
}

# -- Bash: blocked redirects outside /tmp/claude ------------------------

@test "blocks > redirect to /tmp" {
    run fire "cmd > /tmp/foo.sh"
    [ "$status" -eq 2 ]
}

@test "blocks >> append to /tmp" {
    run fire "cmd >> /tmp/foo"
    [ "$status" -eq 2 ]
}

@test "blocks glued >/tmp redirect (no space)" {
    run fire "cmd >/tmp/foo.txt"
    [ "$status" -eq 2 ]
}

@test "blocks fd redirect 2>/tmp" {
    run fire "cmd 2>/tmp/err.log"
    [ "$status" -eq 2 ]
}

@test "blocks tee to /tmp" {
    run fire "cmd | tee /tmp/out.txt"
    [ "$status" -eq 2 ]
}

@test "blocks heredoc redirect to /tmp" {
    run fire "cat > /tmp/script.sh <<'EOF'"
    [ "$status" -eq 2 ]
}

# -- Bash: allowed under /tmp/claude ------------------------------------

@test "allows > redirect under /tmp/claude" {
    run fire "cmd > /tmp/claude/foo.sh"
    [ "$status" -eq 0 ]
}

@test "allows tee under /tmp/claude/log" {
    run fire "cmd 2>&1 | tee /tmp/claude/log/x.log | tail -5"
    [ "$status" -eq 0 ]
}

# -- Bash: reads and non-/tmp writes are fine ---------------------------

@test "allows reading an existing /tmp file" {
    run fire "cat /tmp/some-other-tool-output"
    [ "$status" -eq 0 ]
}

@test "allows redirect outside /tmp entirely" {
    run fire "cmd > /var/tmp/foo"
    [ "$status" -eq 0 ]
}

@test "allows plain command" {
    run fire "ls -la /tmp"
    [ "$status" -eq 0 ]
}

# -- Bash: mktemp must target /tmp/claude -------------------------------

@test "blocks bare mktemp" {
    run fire "f=\$(mktemp)"
    [ "$status" -eq 2 ]
}

@test "blocks mktemp -p /tmp (not claude)" {
    run fire "mktemp -p /tmp"
    [ "$status" -eq 2 ]
}

@test "allows mktemp -p /tmp/claude" {
    run fire "f=\$(mktemp -p /tmp/claude)"
    [ "$status" -eq 0 ]
}

@test "allows mktemp --tmpdir=/tmp/claude" {
    run fire "mktemp --tmpdir=/tmp/claude scratch.XXXX"
    [ "$status" -eq 0 ]
}

# -- Write / Edit / NotebookEdit: file_path -----------------------------

@test "blocks Write to /tmp" {
    run fire_write "/tmp/note.md"
    [ "$status" -eq 2 ]
}

@test "allows Write under /tmp/claude" {
    run fire_write "/tmp/claude/note.md"
    [ "$status" -eq 0 ]
}

@test "allows Write to the project tree" {
    run fire_write "/Users/marcin/dotfiles/foo.txt"
    [ "$status" -eq 0 ]
}

@test "allows Write to /tmp/claude exactly (no trailing slash)" {
    run fire_write "/tmp/claude"
    [ "$status" -eq 0 ]
}

# -- prefix trap: /tmp/claudette is NOT under /tmp/claude ---------------

@test "blocks Write to /tmp/claudette (prefix lookalike)" {
    run fire_write "/tmp/claudette/foo"
    [ "$status" -eq 2 ]
}

# -- regex engine cascade: same verdict under rg / grep / awk -----------

@test "rg engine: blocks /tmp redirect, allows /tmp/claude" {
    RE_ENGINE=rg run fire "cmd > /tmp/foo"
    [ "$status" -eq 2 ]
    RE_ENGINE=rg run fire "cmd > /tmp/claude/foo"
    [ "$status" -eq 0 ]
}

@test "grep engine: blocks /tmp redirect, allows /tmp/claude" {
    RE_ENGINE=grep run fire "cmd > /tmp/foo"
    [ "$status" -eq 2 ]
    RE_ENGINE=grep run fire "cmd > /tmp/claude/foo"
    [ "$status" -eq 0 ]
}

@test "awk engine: blocks /tmp redirect, allows /tmp/claude" {
    RE_ENGINE=awk run fire "cmd > /tmp/foo"
    [ "$status" -eq 2 ]
    RE_ENGINE=awk run fire "cmd > /tmp/claude/foo"
    [ "$status" -eq 0 ]
}

# -- known gaps (xfail) -------------------------------------------------
# documented TODOs in the hook -- need real shell parsing. each asserts the
# IDEAL verdict and is skipped; drop the skip once the hook handles it.

@test "xfail: cp dest under /tmp should be blocked" {
    skip "hook only sees redirects/tee/mktemp, not cp/mv/touch dest args"
    run fire "cp foo /tmp/bar"
    [ "$status" -eq 2 ]
}

@test "xfail: cd /tmp then relative touch should be blocked" {
    skip "relative path after cd needs shell-state tracking"
    run fire "cd /tmp; touch scratch"
    [ "$status" -eq 2 ]
}

@test "xfail: literal '> /tmp/x' inside a quoted string should be allowed" {
    skip "hook can't tell a quoted literal from a real redirect -- over-blocks"
    run fire "git commit -m 'writes > /tmp/x'"
    [ "$status" -eq 0 ]
}
