#!/usr/bin/env bats
# tests for stow/common/claude/.claude/statusline.d/25-git-branch.sh

setup() {
    BADGE="$BATS_TEST_DIRNAME/../../stow/common/claude/.claude/statusline.d/25-git-branch.sh"
    REPO="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$REPO"
    cd "$REPO"
    git init -q -b mybranch
    git config core.hooksPath /dev/null
    git config user.email "t@t"
    git config user.name "t"
}

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

@test "prints branch from cwd in payload" {
    run bash -c "echo '{\"cwd\":\"$REPO\"}' | '$BADGE'"
    [ "$status" -eq 0 ]
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[mybranch]" ]
}

@test "falls back to PWD when cwd absent" {
    run bash -c "cd '$REPO' && echo '{}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[mybranch]" ]
}

@test "silent when not in a git repo" {
    run bash -c "echo '{\"cwd\":\"$BATS_TEST_TMPDIR\"}' | '$BADGE'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "strips disallowed branch characters" {
    git -C "$REPO" checkout -q -b "weird\$name"
    run bash -c "echo '{\"cwd\":\"$REPO\"}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[weirdname]" ]
}

@test "caps branch length at 40 chars" {
    long="b/$(printf 'a%.0s' {1..60})"
    git -C "$REPO" checkout -q -b "$long"
    run bash -c "echo '{\"cwd\":\"$REPO\"}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    inside=${out#[}; inside=${inside%]}
    [ "${#inside}" -eq 40 ]
}
