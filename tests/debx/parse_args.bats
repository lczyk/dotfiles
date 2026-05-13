#!/usr/bin/env bats
# tests for .misc/debx.sh parse_args -- pure flag/mode parsing

setup() {
    DEBX="$BATS_TEST_DIRNAME/../../.misc/debx.sh"
    # shellcheck disable=SC1090
    source "$DEBX"
}

# -- mode parsing -------------------------------------------------------

@test "default mode is unpack" {
    debx::parse_args
    [ "$MODE" = "unpack" ]
}

@test "install: -I" {
    debx::parse_args -I
    [ "$MODE" = "install" ]
}

@test "install: --install" {
    debx::parse_args --install
    [ "$MODE" = "install" ]
}

@test "install: I" {
    debx::parse_args I
    [ "$MODE" = "install" ]
}

@test "install: install" {
    debx::parse_args install
    [ "$MODE" = "install" ]
}

@test "download: d" {
    debx::parse_args d
    [ "$MODE" = "download" ]
}

@test "download: D" {
    debx::parse_args D
    [ "$MODE" = "download" ]
}

@test "download: --download" {
    debx::parse_args --download
    [ "$MODE" = "download" ]
}

@test "download: download" {
    debx::parse_args download
    [ "$MODE" = "download" ]
}

@test "info: i" {
    debx::parse_args i
    [ "$MODE" = "info" ]
}

@test "info: --info" {
    debx::parse_args --info
    [ "$MODE" = "info" ]
}

@test "info: info" {
    debx::parse_args info
    [ "$MODE" = "info" ]
}

@test "unpack: U" {
    debx::parse_args U
    [ "$MODE" = "unpack" ]
}

@test "unpack: --unpack" {
    debx::parse_args --unpack
    [ "$MODE" = "unpack" ]
}

@test "unpack: unpack" {
    debx::parse_args unpack
    [ "$MODE" = "unpack" ]
}

# -- flags --------------------------------------------------------------

@test "FORCE default 0" {
    FORCE=0
    debx::parse_args unpack
    [ "$FORCE" -eq 0 ]
}

@test "-f sets FORCE=1" {
    FORCE=0
    debx::parse_args unpack -f
    [ "$FORCE" -eq 1 ]
}

@test "--force sets FORCE=1" {
    FORCE=0
    debx::parse_args unpack --force
    [ "$FORCE" -eq 1 ]
}

# -- positional capture -------------------------------------------------

@test "captures single positional arg into ARGS" {
    debx::parse_args unpack foo.deb
    [ "${ARGS[0]}" = "foo.deb" ]
}

@test "captures positional after flag" {
    debx::parse_args unpack -f foo.deb
    [ "$FORCE" -eq 1 ]
    [ "${ARGS[0]}" = "foo.deb" ]
}

@test "no mode + positional defaults to unpack" {
    debx::parse_args foo.deb
    [ "$MODE" = "unpack" ]
    [ "${ARGS[0]}" = "foo.deb" ]
}

@test "captures multiple positional args" {
    debx::parse_args unpack a.deb b.deb
    [ "${ARGS[0]}" = "a.deb" ]
    [ "${ARGS[1]}" = "b.deb" ]
}
