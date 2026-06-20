#!/usr/bin/env bash
# PreToolUse hook for the Bash tool. makes sure anything written under
# /tmp/claude/log/ has a .log suffix, so the log dir stays greppable and
# the discourage-bare-tail convention (tee into a .log) is consistent.
#
# blocked:  a /tmp/claude/log/<file> path whose final component is not *.log
#           e.g. /tmp/claude/log/foo.txt, /tmp/claude/log/foo
# allowed:  *.log files, the dir itself, and subdir paths ending in *.log
#           e.g. /tmp/claude/log/foo.log, /tmp/claude/log/ , mkdir .../log
#
# NOTE: the path-safe char class stops at whitespace, quotes, and shell
# punctuation (;)|&<>), so each extracted token is just the path.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

# regex-engine cascade (rg > grep > awk) + re_extract, shared with the
# sibling hooks. the pattern below is POSIX ERE so all three engines
# accept it unchanged.
source "$(dirname "$0")/re-engine.sh"

PAT_LOGPATH='/tmp/claude/log/[A-Za-z0-9._/-]*'

# pull out every /tmp/claude/log/<path> token, flag any non-.log file.
# while-read (not mapfile) for bash 3.2 / macos compatibility.
bad=()
while IFS= read -r tok; do
    [[ -z "$tok" ]] && continue
    final="${tok##*/}"          # basename; empty if tok ends in '/'
    [[ -z "$final" ]] && continue   # dir reference, not a file write
    [[ "$final" == *.log ]] && continue
    bad+=("$tok")
done < <(re_extract "$PAT_LOGPATH" "$COMMAND")

if ((${#bad[@]})); then
    {
        printf 'BLOCKED: files under /tmp/claude/log/ must end in .log:\n\n'
        for t in "${bad[@]}"; do printf '    %s\n' "$t"; done
        printf '\nrename so the final component ends in .log, e.g. /tmp/claude/log/<name>.log\n'
    } >&2
    exit 2
fi

exit 0
