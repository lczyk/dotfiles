#!/usr/bin/env bats
# tests for stow/common/local/.local/bin/wincolor. alacritty is replaced by a
# shim that logs its argv, keeps a per-window background and answers
# get-config from it. FAIL_TIMES makes the first n calls die with epipe.

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
        if [ "$5" = --reset ]; then
            rm -f "$BGDIR/$4"
        else
            v=${5#*=}
            printf '%s' "${v//\"/}" > "$BGDIR/$4"
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
}

last_config_call() { grep '^msg config ' "$LOG" | sed -n '$p'; }

@test "list prints every colour with its hex" {
    run "$WINCOLOR" list
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 7 ]
    [[ "$output" == *"[b]lue"*"#0072bd"* ]]
    [[ "$output" == *"[o]range"*"#e95420"* ]]
    [[ "$output" == *"[a]ubergine"*"#772953"* ]]
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

@test "no argument picks a random palette colour" {
    run "$WINCOLOR"
    [ "$status" -eq 0 ]
    [[ " #0072bd #e95420 #edb120 #772953 #77ac30 #4dbeee #a2142f " == *" $(cat "$BG") "* ]]
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

@test "gives up on other errors" {
    rm "$SHIMDIR/alacritty"
    printf '#!/bin/sh\necho "Error: no socket found" >&2\nexit 1\n' > "$SHIMDIR/alacritty"
    chmod +x "$SHIMDIR/alacritty"
    run "$WINCOLOR" blue
    [ "$status" -eq 1 ]
    [[ "$output" == *"no socket found"* ]]
}
