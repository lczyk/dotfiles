#!/usr/bin/env bash
# PreToolUse hook. claude's scratch files in /tmp must live under /tmp/claude/.
# blocks (exit 2, nudge) any creation elsewhere in /tmp. reads of existing /tmp
# files are fine -- only writes/creation are gated.
#
# two channels, wired under two matchers in settings.json:
#   - Bash:   redirects (> / >>) and `tee` targeting /tmp/<not-claude>, plus
#             bare `mktemp` (lands in /tmp/tmp.XXXX) -- require -p /tmp/claude.
#   - Write / Edit / NotebookEdit:  tool_input.file_path under /tmp/<not-claude>.
#
# TODO(lczyk): edge cases need real shell parsing (documented xfail in the bats):
#   - cp / mv / touch / install / dd of= / sed -i dest args
#   - cd /tmp; touch foo            (relative path after cd)
#   - $VAR-expanded paths, literal '>' inside a quoted string
#   - tee with flags / multiple files (only the first path after tee is seen)

INPUT=$(cat)

# regex-engine cascade (rg > grep > awk) + re_match / re_extract, shared with
# the sibling hooks. patterns below are POSIX ERE so all three accept them.
source "$(dirname "$0")/re-engine.sh"

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')

# a path is allowed iff it isn't under /tmp at all, or it's /tmp/claude[/...].
under_claude() {
    case "$1" in
        /tmp/claude | /tmp/claude/*) return 0 ;;
        /tmp/*) return 1 ;;
        *) return 0 ;;
    esac
}

bad=()

# -- channel: Write / Edit / NotebookEdit (clean file_path, no parsing) --
if [[ -n "$FILE" ]]; then
    under_claude "$FILE" || bad+=("$FILE")
fi

# -- channel: Bash ------------------------------------------------------
if [[ -n "$CMD" ]]; then
    # redirect / tee write targets in /tmp. while-read (not mapfile) for
    # bash 3.2 / macos. `[(]`-free pattern -- POSIX ERE across all engines.
    while IFS= read -r tok; do
        [[ -z "$tok" ]] && continue
        path="${tok##*[[:space:]]}"   # last field (handles `> /tmp/x`)
        path="${path##*>}"            # strip a glued `>`/`>>` (handles `>/tmp/x`)
        under_claude "$path" || bad+=("$path")
    done < <(re_extract '(>>?|tee)[[:space:]]*/tmp/[A-Za-z0-9._/-]*' "$CMD")

    # mktemp defaults to /tmp/tmp.XXXX -- require it to target /tmp/claude.
    if re_match '(^|[^[:alnum:]_])mktemp([^[:alnum:]_]|$)' "$CMD"; then
        re_match '/tmp/claude' "$CMD" || bad+=("mktemp (must use -p /tmp/claude)")
    fi
fi

if ((${#bad[@]})); then
    {
        printf 'BLOCKED: claude scratch files in /tmp must live under /tmp/claude/:\n\n'
        for t in "${bad[@]}"; do printf '    %s\n' "$t"; done
        printf '\nput it under /tmp/claude/ instead, e.g. /tmp/claude/<name>.\n'
        printf 'for mktemp: mktemp -p /tmp/claude. (reads of existing /tmp files are fine.)\n'
    } >&2
    exit 2
fi

exit 0
