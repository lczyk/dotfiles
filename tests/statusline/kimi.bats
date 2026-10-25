#!/usr/bin/env bats
# tests for stow/common/kimi-code/.kimi-code/statusline.sh and Kimi-only badges

setup() {
    REPO="$BATS_TEST_DIRNAME/../.."
    PACKAGE="$REPO/stow/common/kimi-code/.kimi-code"
    DISPATCHER="$PACKAGE/statusline.sh"
    export KIMI_CODE_HOME="$BATS_TEST_TMPDIR/kimi"
    export AGENT_STATE_DIR="$BATS_TEST_TMPDIR/agent-state"
    mkdir -p "$KIMI_CODE_HOME"
    ln -s "$PACKAGE/statusline.d" "$KIMI_CODE_HOME/statusline.d"
    ln -s "$PACKAGE/statusline-colour.sh" "$KIMI_CODE_HOME/statusline-colour.sh"
    unset AGENT_UNFENCE
    PAYLOAD='{"model":"K3","cwd":"/tmp/project","gitBranch":null,"permissionMode":"auto","planMode":false,"contextUsage":0.12,"contextTokens":32000,"maxContextTokens":262144,"sessionId":"test","version":"2.3.1"}'
}

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }
render() { printf '%s' "$1" | "$DISPATCHER"; }
write_config() { printf '%s' "$1" > "$KIMI_CODE_HOME/config.toml"; }
write_caveman() {
    mkdir -p "$AGENT_STATE_DIR"
    printf '%s' "$1" > "$AGENT_STATE_DIR/caveman-active"
}

@test "normalizes a native Kimi snapshot and orders the badges" {
    run render "$PAYLOAD"
    [ "$status" -eq 0 ]
    out=$(printf '%s' "$output" | strip_ansi)
    [ "$out" = "[x] [x] [u] [K3] [ctx 12%]" ]
}

@test "exact context token counts take precedence over the ratio" {
    run render '{"model":"K3","cwd":"/tmp/project","contextUsage":0.99,"contextTokens":500,"maxContextTokens":1000}'
    [ "$status" -eq 0 ]
    [[ "$(printf '%s' "$output" | strip_ansi)" == *"[ctx 50%]"* ]]
}

@test "contextUsage is converted from a fraction when counts are unusable" {
    run render '{"model":"K3","cwd":"/tmp/project","contextUsage":0.429,"contextTokens":0,"maxContextTokens":0}'
    [ "$status" -eq 0 ]
    [[ "$(printf '%s' "$output" | strip_ansi)" == *"[ctx 42%]"* ]]
}

@test "the shared model badge keeps its aliases" {
    run render '{"model":"Opus 4.7","cwd":"/tmp/project","contextUsage":0}'
    [ "$status" -eq 0 ]
    [[ "$(printf '%s' "$output" | strip_ansi)" == *"[O47]"* ]]
}

@test "empty and invalid input fall back silently" {
    run render ''
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    run render '{not json'
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    run render '{"cwd":"/tmp/project"}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "caveman follows Kimi hook wiring and shared mode state" {
    run render "$PAYLOAD"
    [[ "$(printf '%s' "$output" | strip_ansi)" == "[x]"* ]]

    write_config 'command = "node caveman-activate.js"'
    write_caveman lite
    run render "$PAYLOAD"
    [[ "$(printf '%s' "$output" | strip_ansi)" == "[c]"* ]]

    write_caveman off
    run render "$PAYLOAD"
    [[ "$(printf '%s' "$output" | strip_ansi)" == "[x]"* ]]
}

@test "lofi follows Kimi hook wiring and the shared off marker" {
    write_config 'command = "cat ~/.config/agent-styles/lofi.md"'
    run render "$PAYLOAD"
    [[ "$(printf '%s' "$output" | strip_ansi)" == *"[L]"* ]]

    mkdir -p "$AGENT_STATE_DIR"
    : > "$AGENT_STATE_DIR/lofi-off"
    run render "$PAYLOAD"
    [[ "$(printf '%s' "$output" | strip_ansi)" == *"[x]"* ]]
}

@test "unfence capabilities pass through the shared badge" {
    AGENT_UNFENCE=branch run render "$PAYLOAD"
    [ "$status" -eq 0 ]
    [[ "$(printf '%s' "$output" | strip_ansi)" == *"[U:branch]"* ]]
}
