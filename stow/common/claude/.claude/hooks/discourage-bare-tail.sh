#!/usr/bin/env bash
# PreToolUse hook for the Bash tool. blocks bare `| tail` patterns.
#
# preferred pattern:
#   cmd 2>&1 | tee /tmp/claude/log/<name>.log | tail -N
#
# the log persists -- if you need more lines later, read the file
# directly instead of rerunning the command.
#
# allowed: any command that tees into /tmp/claude/log/ (log is preserved).
# blocked: | tail without tee to /tmp/claude/log/ (output lost after read).

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

if echo "$COMMAND" | grep -qE '\|\s*tail(\s|$|-[0-9nfq])'; then
    if echo "$COMMAND" | grep -qE 'tee\s+/tmp/claude/log/'; then
        exit 0
    fi
    cat >&2 <<'EOF'
BLOCKED: bare `| tail` discarded the full log. use tee so it persists:

    mkdir -p /tmp/claude/log
    cmd 2>&1 | tee /tmp/claude/log/<name>.log | tail -50

if you need more output later, read /tmp/claude/log/<name>.log directly -- no rerun needed.
EOF
    exit 2
fi

exit 0
