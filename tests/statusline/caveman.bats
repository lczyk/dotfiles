#!/usr/bin/env bats
# tests for stow/common/claude/.claude/statusline.d/10-caveman.sh

setup() {
    BADGE="$BATS_TEST_DIRNAME/../../stow/common/claude/.claude/statusline.d/10-caveman.sh"
    export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
    mkdir -p "$CLAUDE_CONFIG_DIR/plugins/cache/caveman/caveman"
}

# create a caveman-statusline.sh under hash $1, contents print $2, with mtime offset $3 seconds ago
plant() {
    local hash="$1" out="$2" age="$3"
    local dir="$CLAUDE_CONFIG_DIR/plugins/cache/caveman/caveman/$hash/hooks"
    mkdir -p "$dir"
    local script="$dir/caveman-statusline.sh"
    cat > "$script" <<EOF
#!/usr/bin/env bash
printf '%s' '$out'
EOF
    chmod +x "$script"
    touch -d "@$(($(date +%s) - age))" "$script"
}

@test "silent when no caveman cache exists" {
    rm -rf "$CLAUDE_CONFIG_DIR/plugins"
    run bash -c "echo '{}' | '$BADGE'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "silent when CLAUDE_CONFIG_DIR is unset and no fallback" {
    unset CLAUDE_CONFIG_DIR
    HOME="$BATS_TEST_TMPDIR/nohome" run bash -c "echo '{}' | '$BADGE'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

@test "renders [C] when caveman is active" {
    plant "abc123" "CAVEMAN-OUT" 100
    run bash -c "echo '{}' | '$BADGE'"
    [ "$status" -eq 0 ]
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[C]" ]
}

@test "silent when newest script outputs nothing" {
    plant "abc123" "" 100
    run bash -c "echo '{}' | '$BADGE'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "picks newest by mtime when multiple installed" {
    plant "old" "" 1000
    plant "new" "ACTIVE" 10
    plant "mid" "" 500
    run bash -c "echo '{}' | '$BADGE'"
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[C]" ]
}

@test "newest empty wins -> silent" {
    plant "old" "ACTIVE" 1000
    plant "new" "" 10
    run bash -c "echo '{}' | '$BADGE'"
    [ -z "$output" ]
}
