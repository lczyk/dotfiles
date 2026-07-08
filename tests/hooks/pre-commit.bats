#!/usr/bin/env bats
# tests for stow/common/git/.config/git/hooks/pre-commit
# shims `git` on PATH so tests can feed an arbitrary `git diff --cached` output
# w/out building a real repo.

setup() {
    HOOK="$BATS_TEST_DIRNAME/../../stow/common/git/.config/git/hooks/pre-commit"
    SHIMDIR="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$SHIMDIR"
    export PATH="$SHIMDIR:$PATH"
    export CLAUDECODE=1
}

# write a fake `git` shim that prints $1 verbatim for `git diff --cached`
fake_diff() {
    local out="$BATS_TEST_TMPDIR/diff.out"
    printf '%s' "$1" > "$out"
    cat > "$SHIMDIR/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "diff" ] && [ "\$2" = "--cached" ]; then
    cat "$out"
    exit 0
fi
exit 0
EOF
    chmod +x "$SHIMDIR/git"
}

@test "passes when diff is empty" {
    fake_diff ""
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "passes on pure ASCII added line" {
    fake_diff $'+hello world\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "rejects em-dash in added line under CLAUDECODE" {
    fake_diff $'+hello \xe2\x80\x94 world\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects smart quote in added line" {
    fake_diff $'+say \xe2\x80\x9chi\xe2\x80\x9d\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects emoji in added line" {
    fake_diff $'+rocket \xf0\x9f\x9a\x80\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "ignores non-ASCII on context lines (only flags + additions)" {
    fake_diff $' old \xe2\x80\x94 line\n+new clean line\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "ignores non-ASCII on removed lines" {
    fake_diff $'-removed \xe2\x80\x94 line\n+new clean line\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "ignores ++ header lines" {
    fake_diff $'+++ b/file\xe2\x80\x94name\n+ascii content\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "non-claude run warns but exits 0" {
    unset CLAUDECODE
    fake_diff $'+hello \xe2\x80\x94 world\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

# -- nocommit checks (always block, regardless of CLAUDECODE) --

@test "rejects lowercase nocommit in added line" {
    fake_diff $'+print("debug") // nocommit\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects uppercase NOCOMMIT in added line" {
    fake_diff $'+NOCOMMIT: temporary debug dump\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects mixed-case NoCommit in added line" {
    fake_diff $'+// NoCommit remove this\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "ignores nocommit on context lines" {
    fake_diff $' old line // nocommit\n+new clean line\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "ignores nocommit on removed lines" {
    fake_diff $'-removed line // nocommit\n+new clean line\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "rejects nocommit even in non-claude mode" {
    unset CLAUDECODE
    fake_diff $'+debug print // nocommit\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

# -- trailing whitespace --

@test "rejects trailing space on added line" {
    fake_diff $'+hello   \n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects trailing tab on added line" {
    fake_diff $'+hello\t\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "ignores trailing whitespace on context lines" {
    fake_diff $' old line   \n+clean\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

# -- secret scan --

@test "rejects AWS AKIA key" {
    fake_diff $'+aws_key = "AKIAIOSFODNN7EXAMPLE"\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects GitHub PAT (ghp_)" {
    fake_diff $'+token = ghp_abcdefghijklmnopqrstuvwxyz0123456789\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects OpenAI sk- key" {
    fake_diff $'+OPENAI=sk-abcdefghijklmnopqrstuvwxyz0123\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects Anthropic sk-ant- key" {
    fake_diff $'+ANTHROPIC=sk-ant-abcdefghijklmnopqrstuvwxyz0123\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects PEM private key header" {
    fake_diff $'+-----BEGIN RSA PRIVATE KEY-----\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects generic password= literal" {
    fake_diff $'+password = "hunter2hunter2"\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "rejects api_key= literal" {
    fake_diff $'+api_key: "abcd1234efgh5678"\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}

@test "ignores empty password assignment" {
    fake_diff $'+password = ""\n'
    run "$HOOK"
    [ "$status" -eq 0 ]
}

@test "secrets blocked even in non-claude mode" {
    unset CLAUDECODE
    fake_diff $'+token = ghp_abcdefghijklmnopqrstuvwxyz0123456789\n'
    run "$HOOK"
    [ "$status" -ne 0 ]
}
