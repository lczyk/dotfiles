#!/usr/bin/env bash
# Translate claude / codex PreToolUse payloads into evaluator requests, and
# the evaluator's verdict back into the harness's answer. both harnesses
# share the payload shape for shell calls and the exit-2 / hookSpecificOutput
# contract, so only the request builders differ.
#
# usage: adapter.sh <claude|codex> <mode>
#   claude: shell | write      codex: shell | patch

HARNESS="${1:-}"
MODE="${2:-}"
ENGINE="${AGENT_HOOK_EVALUATOR:-$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/evaluate.sh}"

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

    # deletes are writes too: a Delete File line, or the `--- a/` side of a
    # unified diff (the old name of a rename, the file a /dev/null target
    # drops). strip CR first so a CRLF patch cannot smuggle a path past the
    # globs; read the git rename / copy / diff --git headers (which carry no
    # +++/--- hunk); and tolerate the quotes git puts around a path in a header.
    paths=$(
        printf '%s\n' "$patch" | tr -d '\r' |
            sed -nE \
                -e 's/^\*\*\* (Add|Update|Delete) File: "?([^"]*)"?$/\2/p' \
                -e 's/^\*\*\* Move to: "?([^"]*)"?$/\1/p' \
                -e 's/^\+\+\+ "?b\/([^"]*)"?$/\1/p' \
                -e 's/^--- "?a\/([^"]*)"?$/\1/p' \
                -e 's/^(rename|copy) (from|to) "?([^"]*)"?$/\3/p' \
                -e 's/^diff --git "?a\/([^ "]*).*/\1/p' |
            jq -Rsc 'split("\n") | map(select(length > 0)) | unique'
    ) || return 1

    [ "$(printf '%s' "$paths" | jq 'length')" -gt 0 ] || return 1

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

    verdict=$(printf '%s' "$request" | "$ENGINE")
    status=$?
    [ "$status" -eq 0 ] || _deny "BLOCKED: safety evaluator failed with status $status"

    decision=$(printf '%s' "$verdict" | jq -er '.decision')
    case "$decision" in
        (allow)
            printf '%s' "$verdict" | jq -c '
                select((.hints // [] | length) > 0)
                | {hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: (.hints | join("\n\n"))}}
            '
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
    local name
    local input
    local request

    case "$HARNESS" in
        (claude) name=Claude ;;
        (codex) name=Codex ;;
        (*) _deny "BLOCKED: unknown safety adapter harness: $HARNESS" ;;
    esac
    case "$HARNESS:$MODE" in
        (claude:shell | claude:write | codex:shell | codex:patch) ;;
        (*) _deny "BLOCKED: unknown $name safety adapter mode: $MODE" ;;
    esac

    input=$(cat)
    case "$MODE" in
        (shell)
            request=$(_shell_request "$input") ||
                _deny "BLOCKED: cannot inspect $name shell payload"
            ;;
        (write)
            request=$(_write_request "$input") ||
                _deny "BLOCKED: cannot inspect $name write destinations"
            ;;
        (patch)
            request=$(_patch_request "$input") ||
                _deny "BLOCKED: cannot inspect $name patch destinations"
            ;;
    esac

    _evaluate "$request"
}

main "$@"
