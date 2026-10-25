#!/usr/bin/env bats
# contract tests for Claude-, Codex- and Kimi-shaped safety adapters.

setup() {
    # a capability from the launching session would mask protect-hooks
    unset AGENT_UNFENCE
    REPO="$BATS_TEST_DIRNAME/../.."
    EVALUATOR="$REPO/stow/common/agent-hooks/.config/agent-hooks/evaluate.sh"
    CLAUDE="$REPO/stow/common/claude/.claude/hooks/safety-adapter.sh"
    CODEX="$REPO/stow/common/codex/.codex/hooks/safety-adapter.sh"
    KIMI="$REPO/stow/common/kimi-code/.kimi-code/hooks/safety-adapter.sh"
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

fire_kimi_write() {
    local path="$1"
    printf '{"tool_input":{"path":%s}}' "$(printf '%s' "$path" | jq -Rs .)" |
        env AGENT_HOOK_EVALUATOR="$EVALUATOR" bash "$KIMI" write
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

@test "Kimi adapter allows safe shell commands" {
    run fire_shell "$KIMI" "git status"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "Kimi adapter translates policy denial to exit 2" {
    run fire_shell "$KIMI" "git push origin main"
    [ "$status" -eq 2 ]
    [[ "$output" == BLOCKED:* ]]
}

@test "Kimi adapter normalizes native write paths" {
    run fire_kimi_write "/tmp/note.md"
    [ "$status" -eq 2 ]

    run fire_kimi_write "/tmp/ai/note.md"
    [ "$status" -eq 0 ]

    run fire_kimi_write "$HOME/.kimi-code/config.toml"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not agent-editable"* ]]
}

@test "Kimi adapter fails closed on unknown write payloads" {
    run env AGENT_HOOK_EVALUATOR="$EVALUATOR" bash "$KIMI" write <<<'{"tool_input":{}}'
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot inspect Kimi write destinations"* ]]
}

@test "Codex adapter extracts patch write paths" {
    run fire_codex_patch $'*** Begin Patch\n*** Add File: /tmp/note.md\n+text\n*** End Patch'
    [ "$status" -eq 2 ]

    run fire_codex_patch $'*** Begin Patch\n*** Add File: /tmp/ai/note.md\n+text\n*** End Patch'
    [ "$status" -eq 0 ]
}

@test "Codex adapter judges deleted paths like any other write" {
    run fire_codex_patch $'*** Begin Patch\n*** Delete File: /tmp/ai/stray.md\n*** End Patch'
    [ "$status" -eq 0 ]

    run fire_codex_patch $'*** Begin Patch\n*** Delete File: /tmp/stray.md\n*** End Patch'
    [ "$status" -eq 2 ]
}

@test "Codex adapter refuses to delete a protected hook" {
    run fire_codex_patch "*** Begin Patch"$'\n'"*** Delete File: $HOME/.claude/hooks/safety-adapter.sh"$'\n'"*** End Patch"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not agent-editable"* ]]
}

@test "Codex adapter checks the deletes in a mixed patch" {
    run fire_codex_patch "*** Begin Patch"$'\n'"*** Update File: /tmp/ai/note.md"$'\n'"+x"$'\n'"*** Delete File: $HOME/.config/agent-hooks/evaluate.sh"$'\n'"*** End Patch"
    [ "$status" -eq 2 ]
}

@test "Codex adapter reads the old side of a unified diff" {
    run fire_codex_patch $'--- a/.claude/settings.json\n+++ /dev/null\n@@ -1 +0,0 @@\n-{}'
    [ "$status" -eq 2 ]

    run fire_codex_patch $'--- a/.claude/settings.json\n+++ b/notes.md\n@@ -1 +1 @@\n-{}\n+x'
    [ "$status" -eq 2 ]
}

@test "Codex adapter fails closed on a patch with no paths" {
    run fire_codex_patch $'*** Begin Patch\n*** End Patch'
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot inspect Codex patch destinations"* ]]
}

@test "Codex adapter catches a CRLF delete of an exact-match config" {
    run fire_codex_patch "*** Begin Patch"$'\r\n'"*** Delete File: $HOME/.codex/hooks.json"$'\r\n'"*** End Patch"
    [ "$status" -eq 2 ]
}

@test "Codex adapter catches a protected rename beside a benign hunk" {
    run fire_codex_patch $'diff --git a/keep.md b/keep.md\n--- a/keep.md\n+++ b/keep.md\n@@ -1 +1 @@\n-a\n+b\ndiff --git a/.claude/settings.json b/x/settings.json\nsimilarity index 100%\nrename from .claude/settings.json\nrename to x/settings.json'
    [ "$status" -eq 2 ]
}

@test "adapters fail closed when the evaluator fails" {
    for adapter in "$CLAUDE" "$CODEX" "$KIMI"; do
        run bash -c 'printf %s "$1" | env AGENT_HOOK_EVALUATOR=/usr/bin/false bash "$2" shell' \
            _ '{"tool_input":{"command":"git status"}}' "$adapter"
        [ "$status" -eq 2 ]
        [[ "$output" == *"safety evaluator failed"* ]]
    done
}

@test "adapters return hints without permission overrides" {
    for adapter in "$CLAUDE" "$CODEX"; do
        run fire_shell "$adapter" "cmd | tail"
        [ "$status" -eq 0 ]
        [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')" == HINT:* ]]
        [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "null" ]
    done
}

@test "Kimi adapter returns plain-text hints" {
    run fire_shell "$KIMI" "cmd | tail"
    [ "$status" -eq 0 ]
    [[ "$output" == HINT:* ]]
    [[ "$output" != \{* ]]
}

@test "Codex adapter catches quoted, copy and new-file protected patches" {
    for patch in $'diff --git a/keep.md b/keep.md\n--- a/keep.md\n+++ b/keep.md\n@@ -1 +1 @@\n-a\n+b\ndiff --git "a/.claude/settings.json" "b/x"\nsimilarity index 100%\nrename from ".claude/settings.json"\nrename to x' $'diff --git a/keep.md b/keep.md\n--- a/keep.md\n+++ b/keep.md\n@@ -1 +1 @@\n-a\n+b\n--- "a/.claude/settings.json"\n+++ "b/.claude/settings.json"\n@@ -1 +1 @@\n-{"a":1}\n+{"a":2}' $'diff --git a/keep.md b/keep.md\n--- a/keep.md\n+++ b/keep.md\n@@ -1 +1 @@\n-a\n+b\ndiff --git a/x b/stow/common/claude/.claude/hooks/evil.sh\nsimilarity index 100%\ncopy from x\ncopy to stow/common/claude/.claude/hooks/evil.sh' $'diff --git a/keep.md b/keep.md\n--- a/keep.md\n+++ b/keep.md\n@@ -1 +1 @@\n-a\n+b\ndiff --git a/stow/common/claude/.claude/hooks/evil.sh b/stow/common/claude/.claude/hooks/evil.sh\nnew file mode 100644\nindex 0000000..e69de29'; do
        run fire_codex_patch "$patch"
        [ "$status" -eq 2 ] || { echo "allowed a protected patch"; false; }
    done
}
