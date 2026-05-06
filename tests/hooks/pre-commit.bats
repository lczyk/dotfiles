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
