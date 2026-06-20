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

# regex-engine cascade (rg > grep > awk) + re_match, shared with the
# sibling hooks. patterns below are POSIX ERE so all three engines accept
# them unchanged.
source "$(dirname "$0")/re-engine.sh"

# bad pattern 1: piped to tail/head. word boundary via [^[:alnum:]_] / EOL.
# `[|]` (char class) not `\|` -- awk treats `\|` as alternation w/ empty.
PAT_PIPED='[|][[:space:]]*(tail|head)([^[:alnum:]_]|$)'

# bad pattern 2: tail/head reading process substitution `<(cmd)`.
PAT_PROCSUB='(^|[^[:alnum:]_])(tail|head)[[:space:]][^|]*<[(]'

# allow pattern: tee'd through /tmp/claude/log/ in same pipeline. the
# [^|]* between tee and log path covers -a / --append, quoted paths,
# and multi-file tee where log dir is not the first arg.
PAT_TEE_OK='tee[[:space:]]+[^|]*/tmp/claude/log/'

if re_match "$PAT_PIPED" "$COMMAND" || re_match "$PAT_PROCSUB" "$COMMAND"; then
    if re_match "$PAT_TEE_OK" "$COMMAND"; then
        exit 0
    fi
    cat >&2 <<'EOF'
BLOCKED: bare `| tail` / `| head` discards the full log. use tee so it persists:

    mkdir -p /tmp/claude/log
    cmd 2>&1 | tee /tmp/claude/log/<name>.log | tail -50

if later you realise you would have wanted more output from that command, just read /tmp/claude/log/<name>.log. Only rerun if you expect the output to have changed.
EOF
    exit 2
fi

exit 0
