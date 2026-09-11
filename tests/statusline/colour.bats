#!/usr/bin/env bats
# tests for stow/common/claude/.claude/statusline-colour.sh

setup() {
    LIB="$BATS_TEST_DIRNAME/../../stow/common/claude/.claude/statusline-colour.sh"
    BADGE_DIR="$BATS_TEST_DIRNAME/../../stow/common/claude/.claude/statusline.d"
}

@test "paints with a bare sgr colour code" {
    run bash -c '. "$1"; sl_paint 33 "[C]"' _ "$LIB"
    [ "$output" = $'\033[33m[C]\033[0m' ]
}

@test "named colours are the 16 palette slots" {
    run bash -c '. "$1"; printf "%s %s %s %s" "$SL_RED" "$SL_WHITE" "$SL_BRED" "$SL_BWHITE"' _ "$LIB"
    [ "$output" = "31 37 91 97" ]
}

@test "no badge emits 256-colour or truecolor sequences" {
    ! grep -rE '38;5|38;2|48;5|48;2' "$BADGE_DIR"
}

@test "fable 5 badge is bold bright-white on palette red" {
    run bash -c "echo '{\"model\":{\"display_name\":\"Fable 5\"}}' | '$BADGE_DIR/20-model.sh'"
    [ "$output" = $'\033[1;97;41m[F5]\033[0m' ]
}
