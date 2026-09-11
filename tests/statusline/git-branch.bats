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
    git config commit.gpgsign false
    # seed an initial commit so the index is well-defined
    : > .gitkeep
    git add .gitkeep
    git commit -q -m init
}

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

@test "prints pwd/branch from cwd in payload" {
    run bash -c "echo '{\"cwd\":\"$REPO\"}' | '$BADGE'"
    [ "$status" -eq 0 ]
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[repo/mybranch]" ]
}

@test "falls back to PWD when cwd absent" {
    run bash -c "cd '$REPO' && echo '{}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[repo/mybranch]" ]
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
    [ "$out" = "[repo/weirdname]" ]
}

@test "caps branch length at 40 chars" {
    long="b/$(printf 'a%.0s' {1..60})"
    git -C "$REPO" checkout -q -b "$long"
    run bash -c "echo '{\"cwd\":\"$REPO\"}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    # extract branch portion after "repo/"
    inside=${out#[repo/}; inside=${inside%]}
    [ "${#inside}" -eq 40 ]
}

@test "no dirty marker when worktree clean" {
    run bash -c "echo '{\"cwd\":\"$REPO\"}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[repo/mybranch]" ]
}

@test "shows (N) for unstaged modifications" {
    echo change > "$REPO/.gitkeep"
    echo new > "$REPO/newfile"
    run bash -c "echo '{\"cwd\":\"$REPO\"}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[repo/mybranch(2)]" ]
}

@test "shows (N) for staged changes" {
    echo a > "$REPO/a"
    echo b > "$REPO/b"
    git -C "$REPO" add a b
    run bash -c "echo '{\"cwd\":\"$REPO\"}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[repo/mybranch(2)]" ]
}

@test "counts staged and unstaged together" {
    echo a > "$REPO/a"
    git -C "$REPO" add a
    echo change > "$REPO/.gitkeep"
    run bash -c "echo '{\"cwd\":\"$REPO\"}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[repo/mybranch(2)]" ]
}

@test "counts deleted files" {
    rm "$REPO/.gitkeep"
    run bash -c "echo '{\"cwd\":\"$REPO\"}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[repo/mybranch(1)]" ]
}

@test "shows repo-root-relative path for nested cwd" {
    nested="$REPO/sub"
    mkdir -p "$nested"
    run bash -c "echo '{\"cwd\":\"$nested\"}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[repo/sub/mybranch]" ]
}

# COVER: fish-style abbreviation -- root + leaf full, middles to first char,
# only kicks in when the joined path exceeds 40 chars.
@test "abbreviates middle path components when path is long" {
    deep="$REPO/onedir/twodir/threedir/fourdir/fivedir/leaf"
    mkdir -p "$deep"
    run bash -c "echo '{\"cwd\":\"$deep\"}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[repo/o/t/t/f/f/leaf/mybranch]" ]
}
