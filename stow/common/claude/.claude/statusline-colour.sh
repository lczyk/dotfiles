#!/usr/bin/env bash
# shared colour helper for the statusline badges. sourced, never executed --
# it lives outside statusline.d so the dispatcher can't mistake it for a badge.
#
# problem: badges pick fixed 256-colour foregrounds. against a terminal
# background of similar brightness the text goes near-invisible. so: resolve
# the badge colour to rgb, resolve the terminal background to rgb, and if the
# two are too close, render inverted instead -- badge colour as background,
# plain white text.
#
# background discovery only knows how to read alacritty's config. anything
# else (different terminal, unparseable config, a palette index we can't
# resolve) means "unknown" -> render exactly as before.
#
# usage:
#     . "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline-colour.sh"
#     sl_paint '5;172' '[C]'          # 256-colour index
#     sl_paint '2;255;0;0' '[100%]'   # truecolor
#
# override for tests / other terminals: CLAUDE_STATUSLINE_BG=0x1c1c1c

# minimum WCAG contrast ratio. 4.5 is the AA threshold for body text.
SL_CONTRAST_MIN="${SL_CONTRAST_MIN:-4.5}"

# xterm-256 palette index -> "r g b". indices 0-15 are terminal-defined, so we
# refuse them rather than guess.
_sl_rgb_from_index() {
    local i=$1 r g b v
    if [ "$i" -ge 232 ] && [ "$i" -le 255 ]; then
        v=$(( 8 + (i - 232) * 10 ))
        printf '%d %d %d' "$v" "$v" "$v"
    elif [ "$i" -ge 16 ] && [ "$i" -le 231 ]; then
        i=$(( i - 16 ))
        r=$(( i / 36 )); g=$(( (i % 36) / 6 )); b=$(( i % 6 ))
        [ "$r" -gt 0 ] && r=$(( 55 + 40 * r ))
        [ "$g" -gt 0 ] && g=$(( 55 + 40 * g ))
        [ "$b" -gt 0 ] && b=$(( 55 + 40 * b ))
        printf '%d %d %d' "$r" "$g" "$b"
    else
        return 1
    fi
}

# sgr colour spec (`5;N` or `2;R;G;B`) -> "r g b"
_sl_rgb_from_spec() {
    local spec=$1 r g b
    case "$spec" in
        5\;*)
            case "${spec#5;}" in ''|*[!0-9]*) return 1 ;; esac
            _sl_rgb_from_index "${spec#5;}"
            ;;
        2\;*)
            IFS=';' read -r _ r g b <<<"$spec"
            case "$r$g$b" in ''|*[!0-9]*) return 1 ;; esac
            [ -n "$b" ] || return 1
            printf '%d %d %d' "$r" "$g" "$b"
            ;;
        *) return 1 ;;
    esac
}

# "0x1c1c1c" / "#1c1c1c" / "1c1c1c" -> "28 28 28"
_sl_rgb_from_hex() {
    local h=$1
    h=${h#0x}; h=${h#0X}; h=${h#\#}
    case "$h" in
        [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) ;;
        *) return 1 ;;
    esac
    printf '%d %d %d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
}

# first `background = "0x......"` inside a [colors.primary] table. alacritty
# applies the importing file last, so alacritty.toml beats the local.toml it
# imports -- hence the search order below.
_sl_bg_hex() {
    local dir f hex
    dir="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty"
    for f in "$dir/alacritty.toml" "$dir/local.toml"; do
        [ -f "$f" ] || continue
        hex=$(sed -n '/^\[colors\.primary\]/,/^\[/p' "$f" 2>/dev/null \
            | sed -n 's/^[[:space:]]*background[[:space:]]*=[[:space:]]*["'\'']\{0,1\}\(0[xX]\)\{0,1\}#\{0,1\}\([0-9a-fA-F]\{6\}\).*/\2/p' \
            | sed -n 1p)
        [ -n "$hex" ] && { printf '%s' "$hex"; return 0; }
    done
    return 1
}

# terminal background as "r g b", or non-zero when we can't know it.
_sl_bg_rgb() {
    local hex
    if [ -n "$CLAUDE_STATUSLINE_BG" ]; then
        _sl_rgb_from_hex "$CLAUDE_STATUSLINE_BG"
        return
    fi
    # only alacritty's config describes alacritty's background; under any other
    # terminal reading it would be a lie.
    [ -n "$ALACRITTY_WINDOW_ID" ] || return 1
    hex=$(_sl_bg_hex) || return 1
    _sl_rgb_from_hex "$hex"
}

# WCAG contrast ratio between two rgb triples. exits 0 when it clears
# SL_CONTRAST_MIN, 1 when it doesn't. needs awk for the sRGB gamma curve --
# no awk means no verdict, which callers read as "render normally".
_sl_contrast_ok() {
    command -v awk >/dev/null 2>&1 || return 0
    awk -v fr="$1" -v fg="$2" -v fb="$3" \
        -v br="$4" -v bg="$5" -v bb="$6" \
        -v min="$SL_CONTRAST_MIN" '
        function lin(c) {
            c = c / 255
            return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4
        }
        function lum(r, g, b) {
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        }
        BEGIN {
            l1 = lum(fr, fg, fb); l2 = lum(br, bg, bb)
            if (l2 > l1) { t = l1; l1 = l2; l2 = t }
            exit ((l1 + 0.05) / (l2 + 0.05) >= min) ? 0 : 1
        }'
}

# print `text` in colour `spec`, flipping to inverse video (badge colour as
# background, plain white text) when the two would be too close to read.
sl_paint() {
    local spec=$1 text=$2
    local fr fg fb br bg bb

    read -r fr fg fb <<<"$(_sl_rgb_from_spec "$spec" 2>/dev/null)"
    read -r br bg bb <<<"$(_sl_bg_rgb 2>/dev/null)"

    if [ -n "$fb" ] && [ -n "$bb" ] \
        && ! _sl_contrast_ok "$fr" "$fg" "$fb" "$br" "$bg" "$bb"; then
        printf '\033[48;2;%d;%d;%d;97m%s\033[0m' "$fr" "$fg" "$fb" "$text"
        return 0
    fi

    printf '\033[38;%sm%s\033[0m' "$spec" "$text"
}
