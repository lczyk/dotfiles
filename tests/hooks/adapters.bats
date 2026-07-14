#!/usr/bin/env bats
# contract tests for Claude- and Codex-shaped safety adapters.

setup() {
    REPO="$BATS_TEST_DIRNAME/../.."
    EVALUATOR="$REPO/stow/common/agent-hooks/.config/agent-hooks/evaluate.sh"
    CLAUDE="$REPO/stow/common/claude/.claude/hooks/safety-adapter.sh"
    CODEX="$REPO/stow/common/codex/.codex/hooks/safety-adapter.sh"
}

fire_shell() {
    local adapter="$1"
    local command="$2"
    printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$command" | jq -Rs .)" |
        env AGENT_HOOK_EVALUATOR="$EVALUATOR" bash "$adapter" shell
}

fire_claude_write() {
    local path="$1"
    printf '{"tool_input":{"file_path":%s}}' "$(printf '%s' "$path" | jq -Rs .)" |
        env AGENT_HOOK_EVALUATOR="$EVALUATOR" bash "$CLAUDE" write
}

fire_codex_patch() {
    local patch="$1"
    printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$patch" | jq -Rs .)" |
        env AGENT_HOOK_EVALUATOR="$EVALUATOR" bash "$CODEX" patch
}

@test "Claude adapter allows safe shell commands" {
    run fire_shell "$CLAUDE" "git status"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "Claude adapter translates policy denial to exit 2" {
    run fire_shell "$CLAUDE" "git push origin main"
    [ "$status" -eq 2 ]
    [[ "$output" == BLOCKED:* ]]
}

@test "Claude adapter normalizes direct write paths" {
    run fire_claude_write "/tmp/note.md"
    [ "$status" -eq 2 ]

    run fire_claude_write "/tmp/ai/note.md"
    [ "$status" -eq 0 ]
}

@test "Claude adapter fails closed on unknown write payloads" {
    run env AGENT_HOOK_EVALUATOR="$EVALUATOR" bash "$CLAUDE" write <<<'{"tool_input":{}}'
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot inspect Claude write destinations"* ]]
}

@test "Codex adapter extracts patch write paths" {
    run fire_codex_patch $'*** Begin Patch\n*** Add File: /tmp/note.md\n+text\n*** End Patch'
    [ "$status" -eq 2 ]

    run fire_codex_patch $'*** Begin Patch\n*** Add File: /tmp/ai/note.md\n+text\n*** End Patch'
    [ "$status" -eq 0 ]
}

@test "Codex adapter permits delete-only patches" {
    run fire_codex_patch $'*** Begin Patch\n*** Delete File: /tmp/stray.md\n*** End Patch'
    [ "$status" -eq 0 ]
}

@test "adapters fail closed when the evaluator fails" {
    run bash -c 'printf %s "$1" | env AGENT_HOOK_EVALUATOR=/usr/bin/false bash "$2" shell' \
        _ '{"tool_input":{"command":"git status"}}' "$CLAUDE"
    [ "$status" -eq 2 ]
    [[ "$output" == *"safety evaluator failed"* ]]
}
