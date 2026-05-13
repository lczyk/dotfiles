#!/usr/bin/env bats
# tests for .misc/debx.sh debx_tree -- uses real tree/ls on host

setup() {
    DEBX="$BATS_TEST_DIRNAME/../../.misc/debx.sh"
    # shellcheck disable=SC1090
    source "$DEBX"
    DIR="$BATS_TEST_TMPDIR/sample"
    mkdir -p "$DIR/sub"
    touch "$DIR/a" "$DIR/sub/b"
}

@test "debx_tree: succeeds on real dir" {
    run debx::debx_tree "$DIR"
    [ "$status" -eq 0 ]
}

@test "debx_tree: output mentions files" {
    run debx::debx_tree "$DIR"
    [[ "$output" == *"a"* ]]
    [[ "$output" == *"b"* ]]
}
