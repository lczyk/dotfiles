#!/usr/bin/env bats
# tests for .misc/debx.sh input-validation guards

setup() {
    DEBX="$BATS_TEST_DIRNAME/../../.misc/debx.sh"
    # shellcheck disable=SC1090
    source "$DEBX"
    FORCE=0
}

# -- fatal --------------------------------------------------------------

@test "fatal: exits 1" {
    run bash -c "source '$DEBX'; debx::fatal 'boom'"
    [ "$status" -eq 1 ]
}

@test "fatal: writes msg to stderr" {
    run bash -c "source '$DEBX'; debx::fatal 'boom' 2>&1 1>/dev/null"
    [ "$output" = "boom" ]
}

# -- unpack guards ------------------------------------------------------

@test "unpack: no arg fails" {
    run bash -c "source '$DEBX'; FORCE=0; debx::unpack ''"
    [ "$status" -eq 1 ]
}

@test "unpack: non-.deb extension fails" {
    run bash -c "source '$DEBX'; FORCE=0; debx::unpack foo.txt"
    [ "$status" -eq 1 ]
}

@test "unpack: missing file fails" {
    run bash -c "source '$DEBX'; FORCE=0; debx::unpack /nonexistent/path/foo.deb"
    [ "$status" -eq 1 ]
}

# -- download / info guards ---------------------------------------------

@test "download: no arg fails" {
    run bash -c "source '$DEBX'; debx::download ''"
    [ "$status" -eq 1 ]
}

@test "info: no arg fails" {
    run bash -c "source '$DEBX'; debx::info ''"
    [ "$status" -eq 1 ]
}

# -- main: unknown mode -------------------------------------------------

@test "main: unknown mode fails" {
    run bash -c "source '$DEBX'; MODE=bogus; debx::main ''"
    [ "$status" -eq 1 ]
}
