#!/usr/bin/env bats
# contract tests for the harness-neutral safety evaluator.

setup() {
    EVALUATOR="$BATS_TEST_DIRNAME/../../stow/common/agent-hooks/.config/agent-hooks/evaluate.sh"
}

fire_shell() {
    local command="$1"
    printf '{"version":1,"operation":"shell","command":%s}' "$(printf '%s' "$command" | jq -Rs .)" |
        "$EVALUATOR"
}

fire_write() {
    local path="$1"
    printf '{"version":1,"operation":"write","write_paths":[%s]}' "$(printf '%s' "$path" | jq -Rs .)" |
        "$EVALUATOR"
}

@test "allows a safe shell request" {
    run fire_shell "git status"
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r '.decision')" = "allow" ]
}

@test "returns a structured shell denial" {
    run fire_shell "git push origin main"
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r '.decision')" = "deny" ]
    [ "$(printf '%s' "$output" | jq -r '.policy')" = "block-dangerous" ]
    [[ "$(printf '%s' "$output" | jq -r '.reason')" == BLOCKED:* ]]
}

@test "returns a structured write denial" {
    run fire_write "/tmp/note.md"
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r '.decision')" = "deny" ]
    [ "$(printf '%s' "$output" | jq -r '.policy')" = "enforce-tmp-ai" ]
}

@test "allows a normalized write under /tmp/ai" {
    run fire_write "/tmp/ai/note.md"
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r '.decision')" = "allow" ]
}

@test "rejects malformed and unknown requests" {
    run "$EVALUATOR" <<<'{"version":1,"operation":"shell","command":""}'
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid request"* ]]

    run "$EVALUATOR" <<<'{"version":1,"operation":"write","write_paths":[]}'
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid request"* ]]

    run "$EVALUATOR" <<<'{"version":1,"operation":"launch"}'
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid request"* ]]
}
