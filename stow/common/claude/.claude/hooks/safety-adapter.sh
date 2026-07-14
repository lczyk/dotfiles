#!/usr/bin/env bash
# Translate Claude PreToolUse payloads and policy verdicts.

MODE="${1:-}"
ENGINE="${AGENT_HOOK_EVALUATOR:-$HOME/.config/agent-hooks/evaluate.sh}"

function _deny() {
    printf '%s\n' "$1" >&2
    exit 2
}

function _shell_request() {
    printf '%s' "$1" | jq -ce '
        {
            version: 1,
            operation: "shell",
            command: .tool_input.command
        }
        | select(.command | type == "string")
    '
}

function _write_request() {
    printf '%s' "$1" | jq -ce '
        {
            version: 1,
            operation: "write",
            write_paths: (
                [
                    .tool_input.file_path,
                    .tool_input.filePath,
                    .tool_input.path,
                    .tool_input.notebook_path,
                    .tool_input.notebookPath
                ]
                | map(select(type == "string" and length > 0))
                | unique
            )
        }
        | select(.write_paths | length > 0)
    '
}

function _evaluate() {
    local request="$1"
    local verdict
    local status
    local decision
    local reason

    verdict=$(printf '%s' "$request" | "$ENGINE")
    status=$?
    [ "$status" -eq 0 ] || _deny "BLOCKED: safety evaluator failed with status $status"

    decision=$(printf '%s' "$verdict" | jq -er '.decision')
    case "$decision" in
        (allow)
            return
            ;;
        (deny)
            reason=$(printf '%s' "$verdict" | jq -r '.reason // "blocked by safety policy"')
            _deny "$reason"
            ;;
        (*)
            _deny "BLOCKED: safety evaluator returned an invalid verdict"
            ;;
    esac
}

function main() {
    local input
    local request

    case "$MODE" in
        (shell|write) ;;
        (*) _deny "BLOCKED: unknown Claude safety adapter mode: $MODE" ;;
    esac

    input=$(cat)
    case "$MODE" in
        (shell)
            request=$(_shell_request "$input") ||
                _deny "BLOCKED: cannot inspect Claude shell payload"
            ;;
        (write)
            request=$(_write_request "$input") ||
                _deny "BLOCKED: cannot inspect Claude write destinations"
            ;;
    esac

    _evaluate "$request"
}

main "$@"
