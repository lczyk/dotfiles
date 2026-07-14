#!/usr/bin/env bash
# Harness-neutral safety policy evaluator.
#
# Request:
#   {"version":1,"operation":"shell","command":"..."}
#   {"version":1,"operation":"write","write_paths":["..."]}
#
# Verdict:
#   {"decision":"allow"}
#   {"decision":"deny","policy":"...","reason":"..."}
#
# Policy denials are data and therefore exit 0. Non-zero means the evaluator
# itself failed; harness adapters must translate that into a fail-closed result.

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd -P)
INPUT=$(cat)

function _fail() {
    printf 'agent hook evaluator: %s\n' "$1" >&2
    exit 1
}

function _validate_input() {
    printf '%s' "$INPUT" | jq -e '
        .version == 1 and
        (
            (
                .operation == "shell" and
                (.command | type == "string" and length > 0)
            ) or
            (
                .operation == "write" and
                (.write_paths | type == "array") and
                (.write_paths | length > 0) and
                (.write_paths | all(.[]; type == "string" and length > 0))
            )
        )
    ' >/dev/null
}

function _run_policy() {
    local policy="$1"
    local reason
    local status

    reason=$(printf '%s' "$INPUT" | "$SCRIPT_DIR/$policy" 2>&1 >/dev/null)
    status=$?

    case "$status" in
        (0)
            return
            ;;
        (2)
            jq -cn \
                --arg policy "${policy%.sh}" \
                --arg reason "$reason" \
                '{decision: "deny", policy: $policy, reason: $reason}'
            exit 0
            ;;
        (*)
            _fail "$policy failed with status $status${reason:+: $reason}"
            ;;
    esac
}

function main() {
    local operation
    local policies
    local policy

    _validate_input || _fail "invalid request"
    operation=$(printf '%s' "$INPUT" | jq -r '.operation')

    case "$operation" in
        (shell)
            policies=(
                block-dangerous.sh
                discourage-bare-tail.sh
                enforce-log-suffix.sh
                enforce-tmp-ai.sh
            )
            ;;
        (write)
            policies=(
                enforce-tmp-ai.sh
            )
            ;;
        (*)
            _fail "unsupported operation: $operation"
            ;;
    esac

    for policy in "${policies[@]}"; do
        _run_policy "$policy"
    done

    printf '{"decision":"allow"}\n'
}

main "$@"
