#!/usr/bin/env bash
# Translate Codex hook payloads and policy verdicts.

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

function _patch_request() {
    local input="$1"
    local patch
    local paths

    patch=$(printf '%s' "$input" | jq -er '
        .tool_input
        | if type == "string" then .
          elif type == "object" then (.command // .patch // .input)
          else empty
          end
        | select(type == "string")
    ') || return 1

    paths=$(
        printf '%s\n' "$patch" |
            sed -nE \
                -e 's/^\*\*\* (Add|Update) File: (.*)$/\2/p' \
                -e 's/^\*\*\* Move to: (.*)$/\1/p' \
                -e 's/^\+\+\+ b\/(.*)$/\1/p' |
            jq -Rsc 'split("\n") | map(select(length > 0)) | unique'
    ) || return 1

    if [ "$(printf '%s' "$paths" | jq 'length')" -eq 0 ]; then
        if printf '%s\n' "$patch" | grep -qE -- '^\*\*\* Delete File: |^\+\+\+ /dev/null$'; then
            printf '{"decision":"allow"}'
            return
        fi
        return 1
    fi

    jq -cn \
        --argjson paths "$paths" \
        '{version: 1, operation: "write", write_paths: $paths}'
}

function _evaluate() {
    local request="$1"
    local verdict
    local status
    local decision
    local reason

    if [ "$(printf '%s' "$request" | jq -r '.decision // empty')" = "allow" ]; then
        return
    fi

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
        (shell|patch) ;;
        (*) _deny "BLOCKED: unknown Codex safety adapter mode: $MODE" ;;
    esac

    input=$(cat)
    case "$MODE" in
        (shell)
            request=$(_shell_request "$input") ||
                _deny "BLOCKED: cannot inspect Codex shell payload"
            ;;
        (patch)
            request=$(_patch_request "$input") ||
                _deny "BLOCKED: cannot inspect Codex patch destinations"
            ;;
    esac

    _evaluate "$request"
}

main "$@"
