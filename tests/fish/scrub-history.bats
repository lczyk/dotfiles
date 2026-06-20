#!/usr/bin/env bats
# tests for stow/common/fish/.config/fish/scrub-rm-rf.sh
# the predicate exits 0 when a command should be scrubbed from history, 1 otherwise.

setup() {
    MATCH="$BATS_TEST_DIRNAME/../../stow/common/fish/.config/fish/scrub-rm-rf.sh"
}

scrub() {  # asserts the command IS scrubbed
    run "$MATCH" "$1"
    [ "$status" -eq 0 ]
}

keep() {   # asserts the command is KEPT
    run "$MATCH" "$1"
    [ "$status" -eq 1 ]
}

# -- combined bundles ---------------------------------------------------

@test "scrubs rm -rf" {
    scrub "rm -rf build"
}

@test "scrubs rm -fr" {
    scrub "rm -fr /tmp/x"
}

@test "scrubs rm -Rf (capital R, force last)" {
    scrub "rm -Rf cap"
}

@test "scrubs rm -fRv (extra flags, interleaved)" {
    scrub "rm -fRv x"
}

@test "scrubs bare rm -rf with no target" {
    scrub "rm -rf"
}

# -- split flags --------------------------------------------------------

@test "scrubs rm -r -f" {
    scrub "rm -r -f sep"
}

@test "scrubs rm -R -f" {
    scrub "rm -R -f cap"
}

# -- long flags ---------------------------------------------------------

@test "scrubs rm --recursive --force" {
    scrub "rm --recursive --force x"
}

# -- pipelines / chains -------------------------------------------------

@test "scrubs rm -rf inside an xargs pipeline" {
    scrub "/bin/ls . | grep -v keep | xargs -r rm -rf"
}

@test "scrubs rm -rf in a ; chain" {
    scrub "cd /tmp; rm -rf junk"
}

# -- kept: not both flags ----------------------------------------------

@test "keeps rm -f alone" {
    keep "rm -f only"
}

@test "keeps rm -r alone" {
    keep "rm -r only"
}

@test "keeps rm -rv (recursive + verbose, no force)" {
    keep "rm -rv verbose-recursive"
}

@test "keeps interactive rm -ri" {
    keep "rm -ri foo"
}

# -- kept: not a bare rm -----------------------------------------------

@test "keeps the word confirm" {
    keep "confirm rm please"
}

@test "keeps a filename ending in .rf" {
    keep "rm file.rf"
}

@test "keeps alarm -refresh (rm is a substring)" {
    keep "alarm -refresh now"
}

@test "keeps an unrelated pipeline with rm -f only" {
    keep "find . -type f | xargs rm -f"
}

# -- edge ---------------------------------------------------------------

@test "keeps empty command" {
    keep ""
}
