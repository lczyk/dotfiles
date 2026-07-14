#!/usr/bin/env bash
# Shell-command policy. makes sure anything written under /tmp/ai/log/ has a
# .log suffix, so the log dir stays greppable and the discourage-bare-tail
# convention stays consistent. exit 2 means policy denial; evaluate.sh
# translates that into a harness-neutral verdict.
#
# blocked:  a /tmp/ai/log/<file> path whose final component is not *.log
#           e.g. /tmp/ai/log/foo.txt, /tmp/ai/log/foo
# allowed:  *.log files, the dir itself, and subdir paths ending in *.log
#           e.g. /tmp/ai/log/foo.log, /tmp/ai/log/ , mkdir .../log
#
# NOTE: the path-safe char class stops at whitespace, quotes, and shell
# punctuation (;)|&<>), so each extracted token is just the path.

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.command')

PAT_LOGPATH='/tmp/ai/log/[A-Za-z0-9._/-]*'

# pull out every /tmp/ai/log/<path> token, flag any non-.log file.
# while-read (not mapfile) for bash 3.2 / macos compatibility.
bad=()
while IFS= read -r tok; do
    [[ -z "$tok" ]] && continue
    final="${tok##*/}"          # basename; empty if tok ends in '/'
    [[ -z "$final" ]] && continue   # dir reference, not a file write
    [[ "$final" == *.log ]] && continue
    bad+=("$tok")
done < <(printf '%s' "$COMMAND" | grep -oE -- "$PAT_LOGPATH")

if ((${#bad[@]})); then
    {
        printf 'BLOCKED: files under /tmp/ai/log/ must end in .log:\n\n'
        for t in "${bad[@]}"; do printf '    %s\n' "$t"; done
        printf '\nrename so the final component ends in .log, e.g. /tmp/ai/log/<name>.log\n'
    } >&2
    exit 2
fi

exit 0
