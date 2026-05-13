#!/usr/bin/env bats
# tests for .misc/debx.sh help / version output

setup() {
    DEBX="$BATS_TEST_DIRNAME/../../.misc/debx.sh"
}

@test "-h exits 0" {
    run bash "$DEBX" -h
    [ "$status" -eq 0 ]
}

@test "--help exits 0" {
    run bash "$DEBX" --help
    [ "$status" -eq 0 ]
}

@test "-h prints usage" {
    run bash "$DEBX" -h
    [[ "$output" == *"Usage:"* ]]
}

@test "-h lists all modes" {
    run bash "$DEBX" -h
    [[ "$output" == *"Install"* ]]
    [[ "$output" == *"Download"* ]]
    [[ "$output" == *"Info"* ]]
    [[ "$output" == *"Unpack"* ]]
}

@test "-v exits 0" {
    run bash "$DEBX" -v
    [ "$status" -eq 0 ]
}

@test "--version exits 0" {
    run bash "$DEBX" --version
    [ "$status" -eq 0 ]
}

@test "-v prints version string" {
    run bash "$DEBX" -v
    [[ "$output" == *"version"* ]]
    [[ "$output" == *"0.3."* ]]
}
