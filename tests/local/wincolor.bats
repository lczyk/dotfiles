#!/usr/bin/env bats
# tests for stow/common/local/.local/bin/wincolor. alacritty is replaced by a
# shim that logs its argv, keeps a per-window background and answers
# get-config from it. FAIL_TIMES makes the first n calls die with epipe;
# DROP_TIMES makes the first n config calls succeed without applying.

setup() {
    WINCOLOR="$BATS_TEST_DIRNAME/../../stow/common/local/.local/bin/wincolor"
    SHIMDIR="$BATS_TEST_TMPDIR/bin"
    export LOG="$BATS_TEST_TMPDIR/alacritty.log"
    export BGDIR="$BATS_TEST_TMPDIR/bg"
    mkdir -p "$SHIMDIR" "$BGDIR"
    cat > "$SHIMDIR/alacritty" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LOG"
if [ -n "$FAIL_TIMES" ] && [ "$(wc -l < "$LOG")" -le "$FAIL_TIMES" ]; then
    echo "${FAIL_MSG:-Error: Os { code: 32, kind: BrokenPipe, message: \"Broken pipe\" }}" >&2
    exit 1
fi
case $2 in
    (config)
        if [ -n "$DROP_TIMES" ] && [ "$(grep -c '^msg config ' "$LOG")" -le "$DROP_TIMES" ]; then
            exit 0
        fi
        if [ "$5" = --reset ]; then
            rm -f "$BGDIR/$4"
        else
            for opt in "${@:5}"; do
                case $opt in (colors.primary.background=*)
                    v=${opt#*=}
                    printf '%s' "${v//\"/}" > "$BGDIR/$4" ;;
                esac
            done
        fi ;;
    (get-config)
        bg='#1c1c1c'
        [ -f "$BGDIR/$4" ] && bg=$(cat "$BGDIR/$4")
        printf '{"colors":{"primary":{"foreground":"#ddeedd","background":"%s"}}}\n' "$bg" ;;
esac
SHIM
    chmod +x "$SHIMDIR/alacritty"
    export PATH="$SHIMDIR:$PATH"
    export ALACRITTY_WINDOW_ID=42
    BG="$BGDIR/42"
    # what conf.d/20_palette.fish exports (fish joins lists with spaces)
    export PALETTE_LIGHT_BG=e3e3e3 PALETTE_LIGHT_FG=3c3836
    export PALETTE_LIGHT_NORMAL='a89984 cc241d 98971a d79921 458588 b16286 689d6a 504945'
    export PALETTE_LIGHT_BRIGHT='928374 9d0006 79740e b57614 076678 8f3f71 427b58 282828'
}

last_config_call() { grep '^msg config ' "$LOG" | sed -n '$p'; }

@test "list prints every colour with its hex" {
    run "$WINCOLOR" list
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 8 ]
    [[ "$output" == *"[b]lue"*"#0072bd"* ]]
    [[ "$output" == *"[o]range"*"#e95420"* ]]
    [[ "$output" == *"[a]ubergine"*"#772953"* ]]
    [[ "$output" == *"[l]ight"*"#e3e3e3"* ]]
}

@test "list needs no window" {
    unset ALACRITTY_WINDOW_ID
    run "$WINCOLOR" list
    [ "$status" -eq 0 ]
}

@test "refuses outside alacritty" {
    unset ALACRITTY_WINDOW_ID
    run "$WINCOLOR" blue
    [ "$status" -eq 1 ]
    [[ "$output" == *"not inside an alacritty window"* ]]
    [ ! -e "$LOG" ]
}

@test "named colour sets the background" {
    run "$WINCOLOR" blue
    [ "$status" -eq 0 ]
    [ "$(last_config_call)" = 'msg config -w 42 colors.primary.background="#0072bd"' ]
    [ "$(cat "$BG")" = '#0072bd' ]
}

@test "light also swaps the text palette" {
    run "$WINCOLOR" l
    [ "$status" -eq 0 ]
    call=$(last_config_call)
    [[ "$call" == 'msg config -w 42 colors.primary.background="#e3e3e3" colors.primary.foreground="#3c3836" '* ]]
    [[ "$call" == *' colors.normal.red="#cc241d" '* ]]
    [[ "$call" == *' colors.bright.white="#282828"' ]]
    [ "$(grep -o 'colors\.\(normal\|bright\)\.[a-z]*=' <<< "$call" | wc -l)" -eq 16 ]
    [ "$(cat "$BG")" = '#e3e3e3' ]
    run "$WINCOLOR" light
    [ "$(last_config_call)" = 'msg config -w 42 --reset' ]
}

@test "same colour twice untoggles" {
    "$WINCOLOR" blue
    run "$WINCOLOR" blue
    [ "$status" -eq 0 ]
    [ "$(last_config_call)" = 'msg config -w 42 --reset' ]
    [ ! -e "$BG" ]
}

@test "different colour switches" {
    "$WINCOLOR" blue
    run "$WINCOLOR" red
    [ "$status" -eq 0 ]
    [ "$(cat "$BG")" = '#a2142f' ]
}

@test "unique prefix selects a colour" {
    run "$WINCOLOR" a
    [ "$status" -eq 0 ]
    [ "$(cat "$BG")" = '#772953' ]
    run "$WINCOLOR" gr
    [ "$(cat "$BG")" = '#77ac30' ]
}

@test "unknown colour fails without touching alacritty" {
    run "$WINCOLOR" mauve
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown colour 'mauve'"* ]]
    [ ! -e "$LOG" ]
}

@test "orange, yellow and cyan get the light text palette, blue does not" {
    for c in orange yellow cyan; do
        "$WINCOLOR" "$c"
        [[ "$(last_config_call)" == *' colors.primary.foreground="#3c3836" '* ]]
    done
    "$WINCOLOR" blue
    [ "$(last_config_call)" = 'msg config -w 42 colors.primary.background="#0072bd"' ]
}

@test "light needs the palette from fish" {
    unset PALETTE_LIGHT_NORMAL
    run "$WINCOLOR" light
    [ "$status" -eq 1 ]
    [[ "$output" == *"PALETTE_LIGHT_"* ]]
    ! grep -q '^msg config ' "$LOG"
}

@test "no argument picks a random palette colour, never light" {
    for _ in $(seq 40); do
        "$WINCOLOR"
        [[ " #0072bd #e95420 #edb120 #772953 #77ac30 #4dbeee #a2142f " == *" $(cat "$BG") "* ]]
        "$WINCOLOR" off
    done
}

@test "no argument on a coloured window untoggles" {
    "$WINCOLOR" green
    run "$WINCOLOR"
    [ "$status" -eq 0 ]
    [ "$(last_config_call)" = 'msg config -w 42 --reset' ]
    [ ! -e "$BG" ]
}

@test "a background set by someone else still counts as coloured" {
    printf '#123456' > "$BG"
    run "$WINCOLOR"
    [ "$status" -eq 0 ]
    [ "$(last_config_call)" = 'msg config -w 42 --reset' ]
}

@test "off resets even when not coloured" {
    run "$WINCOLOR" off
    [ "$status" -eq 0 ]
    [ "$(last_config_call)" = 'msg config -w 42 --reset' ]
}

@test "windows are independent" {
    "$WINCOLOR" blue
    ALACRITTY_WINDOW_ID=7 run "$WINCOLOR" blue
    [ "$status" -eq 0 ]
    [ "$(cat "$BG")" = '#0072bd' ]
    [ "$(cat "$BGDIR/7")" = '#0072bd' ]
}

@test "retries after a dropped connection" {
    FAIL_TIMES=2 run "$WINCOLOR" blue
    [ "$status" -eq 0 ]
    [[ "$output" != *"Broken pipe"* ]]
    [ "$(cat "$BG")" = '#0072bd' ]
    FAIL_MSG='Error: Os { code: 57, kind: NotConnected, message: "Socket is not connected" }' \
        FAIL_TIMES=4 run "$WINCOLOR" red
    [ "$status" -eq 0 ]
    [ "$(cat "$BG")" = '#a2142f' ]
}

@test "resends a change alacritty silently dropped" {
    DROP_TIMES=2 run "$WINCOLOR" blue
    [ "$status" -eq 0 ]
    [ "$(grep -c '^msg config ' "$LOG")" -eq 3 ]
    [ "$(cat "$BG")" = '#0072bd' ]
    DROP_TIMES=1 run "$WINCOLOR" off
    [ "$status" -eq 0 ]
    [ ! -e "$BG" ]
}

@test "gives up on other errors" {
    rm "$SHIMDIR/alacritty"
    printf '#!/bin/sh\necho "Error: no socket found" >&2\nexit 1\n' > "$SHIMDIR/alacritty"
    chmod +x "$SHIMDIR/alacritty"
    run "$WINCOLOR" blue
    [ "$status" -eq 1 ]
    [[ "$output" == *"no socket found"* ]]
}
