#!/usr/bin/env bats
# contract tests for Copilot safety and context adapters.

setup() {
    REPO="$BATS_TEST_DIRNAME/../.."
    CONFIG_HOME="$BATS_TEST_TMPDIR/config"
    STATE_DIR="$BATS_TEST_TMPDIR/state"
    EVALUATOR="$REPO/stow/common/agent-hooks/.config/agent-hooks/evaluate.sh"
    SAFETY="$REPO/stow/common/copilot/.copilot/hooks/pre-tool-use.js"
    CONTEXT="$REPO/stow/common/copilot/.copilot/hooks/context.js"

    mkdir -p "$CONFIG_HOME" "$STATE_DIR"
    ln -s "$REPO/stow/common/agent-hooks/.config/agent-hooks" "$CONFIG_HOME/agent-hooks"
    ln -s "$REPO/stow/common/agent-modes/.config/agent-modes" "$CONFIG_HOME/agent-modes"
    ln -s "$REPO/stow/common/agent-skills/.config/agent-skills" "$CONFIG_HOME/agent-skills"
    ln -s "$REPO/stow/common/agent-styles/.config/agent-styles" "$CONFIG_HOME/agent-styles"
}

fire_tool() {
    local tool="$1"
    local args="$2"
    jq -cn --arg tool "$tool" --argjson args "$args" \
        '{toolName: $tool, toolArgs: $args}' |
        env XDG_CONFIG_HOME="$CONFIG_HOME" \
            AGENT_HOOK_EVALUATOR="$EVALUATOR" \
            node "$SAFETY"
}

fire_raw_tool() {
    local tool="$1"
    local args="$2"
    jq -cn --arg tool "$tool" --arg args "$args" \
        '{toolName: $tool, toolArgs: $args}' |
        env XDG_CONFIG_HOME="$CONFIG_HOME" \
            AGENT_HOOK_EVALUATOR="$EVALUATOR" \
            node "$SAFETY"
}

@test "Copilot adapter allows safe shell requests" {
    run fire_tool bash '{"command":"git status"}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "Copilot adapter emits a native JSON denial" {
    run fire_tool bash '{"command":"git push origin main"}'
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r '.permissionDecision')" = "deny" ]
    [[ "$(printf '%s' "$output" | jq -r '.permissionDecisionReason')" == BLOCKED:* ]]
}

@test "Copilot adapter parses JSON-string shell arguments" {
    run fire_raw_tool bash '{"command":"brew install jq"}'
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r '.permissionDecision')" = "deny" ]
}

@test "Copilot adapter normalizes direct and patch write paths" {
    run fire_tool create '{"path":"/tmp/note.md","content":"x"}'
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r '.permissionDecision')" = "deny" ]

    run fire_raw_tool apply_patch $'*** Begin Patch\n*** Add File: /tmp/ai/note.md\n+x\n*** End Patch'
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    run fire_raw_tool apply_patch $'*** Begin Patch\n*** Add File: /tmp/note.md\n+x\n*** End Patch'
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r '.permissionDecision')" = "deny" ]
}

@test "Copilot adapter fails closed on malformed writes and evaluator errors" {
    run fire_tool create '{"content":"x"}'
    [ "$status" -eq 0 ]
    [[ "$(printf '%s' "$output" | jq -r '.permissionDecisionReason')" == *"cannot inspect"* ]]

    run bash -c 'printf %s "$1" | env AGENT_HOOK_EVALUATOR=/usr/bin/false node "$2"' \
        _ '{"toolName":"bash","toolArgs":{"command":"git status"}}' "$SAFETY"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Copilot safety adapter failed"* ]]
}

@test "session start injects lofi and configured modes as JSON context" {
    run env XDG_CONFIG_HOME="$CONFIG_HOME" AGENT_STATE_DIR="$STATE_DIR" \
        node "$CONTEXT" session-start <<<'{"source":"startup"}'
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r '.additionalContext' | grep -c 'lofi -- personal writing style')" -eq 1 ]
    [ "$(printf '%s' "$output" | jq -r '.additionalContext' | grep -c 'CAVEMAN MODE ACTIVE -- level: full')" -eq 1 ]
    [ "$(printf '%s' "$output" | jq -r '.additionalContext' | grep -c 'PONYTAIL MODE ACTIVE')" -eq 0 ]
    [ "$(cat "$STATE_DIR/caveman-active")" = "full" ]
    [ ! -e "$STATE_DIR/ponytail-active" ]
}

@test "session start honors the shared lofi marker" {
    touch "$STATE_DIR/lofi-off"
    run env XDG_CONFIG_HOME="$CONFIG_HOME" AGENT_STATE_DIR="$STATE_DIR" \
        node "$CONTEXT" session-start <<<'{"source":"startup"}'
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r '.additionalContext' | grep -c 'lofi -- personal writing style')" -eq 0 ]
}

@test "prompt tracking updates shared mode state without hook output" {
    run env XDG_CONFIG_HOME="$CONFIG_HOME" AGENT_STATE_DIR="$STATE_DIR" \
        node "$CONTEXT" prompt <<<'{"prompt":"/caveman ultra"}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(cat "$STATE_DIR/caveman-active")" = "ultra" ]

    run env XDG_CONFIG_HOME="$CONFIG_HOME" AGENT_STATE_DIR="$STATE_DIR" \
        node "$CONTEXT" prompt <<<'{"prompt":"/ponytail full"}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(cat "$STATE_DIR/ponytail-active")" = "full" ]

    run env XDG_CONFIG_HOME="$CONFIG_HOME" AGENT_STATE_DIR="$STATE_DIR" \
        node "$CONTEXT" prompt <<<'{"prompt":"normal mode"}'
    [ "$status" -eq 0 ]
    [ ! -e "$STATE_DIR/caveman-active" ]
    [ ! -e "$STATE_DIR/ponytail-active" ]
}

@test "caveman independent commands are tracked" {
    run env XDG_CONFIG_HOME="$CONFIG_HOME" AGENT_STATE_DIR="$STATE_DIR" \
        node "$CONTEXT" prompt <<<'{"prompt":"/caveman-commit"}'
    [ "$status" -eq 0 ]
    [ "$(cat "$STATE_DIR/caveman-active")" = "commit" ]
}
