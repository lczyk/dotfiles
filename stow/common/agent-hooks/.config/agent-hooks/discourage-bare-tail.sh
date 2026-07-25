#!/usr/bin/env bash
# Shell-command policy. blocks bare `| tail` / `| head` and `tail <(...)` /
# `head <(...)` process-substitution forms. exit 2 means policy denial;
# evaluate.sh translates that into a harness-neutral verdict.
#
# preferred pattern:
#   cmd 2>&1 | tee /tmp/ai/log/<name>.log | tail -N
#
# the log persists -- if you need more lines later, read the file
# directly instead of rerunning the command.
#
# allowed: any command that tees into /tmp/ai/log/ (log is preserved).
#          covers tee -a / --append, quoted paths, multi-file tee.
# blocked: bare `| tail` / `| head` / process-sub variants w/out tee to log.
#
# TODO: edge cases not handled -- require real shell parsing:
#   - variable-expanded log path:  LOG=/tmp/ai/log/x.log; cmd | tee $LOG | tail
#   - literal `| tail` inside quoted string: git commit -m "fix | tail crash"

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.command')

# fold line wraps and whitespace runs -- `cmd |<newline>tail -5` is one
# pipeline, but a line-based grep can't see it. same fold in the sibling
# policies; kept inline so a missing helper can't turn this into a no-op.
COMMAND=$(printf '%s' "$COMMAND" | sed -E 's/\\$//' | tr '\n\t' '  ' | sed -E 's/  +/ /g')

# bad pattern 1: piped to tail/head. word boundary via [^[:alnum:]_] / EOL.
# `[|]` (char class) for a literal pipe.
PAT_PIPED='[|][[:space:]]*(tail|head)([^[:alnum:]_]|$)'

# bad pattern 2: tail/head reading process substitution `<(cmd)`.
PAT_PROCSUB='(^|[^[:alnum:]_])(tail|head)[[:space:]][^|]*<[(]'

# allow pattern: tee'd through /tmp/ai/log/ in same pipeline. the
# [^|]* between tee and log path covers -a / --append, quoted paths,
# and multi-file tee where log dir is not the first arg.
PAT_TEE_OK='tee[[:space:]]+[^|]*/tmp/ai/log/'

# the tee has to be in the SAME pipeline as the tail, so check per segment:
# `cmd | tee log | tail && other | tail` leaves the second tail bare.
# `;`, `&&` and `||` end a pipeline; a lone `|` continues it.
SEGMENTS=${COMMAND//&&/$'\n'}
SEGMENTS=${SEGMENTS//||/$'\n'}
SEGMENTS=${SEGMENTS//;/$'\n'}

bare=0
while IFS= read -r seg; do
    [[ -z "$seg" ]] && continue
    printf '%s' "$seg" | grep -qE -- "$PAT_PIPED" ||
        printf '%s' "$seg" | grep -qE -- "$PAT_PROCSUB" ||
        continue
    printf '%s' "$seg" | grep -qE -- "$PAT_TEE_OK" && continue
    bare=1
    break
done <<< "$SEGMENTS"

if ((bare)); then
    cat >&2 <<'EOF'
BLOCKED: bare `| tail` / `| head` discards the full log. use tee so it persists:

    mkdir -p /tmp/ai/log
    cmd 2>&1 | tee /tmp/ai/log/<name>.log | tail -50

if later you realise you would have wanted more output from that command, just read /tmp/ai/log/<name>.log. Only rerun if you expect the output to have changed.
EOF
    exit 2
fi

exit 0
