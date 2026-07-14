#!/usr/bin/env bats
# tests for stow/common/agent-hooks/.config/agent-hooks/enforce-tmp-ai.sh
# the policy reads harness-neutral shell/write requests and exits 2 to deny
# writes to /tmp outside /tmp/ai/.

setup() {
    HOOK="$BATS_TEST_DIRNAME/../../stow/common/agent-hooks/.config/agent-hooks/enforce-tmp-ai.sh"
}

# fire a neutral shell request.
fire() {
    local cmd="$1"
    printf '{"version":1,"operation":"shell","command":%s}' "$(printf '%s' "$cmd" | jq -Rs .)" \
        | "$HOOK"
}

# fire a neutral write request with one destination path.
fire_write() {
    local path="$1"
    printf '{"version":1,"operation":"write","write_paths":[%s]}' "$(printf '%s' "$path" | jq -Rs .)" \
        | "$HOOK"
}

# Normalize patch destinations as a harness adapter would, then fire the policy.
fire_patch() {
    local patch="$1"
    local paths

    paths=$(
        printf '%s\n' "$patch" |
            sed -nE \
                -e 's/^\*\*\* (Add|Update) File: (.*)$/\2/p' \
                -e 's/^\*\*\* Move to: (.*)$/\1/p' |
            jq -Rsc 'split("\n") | map(select(length > 0))'
    )
    printf '{"version":1,"operation":"write","write_paths":%s}' "$paths" | "$HOOK"
}

# -- Bash: blocked redirects outside /tmp/ai ------------------------

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

# -- Bash: allowed under /tmp/ai ------------------------------------

@test "allows > redirect under /tmp/ai" {
    run fire "cmd > /tmp/ai/foo.sh"
    [ "$status" -eq 0 ]
}

@test "allows tee under /tmp/ai/log" {
    run fire "cmd 2>&1 | tee /tmp/ai/log/x.log | tail -5"
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

# -- Bash: mktemp must target /tmp/ai -------------------------------

@test "blocks bare mktemp" {
    run fire "f=\$(mktemp)"
    [ "$status" -eq 2 ]
}

@test "blocks mktemp -p /tmp (not claude)" {
    run fire "mktemp -p /tmp"
    [ "$status" -eq 2 ]
}

@test "allows mktemp -p /tmp/ai" {
    run fire "f=\$(mktemp -p /tmp/ai)"
    [ "$status" -eq 0 ]
}

@test "allows mktemp --tmpdir=/tmp/ai" {
    run fire "mktemp --tmpdir=/tmp/ai scratch.XXXX"
    [ "$status" -eq 0 ]
}

# -- Write / Edit / NotebookEdit: file_path -----------------------------

@test "blocks Write to /tmp" {
    run fire_write "/tmp/note.md"
    [ "$status" -eq 2 ]
}

@test "allows Write under /tmp/ai" {
    run fire_write "/tmp/ai/note.md"
    [ "$status" -eq 0 ]
}

@test "allows Write to the project tree" {
    run fire_write "/Users/marcin/dotfiles/foo.txt"
    [ "$status" -eq 0 ]
}

@test "allows Write to /tmp/ai exactly (no trailing slash)" {
    run fire_write "/tmp/ai"
    [ "$status" -eq 0 ]
}

# -- prefix trap: /tmp/aiette is NOT under /tmp/ai ---------------

@test "blocks Write to /tmp/aiette (prefix lookalike)" {
    run fire_write "/tmp/aiette/foo"
    [ "$status" -eq 2 ]
}

# -- Patch: paths come from patch headers -----------------------------------

@test "blocks patch Add File under /tmp" {
    run fire_patch $'*** Begin Patch\n*** Add File: /tmp/note.md\n+text\n*** End Patch'
    [ "$status" -eq 2 ]
}

@test "blocks patch Update File under /private/tmp" {
    run fire_patch $'*** Begin Patch\n*** Update File: /private/tmp/note.md\n@@\n-old\n+new\n*** End Patch'
    [ "$status" -eq 2 ]
}

@test "allows patch Delete File under /tmp" {
    # deletes aren't scratch creation -- same stance as reads
    run fire_patch $'*** Begin Patch\n*** Delete File: /tmp/stray.md\n*** End Patch'
    [ "$status" -eq 0 ]
}

@test "blocks patch Move to under /tmp" {
    run fire_patch $'*** Begin Patch\n*** Update File: note.md\n*** Move to: /tmp/note.md\n*** End Patch'
    [ "$status" -eq 2 ]
}

@test "allows patch paths under /tmp/ai" {
    run fire_patch $'*** Begin Patch\n*** Add File: /tmp/ai/note.md\n+text\n*** End Patch'
    [ "$status" -eq 0 ]
}

@test "allows patch paths in the project tree" {
    run fire_patch $'*** Begin Patch\n*** Update File: src/main.rs\n@@\n-old\n+new\n*** End Patch'
    [ "$status" -eq 0 ]
}

@test "patch mode ignores shell-looking text in file contents" {
    run fire_patch $'*** Begin Patch\n*** Update File: README.md\n@@\n-old\n+cmd > /tmp/not-a-write-by-the-hook.md\n*** End Patch'
    [ "$status" -eq 0 ]
}

# -- regex engine cascade: same verdict under rg / grep / awk -----------

@test "rg engine: blocks /tmp redirect, allows /tmp/ai" {
    RE_ENGINE=rg run fire "cmd > /tmp/foo"
    [ "$status" -eq 2 ]
    RE_ENGINE=rg run fire "cmd > /tmp/ai/foo"
    [ "$status" -eq 0 ]
}

@test "grep engine: blocks /tmp redirect, allows /tmp/ai" {
    RE_ENGINE=grep run fire "cmd > /tmp/foo"
    [ "$status" -eq 2 ]
    RE_ENGINE=grep run fire "cmd > /tmp/ai/foo"
    [ "$status" -eq 0 ]
}

@test "awk engine: blocks /tmp redirect, allows /tmp/ai" {
    RE_ENGINE=awk run fire "cmd > /tmp/foo"
    [ "$status" -eq 2 ]
    RE_ENGINE=awk run fire "cmd > /tmp/ai/foo"
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
