#!/usr/bin/env bash
# brightness keys walk a fixed ladder of percentages instead of a linear
# step, so the dim end has fine rungs and the bright end coarse ones.
set -e

# rungs in tenths of a percent, ascending
LADDER=(0 5 10 50 100 200 300 400 500 600 700 800 900 1000)

function _usage() { printf 'usage: %s up|down\n' "${0##*/}" >&2; }

function _raw() { printf '%d' $(( $2 * $1 / 1000 )); }

function main() {
    local cur max rung target
    cur=$(light -r -G)
    max=$(light -r -M)
    case "${1:-}" in
        (down)
            target=0
            for rung in "${LADDER[@]}"; do
                rung=$(_raw "${rung}" "${max}")
                [ "${rung}" -lt "${cur}" ] && target=${rung}
            done
            ;;
        (up)
            target=${max}
            for ((i = ${#LADDER[@]} - 1; i >= 0; i--)); do
                rung=$(_raw "${LADDER[i]}" "${max}")
                [ "${rung}" -gt "${cur}" ] && target=${rung}
            done
            ;;
        (*) _usage; exit 2 ;;
    esac
    light -r -S "${target}"
}

main "$@"
