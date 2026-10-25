#!/usr/bin/env bats
# contract tests for Kimi's caveman and lofi context hooks.

setup() {
    REPO="$BATS_TEST_DIRNAME/../.."
    HOOKS="$REPO/stow/common/kimi-code/.kimi-code/hooks"
    ACTIVATE="$HOOKS/caveman-activate.js"
    TRACKER="$HOOKS/caveman-mode-tracker.js"
    CONFIG="$REPO/stow/common/kimi-code/.kimi-code/config.toml"

    export AGENT_STATE_DIR="$BATS_TEST_TMPDIR/state"
    export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
    unset CAVEMAN_DEFAULT_MODE
    mkdir -p "$AGENT_STATE_DIR" "$XDG_CONFIG_HOME"
    ln -s "$REPO/stow/common/agent-skills/.config/agent-skills" "$XDG_CONFIG_HOME/agent-skills"
    ln -s "$REPO/stow/common/agent-styles/.config/agent-styles" "$XDG_CONFIG_HOME/agent-styles"
    FLAG="$AGENT_STATE_DIR/caveman-active"
}

fire() {
    jq -cn --arg prompt "$1" '{prompt: $prompt}' | node "$TRACKER"
}

activate() {
    jq -cn --arg source "$1" '{source: $source}' | node "$ACTIVATE"
}

flag() {
    cat "$FLAG" 2>/dev/null || echo "(none)"
}

lofi_hook() {
    local file="$1"
    bash -c 'if [ ! -f "${XDG_CONFIG_HOME:-$HOME/.config}/agent-state/lofi-off" ]; then cat "${XDG_CONFIG_HOME:-$HOME/.config}/agent-styles/'"$file"'"; fi'
}

@test "startup emits plain filtered caveman rules and seeds the default" {
    run activate startup
    [ "$status" -eq 0 ]
    [[ "$output" == *"caveman mode active -- level: full"* ]]
    [[ "$output" == *"drop articles, fragments ok"* ]]
    [[ "$output" != *"abbreviate prose words"* ]]
    [[ "$output" != \{* ]]
    [ "$(flag)" = "full" ]
}

@test "resume preserves a selected mode and clear preserves deactivation" {
    activate startup >/dev/null
    fire "/skill:caveman ultra" >/dev/null
    run activate resume
    [[ "$output" == *"level: ultra"* ]]
    [ "$(flag)" = "ultra" ]

    fire "/skill:caveman off" >/dev/null
    run activate clear
    [ -z "$output" ]
    [ "$(flag)" = "(none)" ]
}

@test "configured default and off mode are honoured" {
    CAVEMAN_DEFAULT_MODE=lite activate startup >/dev/null
    [ "$(flag)" = "lite" ]
    CAVEMAN_DEFAULT_MODE=off activate startup >/dev/null
    [ "$(flag)" = "(none)" ]
}

@test "Kimi skill commands toggle caveman and emit plain reinforcement" {
    run fire "/skill:caveman ultra"
    [ "$status" -eq 0 ]
    [ "$(flag)" = "ultra" ]
    [[ "$output" == "caveman mode active (ultra)."* ]]
    [[ "$output" != \{* ]]

    fire "/skill:caveman sideways" >/dev/null
    [ "$(flag)" = "ultra" ]
    fire "/skill:caveman off" >/dev/null
    [ "$(flag)" = "(none)" ]
}

@test "Kimi content-part payloads toggle caveman" {
    run bash -c 'jq -cn '\''{prompt: [{type: "text", text: "/skill:caveman ultra"}]}'\'' | node "$1"' _ "$TRACKER"
    [ "$status" -eq 0 ]
    [ "$(flag)" = "ultra" ]
    [[ "$output" == "caveman mode active (ultra)."* ]]
}

@test "bare skill command uses the configured default" {
    export CAVEMAN_DEFAULT_MODE=lite
    fire "/skill:caveman" >/dev/null
    [ "$(flag)" = "lite" ]
}

@test "deactivation is strict and scheduled tasks stay untouched" {
    fire "/skill:caveman full" >/dev/null
    fire "explain why stop caveman clears the mode" >/dev/null
    [ "$(flag)" = "full" ]
    fire "stop caveman" >/dev/null
    [ "$(flag)" = "(none)" ]

    fire "/skill:caveman ultra" >/dev/null
    run fire '<scheduled-task id="1">check deploy</scheduled-task>'
    [ -z "$output" ]
    [ "$(flag)" = "ultra" ]
}

@test "independent commit mode is tracked without per-turn reinforcement" {
    run fire "/skill:caveman-commit"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(flag)" = "commit" ]
}

@test "lofi startup and reminder hooks honour the shared off marker" {
    run lofi_hook lofi.md
    [ "$status" -eq 0 ]
    [[ "$output" == *"lofi -- personal writing style"* ]]
    run lofi_hook lofi-reminder.md
    [[ "$output" == *"lofi on. lowercase everything"* ]]

    mkdir -p "$XDG_CONFIG_HOME/agent-state"
    touch "$XDG_CONFIG_HOME/agent-state/lofi-off"
    run lofi_hook lofi.md
    [ "$status" -eq 0 ]
    [ -z "$(lofi_hook lofi.md)" ]
    run lofi_hook lofi-reminder.md
    [ "$status" -eq 0 ]
    [ -z "$(lofi_hook lofi-reminder.md)" ]
}

@test "Kimi config wires native startup and prompt hooks" {
    run python3 - "$CONFIG" <<'PY'
import sys
import tomllib
with open(sys.argv[1], "rb") as file:
    config = tomllib.load(file)
hooks = config["hooks"]
assert [hook["event"] for hook in hooks] == [
    "SessionStart", "SessionStart", "UserPromptSubmit", "UserPromptSubmit"
]
assert all(hook["timeout"] == 5 for hook in hooks)
assert "caveman-activate.js" in hooks[0]["command"]
assert "agent-styles/lofi.md" in hooks[1]["command"]
assert "caveman-mode-tracker.js" in hooks[2]["command"]
assert "agent-styles/lofi-reminder.md" in hooks[3]["command"]
PY
    [ "$status" -eq 0 ]
}
