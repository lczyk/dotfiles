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
# (avoids the non-portable `env -S` shebang trick). `--test` is the one
# exception: it runs the embedded self-test (see the bottom of the file).
if [[ "${BASH_SOURCE[0]}" == "${0}" && "${1:-}" != "--test" ]]; then
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
    # `-e` (rg) / `--` (grep) keep a leading-dash PATTERN from being parsed as
    # an option. awk reads the pattern via ENVIRON (not -v, which would strip
    # backslash escapes like \. and \*), so it's dash-safe too.
    re_match() {
        local pat="$1" text="$2"
        case "$RE_ENGINE" in
            rg)   printf '%s' "$text" | rg -q -e "$pat" ;;
            grep) printf '%s' "$text" | grep -qE -- "$pat" ;;
            awk)  printf '%s' "$text" | p="$pat" awk '$0 ~ ENVIRON["p"] { found=1; exit } END { exit !found }' ;;
        esac
    }

    # re_extract PATTERN TEXT -- print every match of PATTERN in TEXT, one
    # per line. awk has no -o, so it loops match()/substr() per line.
    re_extract() {
        local pat="$1" text="$2"
        case "$RE_ENGINE" in
            rg)   printf '%s' "$text" | rg -oN -e "$pat" ;;
            grep) printf '%s' "$text" | grep -oE -- "$pat" ;;
            awk)  printf '%s' "$text" | p="$pat" awk '
                      BEGIN { p=ENVIRON["p"] }
                      { s=$0; while (match(s, p)) {
                          print substr(s, RSTART, RLENGTH); s=substr(s, RSTART+RLENGTH) } }' ;;
        esac
    }

    # NOTE: don't export the sentinel. a child bash inherits the env var but
    # not the shell functions, so it'd see the guard set and skip defining
    # re_match / re_extract -- breaking any child that sources this lib.
    __RE_ENGINE_SH__=1
fi

############################################################################
# embedded self-test. run as `bash re-engine.sh --test` (or via the
# re-engine.test.sh shim). re-runs every test_* fn under each available
# engine, so rg / grep / awk must agree on the POSIX-ERE patterns.
if [[ "${#BASH_SOURCE[@]}" -eq 1 && "${BASH_SOURCE[0]}" == "$0" && "${1:-}" == "--test" ]]; then

    # re_match hit + miss
    function test_match_hit()  { re_match 'foo' 'a foo b'; }
    function test_match_miss() { ! re_match 'foo' 'a bar b'; }

    # re_extract prints every match, one per line
    function test_extract_multi() {
        local got; got=$(re_extract '[0-9]+' 'a12 b3 c456')
        test "$got" = $'12\n3\n456' || return 1
    }

    # leading-dash pattern must not be parsed as an option (the -e / -- / -v
    # dash-safety in re_match / re_extract).
    function test_leading_dash() {
        re_match -- 'x -- y' || return 1
        local got; got=$(re_extract -- 'a -- b -- c')
        test "$got" = $'--\n--' || return 1
    }

    # alternation `a|b` -- guards the `[|]`-not-`\|` awk caveat
    function test_alternation() {
        re_match 'cat|dog' 'i have a dog' || return 1
        ! re_match 'cat|dog' 'i have a fish' || return 1
    }

    # backslash escapes stay literal -- guards the awk ENVIRON-not-`-v` fix,
    # which otherwise strips \. and \* (turning them into . and *).
    function test_escape() {
        re_match 'a\.b' 'a.b'    || return 1  # \. is a literal dot
        ! re_match 'a\.b' 'axb'  || return 1  # ...not any-char
        re_match 'a\*' 'a*'      || return 1  # \* is a literal star
    }

    # `(^|[ ;|&])` start-or-separator anchor -- the dominant pattern shape in
    # block-dangerous; must agree across engines.
    function test_anchor() {
        re_match '(^|[ ;|&])git' 'git status'   || return 1  # at start
        re_match '(^|[ ;|&])git' 'foo && git x' || return 1  # after separator
        ! re_match '(^|[ ;|&])git' 'mygit x'    || return 1  # not mid-word
    }

    # no color when NO_COLOR is set (any value) or stdout is not a tty
    if [[ -n "${NO_COLOR+x}" || ! -t 1 ]]; then
        c_green="" c_red="" c_reset=""
    else
        c_green=$'\e[32m' c_red=$'\e[31m' c_reset=$'\e[0m'
    fi

    # discover test fns in declaration order (declare -F sorts alphabetically,
    # so scan the source instead).
    test_funcs=()
    while read -r line; do
        [[ $line =~ ^[[:space:]]*function[[:space:]]+(test_[A-Za-z0-9_]+) ]] || continue
        test_funcs+=("${BASH_REMATCH[1]}")
    done < "${BASH_SOURCE[0]}"

    status=0
    for engine in rg grep awk; do
        if ! command -v "$engine" >/dev/null 2>&1; then
            printf 'skip: %s not installed\n' "$engine"
            continue
        fi
        RE_ENGINE="$engine"
        pass=0 fail=0
        for test_func in "${test_funcs[@]}"; do
            if $test_func; then
                pass=$((pass+1))
            else
                fail=$((fail+1)); status=1
                printf '%s[%s] %s failed%s\n' "$c_red" "$engine" "$test_func" "$c_reset"
            fi
        done
        printf '[%s] %d passed, %d failed (of %d)\n' "$engine" "$pass" "$fail" "${#test_funcs[@]}"
    done

    if [[ $status -eq 0 ]]; then
        printf '%sSelf-test passed%s\n' "$c_green" "$c_reset"
    else
        printf '%sSelf-test failed%s\n' "$c_red" "$c_reset"
    fi
    exit $status
fi
