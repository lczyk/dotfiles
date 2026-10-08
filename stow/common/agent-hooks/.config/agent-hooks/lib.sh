# shellcheck shell=bash
# helpers shared by the agent policies in this dir and the git hooks. sourced,
# never executed, and every caller sources it fail-closed: a fence that can't
# find its helpers denies rather than turning into a no-op.

# fold line wraps and whitespace runs before matching. the callers match with
# line-based greps that have literal spaces in them, so a wrapped
# `git \<newline>push` or a stray `git  push` would otherwise walk past.
# folding only joins what the shell would join anyway -- it can widen a
# pattern's reach, never narrow it.
_fold() {
    printf '%s' "$1" | sed -E 's/\\$//' | tr '\n\t' '  ' | sed -E 's/  +/ /g'
}

# a folded command split at `;`, `|` and `&`, one segment per line.
_segments() {
    # shellcheck disable=SC2020  # a char-set mapping is the intent
    printf '%s\n' "$1" | tr ';|&' '\n\n\n'
}

# capability opt-outs, comma-separated, read from this process's OWN
# environment (`env AGENT_UNFENCE=branch claude`). an agent cannot grant
# itself one: a command's env-prefix reaches a policy as text on stdin, never
# as an actual variable.
_unfenced() {
    case ",${AGENT_UNFENCE}," in
        (*",$1,"*) return 0 ;;
    esac
    return 1
}

# the AGENT_UNFENCE tokens a capability check can match, one per line: split
# on commas and kept only when a bare word -- `branch, meta` grants branch.
_unfence_tokens() {
    local tok toks
    IFS=, read -ra toks <<< "$AGENT_UNFENCE"
    for tok in "${toks[@]}"; do
        [[ "$tok" =~ ^[A-Za-z0-9_-]+$ ]] && printf '%s\n' "$tok"
    done
    return 0
}

# agent sessions take the strict path in the git hooks. AGENT_SESSION is set
# by our own harness configs; CLAUDECODE, COPILOT_CLI and OPENCODE_PID are
# native fallbacks.
is_agent() {
    [ -n "$AGENT_SESSION" ] || [ "$CLAUDECODE" = "1" ] || [ "$COPILOT_CLI" = "1" ] || [ -n "$OPENCODE_PID" ]
}
