#!/usr/bin/env bash
# shared regex-engine cascade for the Bash PreToolUse hooks.
#
# source it from a hook:
#   source "$(dirname "$0")/re-engine.sh"
# then use re_match (boolean) or re_extract (print each match, one per line).
#
# engine cascade: rg > grep > awk. picked once into RE_ENGINE. patterns
# passed in must be POSIX ERE (no \s / \b) so all three accept them
# unchanged. set RE_ENGINE before sourcing to force a specific engine
# (e.g. tests run the matrix this way).

# refuse direct execution -- this is a library. portable sourced-check
# (avoids the non-portable `env -S` shebang trick).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    printf 'this file should be sourced, not executed\n' >&2
    exit 1
fi

if [[ -z "${__RE_ENGINE_SH__:-}" ]]; then

    if [[ -z "${RE_ENGINE:-}" ]]; then
        if command -v rg >/dev/null 2>&1; then
            RE_ENGINE=rg
        elif command -v grep >/dev/null 2>&1; then
            RE_ENGINE=grep
        else
            RE_ENGINE=awk
        fi
    fi

    # re_match PATTERN TEXT -- exit 0 iff PATTERN matches somewhere in TEXT.
    # `[|]` (char class) not `\|` -- awk treats `\|` as alternation w/ empty.
    re_match() {
        local pat="$1" text="$2"
        case "$RE_ENGINE" in
            rg)   printf '%s' "$text" | rg -q "$pat" ;;
            grep) printf '%s' "$text" | grep -qE "$pat" ;;
            awk)  printf '%s' "$text" | awk -v p="$pat" '$0 ~ p { found=1; exit } END { exit !found }' ;;
        esac
    }

    # re_extract PATTERN TEXT -- print every match of PATTERN in TEXT, one
    # per line. awk has no -o, so it loops match()/substr() per line.
    re_extract() {
        local pat="$1" text="$2"
        case "$RE_ENGINE" in
            rg)   printf '%s' "$text" | rg -oN "$pat" ;;
            grep) printf '%s' "$text" | grep -oE "$pat" ;;
            awk)  printf '%s' "$text" | awk -v p="$pat" '
                      { s=$0; while (match(s, p)) {
                          print substr(s, RSTART, RLENGTH); s=substr(s, RSTART+RLENGTH) } }' ;;
        esac
    }

    export __RE_ENGINE_SH__=1
fi
