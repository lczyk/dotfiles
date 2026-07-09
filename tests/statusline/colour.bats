#!/usr/bin/env bats
# tests for stow/common/claude/.claude/statusline-colour.sh

setup() {
    LIB="$BATS_TEST_DIRNAME/../../stow/common/claude/.claude/statusline-colour.sh"
    BADGE_DIR="$BATS_TEST_DIRNAME/../../stow/common/claude/.claude/statusline.d"
    unset ALACRITTY_WINDOW_ID CLAUDE_STATUSLINE_BG
}

# run `sl_paint "$@"` with the given CLAUDE_STATUSLINE_BG (empty = unknown)
paint() {
    local bg=$1; shift
    run env CLAUDE_STATUSLINE_BG="$bg" ALACRITTY_WINDOW_ID= \
        bash -c '. "$1"; shift; sl_paint "$@"' _ "$LIB" "$@"
}

# -- palette resolution

@test "resolves a 256-colour cube index to rgb" {
    run bash -c '. "$1"; _sl_rgb_from_spec "5;39"' _ "$LIB"
    [ "$output" = "0 175 255" ]
}

@test "resolves a 256-colour greyscale index to rgb" {
    run bash -c '. "$1"; _sl_rgb_from_spec "5;235"' _ "$LIB"
    [ "$output" = "38 38 38" ]
}

@test "refuses terminal-defined indices 0-15" {
    run bash -c '. "$1"; _sl_rgb_from_spec "5;7"' _ "$LIB"
    [ "$status" -ne 0 ]
}

@test "resolves a truecolor spec to rgb" {
    run bash -c '. "$1"; _sl_rgb_from_spec "2;12;34;56"' _ "$LIB"
    [ "$output" = "12 34 56" ]
}

@test "rejects a malformed spec" {
    run bash -c '. "$1"; _sl_rgb_from_spec "38;5;39"' _ "$LIB"
    [ "$status" -ne 0 ]
}

# -- hex parsing

@test "parses hex background in 0x, # and bare forms" {
    for form in 0x1c1c1c '#1c1c1c' 1c1c1c; do
        run bash -c '. "$1"; _sl_rgb_from_hex "$2"' _ "$LIB" "$form"
        [ "$output" = "28 28 28" ]
    done
}

@test "rejects a short hex background" {
    run bash -c '. "$1"; _sl_rgb_from_hex "0x1c1"' _ "$LIB"
    [ "$status" -ne 0 ]
}

# -- background discovery

@test "background is unknown outside alacritty" {
    run env -u ALACRITTY_WINDOW_ID -u CLAUDE_STATUSLINE_BG \
        bash -c '. "$1"; _sl_bg_rgb' _ "$LIB"
    [ "$status" -ne 0 ]
}

@test "reads background from alacritty.toml when inside alacritty" {
    mkdir -p "$BATS_TEST_TMPDIR/alacritty"
    cat >"$BATS_TEST_TMPDIR/alacritty/alacritty.toml" <<'TOML'
[colors.normal]
background = "0xff0000"

[colors.primary]
background = "0x1c1c1c"
foreground = "0xddeedd"

[window]
TOML
    run env -u CLAUDE_STATUSLINE_BG XDG_CONFIG_HOME="$BATS_TEST_TMPDIR" \
        ALACRITTY_WINDOW_ID=1 bash -c '. "$1"; _sl_bg_rgb' _ "$LIB"
    [ "$status" -eq 0 ]
    [ "$output" = "28 28 28" ]
}

@test "falls back to local.toml when alacritty.toml has no primary background" {
    mkdir -p "$BATS_TEST_TMPDIR/alacritty"
    printf '[window]\ntitle = "x"\n' >"$BATS_TEST_TMPDIR/alacritty/alacritty.toml"
    printf '[colors.primary]\nbackground = "#ffffff"\n' >"$BATS_TEST_TMPDIR/alacritty/local.toml"
    run env -u CLAUDE_STATUSLINE_BG XDG_CONFIG_HOME="$BATS_TEST_TMPDIR" \
        ALACRITTY_WINDOW_ID=1 bash -c '. "$1"; _sl_bg_rgb' _ "$LIB"
    [ "$output" = "255 255 255" ]
}

@test "background is unknown when alacritty config is missing" {
    run env -u CLAUDE_STATUSLINE_BG XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/nope" \
        ALACRITTY_WINDOW_ID=1 bash -c '. "$1"; _sl_bg_rgb' _ "$LIB"
    [ "$status" -ne 0 ]
}

# -- painting

@test "unknown background renders the plain foreground colour" {
    paint '' '5;39' '[O48]'
    [ "$output" = $'\033[38;5;39m[O48]\033[0m' ]
}

@test "high contrast renders the plain foreground colour" {
    paint 0x1c1c1c '5;39' '[O48]'
    [ "$output" = $'\033[38;5;39m[O48]\033[0m' ]
}

@test "low contrast flips to badge colour on background, white text" {
    paint 0xffffff '5;39' '[O48]'
    [ "$output" = $'\033[48;2;0;175;255;97m[O48]\033[0m' ]
}

@test "flipped badge is not bold" {
    paint 0xffffff '5;139' '[x]'
    [[ "$output" != *$'\033[1;'* ]]
}

@test "dark red on a dark background flips" {
    paint 0x1c1c1c '5;196' '[ctx 90%]'
    [[ "$output" == $'\033[48;2;255;0;0;97m'* ]]
}

@test "truecolor spec flips too" {
    paint 0xffffff '2;255;255;0' '[50%]'
    [ "$output" = $'\033[48;2;255;255;0;97m[50%]\033[0m' ]
}

@test "an unresolvable palette index renders plainly" {
    paint 0xffffff '5;7' '[x]'
    [ "$output" = $'\033[38;5;7m[x]\033[0m' ]
}

@test "an unparseable background renders plainly" {
    paint 'not-a-colour' '5;39' '[O48]'
    [ "$output" = $'\033[38;5;39m[O48]\033[0m' ]
}

@test "SL_CONTRAST_MIN tunes the threshold" {
    run env CLAUDE_STATUSLINE_BG=0x1c1c1c ALACRITTY_WINDOW_ID= SL_CONTRAST_MIN=21 \
        bash -c '. "$1"; sl_paint "5;39" "[O48]"' _ "$LIB"
    [[ "$output" == $'\033[48;2;'* ]]
}

# -- badge integration

@test "fable badge ignores the background entirely" {
    run env CLAUDE_STATUSLINE_BG=0x1c1c1c bash -c \
        "echo '{\"model\":{\"display_name\":\"Fable 5\"}}' | '$BADGE_DIR/20-model.sh'"
    [ "$output" = $'\033[1;97;48;5;196m[F5]\033[0m' ]
}

@test "model badge flips on a light background" {
    run env CLAUDE_STATUSLINE_BG=0xffffff bash -c \
        "echo '{\"model\":{\"display_name\":\"Opus 4.8\"}}' | '$BADGE_DIR/20-model.sh'"
    [ "$output" = $'\033[48;2;0;175;255;97m[O48]\033[0m' ]
}

@test "context badge flips on a light background" {
    run env CLAUDE_STATUSLINE_BG=0xffffff bash -c \
        "echo '{\"context_window\":{\"used_percentage\":10}}' | '$BADGE_DIR/30-context.sh'"
    [ "$output" = $'\033[48;2;95;175;95;97m[ctx 10%]\033[0m' ]
}
