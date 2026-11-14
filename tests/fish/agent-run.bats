#!/usr/bin/env bats
# tests for stow/common/fish/.config/fish/conf.d/09_agent_run.fish

setup() {
    CONFD="$BATS_TEST_DIRNAME/../../stow/common/fish/.config/fish/conf.d"
    FISH=$(command -v fish)
    JQ_DIR=$(dirname "$(command -v jq)")
    BIN="$BATS_TEST_TMPDIR/bin"
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$BIN" "$WORK"
    cat > "$BIN/fake" <<'EOF'
#!/usr/bin/env bash
printf 'claim=%s\n' "$AGENT_CLAIM"
printf 'pid=%s\n' "$$"
printf 'FOO=%s\n' "$FOO"
printf 'argv=%s\n' "$*"
[ -n "$AGENT_CLAIM" ] && jq -c . "$AGENT_CLAIM"
exit "${FAKE_STATUS:-0}"
EOF
    chmod +x "$BIN/fake"
}

_run_fish() {
    run env HOME="$BATS_TEST_TMPDIR/home" PATH="$BIN:$JQ_DIR:/usr/bin:/bin" \
        "$FISH" --no-config --command "cd $WORK; source $CONFD/09_agent_run.fish; $1"
}

@test "claim names the harness pid and is removed after exit" {
    _run_fish "__agent_run fake fake --x 'a b'"
    [ "$status" -eq 0 ]
    local pid
    pid=$(printf '%s\n' "$output" | sed -n 's/^pid=//p')
    [[ "$output" == *"claim=$WORK/.agents/sessions/fake-$pid.json"* ]]
    [[ "$output" == *"argv=--x a b"* ]]
    [[ "$output" == *"\"harness\":\"fake\",\"pid\":$pid,\"root\":\"$WORK\""* ]]
    [ -z "$(ls -A "$WORK/.agents/sessions")" ]
}

@test "env assignments before the command reach the harness" {
    _run_fish "__agent_run fake FOO=bar fake"
    [ "$status" -eq 0 ]
    [[ "$output" == *"FOO=bar"* ]]
}

@test "exit status is forwarded" {
    _run_fish "__agent_run fake FAKE_STATUS=3 fake; echo st=\$status"
    [[ "$output" == *"st=3"* ]]
}

@test "inside a git repo the claim sits at the toplevel" {
    git -C "$WORK" init -q -b trunk
    mkdir -p "$WORK/sub"
    _run_fish "cd sub; __agent_run fake fake"
    [ "$status" -eq 0 ]
    [[ "$output" == *"claim=$WORK/.agents/sessions/fake-"* ]]
    [[ "$output" == *"\"cwd\":\"$WORK/sub\",\"branch\":\"trunk\""* ]]
}

@test "live claims are reported and dead ones pruned" {
    mkdir -p "$WORK/.agents/sessions"
    sleep 30 &
    local live=$!
    printf '{"harness":"other","pid":%s,"branch":"main","started":"t0"}\n' "$live" \
        > "$WORK/.agents/sessions/other-$live.json"
    printf '{"harness":"gone","pid":999999,"branch":"main","started":"t0"}\n' \
        > "$WORK/.agents/sessions/gone-999999.json"
    _run_fish "__agent_run fake fake"
    kill "$live"
    [ "$status" -eq 0 ]
    [[ "$output" == *"agent: other sessions in $WORK"* ]]
    [[ "$output" == *"other pid $live on main since t0"* ]]
    [[ "$output" != *"gone"* ]]
    [ ! -e "$WORK/.agents/sessions/gone-999999.json" ]
    [ -e "$WORK/.agents/sessions/other-$live.json" ]
}

@test "unwritable root still runs the harness, without a claim" {
    chmod a-w "$WORK"
    _run_fish "__agent_run fake fake"
    chmod u+w "$WORK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"claim="$'\n'* ]]
}

@test "harness shims go through the claim" {
    local t
    for t in claude codex copilot hax kimi opencode; do
        cp "$BIN/fake" "$BIN/$t"
        run env HOME="$BATS_TEST_TMPDIR/home" PATH="$BIN:$JQ_DIR:/usr/bin:/bin" "$FISH" --no-config --command \
            "cd $WORK; source $CONFD/09_agent_run.fish; source $CONFD/10_$t.fish; $t hi"
        [ "$status" -eq 0 ]
        [[ "$output" == *"claim=$WORK/.agents/sessions/$t-"* ]]
        [[ "$output" == *"argv=hi"* ]]
    done
}
