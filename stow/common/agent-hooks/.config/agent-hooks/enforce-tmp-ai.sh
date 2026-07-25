#!/usr/bin/env bash
# Shell/write policy. ai scratch files in /tmp must live under /tmp/ai/.
# exit 2 means policy denial; evaluate.sh translates that into a
# harness-neutral verdict. reads of existing /tmp files are fine.
#
# request channels:
#   - shell: redirects (> / >>) and `tee` targeting /tmp/<not-ai>, plus bare
#            `mktemp` (lands in /tmp/tmp.XXXX) -- require -p /tmp/ai.
#   - write: normalized destination paths supplied in write_paths. harness
#            adapters own extraction from direct edits and patch formats.
#
# TODO(lczyk): edge cases need real shell parsing (documented xfail in the bats):
#   - install / sed -i dest args, `git init /tmp/x`, writes from inside an
#     interpreter (python3 -c "open('/tmp/x','w')")
#   - cd /tmp; touch foo            (relative path after cd)
#   - $VAR-expanded paths, literal '>' inside a quoted string
#   - tee with flags / multiple files (only the first path after tee is seen)

INPUT=$(cat)
OPERATION=$(printf '%s' "$INPUT" | jq -r '.operation')
COMMAND=$(printf '%s' "$INPUT" | jq -r '.command // empty')

# fold line wraps and whitespace runs -- `cmd > \<newline>/tmp/x` is still a
# redirect to /tmp. same fold in the sibling policies; kept inline so a
# missing helper can't turn this into a no-op.
COMMAND=$(printf '%s' "$COMMAND" | sed -E 's/\\$//' | tr '\n\t' '  ' | sed -E 's/  +/ /g')

# a path is allowed iff it isn't under /tmp at all, or it's /tmp/ai[/...].
# /tmp is a symlink to /private/tmp on macos; the harness hands out an
# already-resolved /private/tmp scratchpad, so gate both prefixes.
function _under_ai() {
    # a `..` climbs back out of /tmp/ai -- refuse rather than resolve it.
    if [[ "$1" == /tmp/* || "$1" == /private/tmp/* ]] &&
        [[ "$1" == */../* || "$1" == */.. ]]; then
        return 1
    fi
    case "$1" in
        /tmp/ai | /tmp/ai/*) return 0 ;;
        /private/tmp/ai | /private/tmp/ai/*) return 0 ;;
        /tmp/* | /private/tmp/*) return 1 ;;
        # the dir itself is a destination too, e.g. `tar -C /tmp`
        /tmp | /private/tmp) return 1 ;;
        *) return 0 ;;
    esac
}

# a quote character, kept out of the patterns below so they stay readable.
Q='["'"'"']'
PAT_TMPPATH="$Q?(/private)?/tmp(/[A-Za-z0-9._/-]*)?"

bad=()

# strip a leading quote left over from `> "/tmp/x"`, then judge the path.
function _check_path() {
    local path="$1"
    path=${path#[\"\']}
    path=${path%[\"\']}
    [[ -z "$path" ]] && return
    _under_ai "$path" || bad+=("$path")
}

# -- normalized write destinations --------------------------------------
if [[ "$OPERATION" == write ]]; then
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        _under_ai "$path" || bad+=("$path")
    done < <(printf '%s' "$INPUT" | jq -r '.write_paths[]')
fi

# -- shell command -------------------------------------------------------
if [[ "$OPERATION" == shell && -n "$COMMAND" ]]; then
    # redirect / tee write targets in /tmp. while-read (not mapfile) for
    # bash 3.2 / macos.
    while IFS= read -r tok; do
        [[ -z "$tok" ]] && continue
        path="${tok##* }"             # last field (handles `> /tmp/x`)
        path="${path##*>}"            # strip a glued `>`/`>>` (handles `>/tmp/x`)
        _check_path "$path"
    done < <(printf '%s' "$COMMAND" | grep -oE -- "(>>?|tee)[[:space:]]*$PAT_TMPPATH")

    # touch / mkdir take destinations only, so every /tmp arg is a write.
    while IFS= read -r seg; do
        while IFS= read -r tok; do
            _check_path "$tok"
        done < <(printf '%s' "$seg" | grep -oE -- "$PAT_TMPPATH")
    done < <(printf '%s' "$COMMAND" | grep -oE -- "(^|[ ;|&])(touch|mkdir)[[:space:]][^;|&]*")

    # cp / mv: only the final argument is the destination -- copying a file
    # OUT of /tmp is a read and stays fine.
    while IFS= read -r seg; do
        seg="${seg% }"
        _check_path "${seg##* }"
    done < <(printf '%s' "$COMMAND" | grep -oE -- "(^|[ ;|&])(cp|mv)[[:space:]][^;|&]*")

    # download / copy tools that name their destination with a flag.
    while IFS= read -r tok; do
        _check_path "${tok##* }"
    done < <(printf '%s' "$COMMAND" | grep -oE -- "(-o|--output)[[:space:]]+$PAT_TMPPATH")

    while IFS= read -r tok; do
        _check_path "${tok#of=}"
    done < <(printf '%s' "$COMMAND" | grep -oE -- "of=$PAT_TMPPATH")

    # tar -C <dir> extracts into that dir. `-C` alone is too common to match
    # (git -C <repo> is a read), so anchor it to a tar invocation.
    while IFS= read -r tok; do
        _check_path "${tok##* }"
    done < <(printf '%s' "$COMMAND" | grep -oE -- "(^|[ ;|&])tar[^;|&]*-C[[:space:]]+$PAT_TMPPATH")

    # mktemp defaults to /tmp/tmp.XXXX -- require it to target /tmp/ai.
    if printf '%s' "$COMMAND" | grep -qE -- '(^|[^[:alnum:]_])mktemp([^[:alnum:]_]|$)'; then
        printf '%s' "$COMMAND" | grep -qE -- '/tmp/ai' || bad+=("mktemp (must use -p /tmp/ai)")
    fi
fi

if ((${#bad[@]})); then
    {
        printf 'BLOCKED: ai scratch files in /tmp must live under /tmp/ai/:\n\n'
        for t in "${bad[@]}"; do printf '    %s\n' "$t"; done
        printf '\nput it under /tmp/ai/ instead, e.g. /tmp/ai/<name>.\n'
        printf 'for mktemp: mktemp -p /tmp/ai. (reads of existing /tmp files are fine.)\n'
    } >&2
    exit 2
fi

exit 0
