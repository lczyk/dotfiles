#!/usr/bin/env bash
# PreToolUse hook for the Bash tool. blocks bare `| tail` / `| head` and
# `tail <(...)` / `head <(...)` process-substitution forms.
#
# preferred pattern:
#   cmd 2>&1 | tee /tmp/claude/log/<name>.log | tail -N
#
# the log persists -- if you need more lines later, read the file
# directly instead of rerunning the command.
#
# allowed: any command that tees into /tmp/claude/log/ (log is preserved).
#          covers tee -a / --append, quoted paths, multi-file tee.
# blocked: bare `| tail` / `| head` / process-sub variants w/out tee to log.
#
# TODO: edge cases not handled -- require real shell parsing:
#   - variable-expanded log path:  LOG=/tmp/claude/log/x.log; cmd | tee $LOG | tail
#   - literal `| tail` inside quoted string: git commit -m "fix | tail crash"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

# bad pattern 1: piped to tail/head (word-boundary excludes tailscale, header, etc.)
# bad pattern 2: tail/head reading process substitution `<(cmd)`
if echo "$COMMAND" | grep -qE '\|\s*(tail|head)\b' \
   || echo "$COMMAND" | grep -qE '\b(tail|head)\b[^|]*<\('; then
    # allow if tee'd through /tmp/claude/log/ in same pipeline.
    # `[^|]*` between tee and log path lets through -a / --append flags,
    # quoted paths, and multi-file tee where log dir is not the first arg.
    if echo "$COMMAND" | grep -qE 'tee\s+[^|]*/tmp/claude/log/'; then
        exit 0
    fi
    cat >&2 <<'EOF'
BLOCKED: bare `| tail` / `| head` discards the full log. use tee so it persists:

    mkdir -p /tmp/claude/log
    cmd 2>&1 | tee /tmp/claude/log/<name>.log | tail -50

if you need more output later, read /tmp/claude/log/<name>.log directly -- no rerun needed.
EOF
    exit 2
fi

exit 0
