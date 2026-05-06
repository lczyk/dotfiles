#!/usr/bin/env bats
# tests for stow/common/claude/.claude/statusline.sh
# isolates a fake $CLAUDE_CONFIG_DIR per test so we control which badge scripts run.

setup() {
    REPO="$BATS_TEST_DIRNAME/../.."
    DISPATCHER="$REPO/stow/common/claude/.claude/statusline.sh"
    export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
    mkdir -p "$CLAUDE_CONFIG_DIR/statusline.d"
    BD="$CLAUDE_CONFIG_DIR/statusline.d"
}

# write an executable badge that prints $2 (and reads stdin to drain).
make_badge() {
    cat > "$BD/$1" <<EOF
#!/usr/bin/env bash
cat >/dev/null
printf '%s' '$2'
EOF
    chmod +x "$BD/$1"
}

@test "empty badge dir prints nothing" {
    rm -rf "$BD"
    mkdir -p "$BD"
    run bash -c "echo '{}' | '$DISPATCHER'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "single badge output passes through" {
    make_badge "10-a.sh" "ALPHA"
    run bash -c "echo '{}' | '$DISPATCHER'"
    [ "$status" -eq 0 ]
    [ "$output" = "ALPHA" ]
}

@test "joins multiple badges with single space" {
    make_badge "10-a.sh" "ALPHA"
    make_badge "20-b.sh" "BETA"
    run bash -c "echo '{}' | '$DISPATCHER'"
    [ "$output" = "ALPHA BETA" ]
}

@test "skips badges that print nothing" {
    make_badge "10-a.sh" "ALPHA"
    make_badge "15-silent.sh" ""
    make_badge "20-b.sh" "BETA"
    run bash -c "echo '{}' | '$DISPATCHER'"
    [ "$output" = "ALPHA BETA" ]
}

@test "skips non-executable files" {
    make_badge "10-a.sh" "ALPHA"
    cat > "$BD/15-noexec.sh" <<'EOF'
#!/usr/bin/env bash
printf 'NOPE'
EOF
    run bash -c "echo '{}' | '$DISPATCHER'"
    [ "$output" = "ALPHA" ]
}

@test "runs in lex order" {
    make_badge "30-c.sh" "C"
    make_badge "10-a.sh" "A"
    make_badge "20-b.sh" "B"
    run bash -c "echo '{}' | '$DISPATCHER'"
    [ "$output" = "A B C" ]
}

@test "missing badge dir is silent no-op" {
    rm -rf "$BD"
    run bash -c "echo '{}' | '$DISPATCHER'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "stdin payload is piped to each badge" {
    cat > "$BD/10-echo.sh" <<'EOF'
#!/usr/bin/env bash
read -r line
printf 'got=%s' "$line"
EOF
    chmod +x "$BD/10-echo.sh"
    run bash -c "echo 'hello' | '$DISPATCHER'"
    [ "$output" = "got=hello" ]
}

@test "badge stderr is discarded" {
    cat > "$BD/10-noisy.sh" <<'EOF'
#!/usr/bin/env bash
echo "error stuff" >&2
printf 'OK'
EOF
    chmod +x "$BD/10-noisy.sh"
    run bash -c "echo '{}' | '$DISPATCHER' 2>/dev/null"
    [ "$output" = "OK" ]
}
