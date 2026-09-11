#!/usr/bin/env bash
# shared colour helper for the statusline badges. sourced, never executed --
# it lives outside statusline.d so the dispatcher can't mistake it for a badge.
#
# badges use the terminal's own 16-colour palette (sgr 30-37 / 90-97) rather
# than fixed 256-colour or truecolor values, so they follow whatever palette
# the terminal has active -- dark, light, or swapped at runtime.
#
# usage:
#     . "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline-colour.sh"
#     sl_paint "$SL_YELLOW" '[C]'
#     sl_paint "$SL_BRED" '[U:branch]'

# shellcheck disable=SC2034  # consumed by the badges that source this file
SL_RED=31
SL_GREEN=32
SL_YELLOW=33
SL_BLUE=34
SL_MAGENTA=35
SL_CYAN=36
SL_WHITE=37
SL_BRED=91
SL_BGREEN=92
SL_BYELLOW=93
SL_BBLUE=94
SL_BMAGENTA=95
SL_BCYAN=96
SL_BWHITE=97

# print `text` in sgr colour `code`
sl_paint() {
    printf '\033[%sm%s\033[0m' "$1" "$2"
}
