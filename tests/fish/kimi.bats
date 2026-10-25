#!/usr/bin/env bats
# tests for stow/common/fish/.config/fish/conf.d/10_kimi.fish

setup() {
    CONF="$BATS_TEST_DIRNAME/../../stow/common/fish/.config/fish/conf.d/10_kimi.fish"
    FISH=$(command -v fish)
    BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$BIN"
    cat > "$BIN/kimi" <<'EOF'
#!/usr/bin/env bash
printf 'AGENT_SESSION=%s\n' "$AGENT_SESSION"
printf 'argv=%s\n' "$*"
EOF
    chmod +x "$BIN/kimi"
}

@test "kimi alias marks the agent session and forwards arguments" {
    run env HOME="$BATS_TEST_TMPDIR/home" PATH="$BIN:/usr/bin:/bin" "$FISH" --no-config --command \
        "source $CONF; kimi --prompt 'hello world'"
    [ "$status" -eq 0 ]
    [ "$output" = $'AGENT_SESSION=1\nargv=--prompt hello world' ]
}

@test "kimi config adds the default install directory to PATH" {
    run env HOME="$BATS_TEST_TMPDIR/home" PATH="/usr/bin:/bin" "$FISH" --no-config --command \
        "mkdir -p \$HOME/.kimi-code/bin; cp $BIN/kimi \$HOME/.kimi-code/bin/kimi; source $CONF; kimi --version"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AGENT_SESSION=1"* ]]
    [[ "$output" == *"argv=--version"* ]]
}
