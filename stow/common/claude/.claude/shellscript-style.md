## shellscript style

### portability

- **match existing repo convention first** if every script in the repo uses `#!/bin/bash`, match that -- don't force dash into a bash project. the default-only kicks in for greenfield scripts or repos with no established pattern.
- **dash-compatible by default** for new scripts with no repo precedent, write to run under `#!/bin/sh` (dash). no bash-isms in portable scripts. when bash is required, use `#!/usr/bin/env bash` with `-e` and make it obvious -- don't try to look dash-compatible while using bash features.
- **`#!/usr/bin/env bash` over `#!/bin/bash`** `env` finds bash in `$PATH`; more portable across systems. `-e` (errexit) is the norm for scripts that should fail on first error.
- **`[` standard; `[[` bash-only** both fine in bash scripts, but `[[` is a syntax error in dash. default to `[`; reach for `[[` only in `#!/bin/bash` scripts where pattern matching or null-safety justify it.

### structure

- **`#!/usr/bin/env bash` with `-e` for bash, `#!/bin/sh -e` for dash** scripts fail on first error. libraries use a source-guard shebang instead (see defer.sh). skip `-e` when error handling is manual via a `_fail`-style helper that calls `exit` directly.
- **3-layer layout for utility scripts** top-level configuration, then top-level private helpers, then `main`:
    ```bash
    #!/usr/bin/env bash

    # top-level configuration (ALL_CAPS, set once before main)
    LABEL="warning"
    FAIL=0

    # top-level private helpers (_prefix)
    function _fail() { printf '%s: %s\n' "$LABEL" "$1" >&2; shift; ...; exit $FAIL; }

    # main entry point
    function main() { local msg="$1"; ...; exit 0; }

    main "$@"
    ```
    three layers: config vars set once -> `_`-prefixed helpers at module scope -> `main` entry point -> `main "$@"` at the bottom. helpers go at top level, not nested inside `main` -- they are not redefined on every call.
- **consistent indentation throughout** pick 4 spaces and stick with it. no mixing 2-space and 4-space within a file.
- **never nest function definitions** define all functions at module scope (top level). nesting a function inside another redefines it on every outer call and makes the inner function's scope unclear. private helpers with `_` prefix go at the top level, not inside `main`.
- **flat scripts are idiomatic for tests and simple tasks** not everything needs `main` and functions. test scripts that execute top-to-bottom are fine. the structure rules above are for reusable library/utility scripts, not one-shot test files.

### naming

- **`_` prefix for private functions and variables** `_defer_extract()`, `_fail()`, `_TO_INSTALL`. signals "internal; don't call from outside this module".
- **`ALL_CAPS` for top-level constants and configuration** `_ALL_CAPS` when private. configuration vars set once before `main()` also use `ALL_CAPS` (e.g. `LABEL`, `FAIL`) -- they are effectively read-only once `main` starts.

### expressions

- **`local` for all function-local variables** `local defer_cmd="$1"`; `local rootfs="$(mktemp -d)"`. no global leak. `local` suppresses word splitting on the RHS so `local x=$(cmd)` needs no outer quotes.
- **quote all expansions** `"${defer_name}"`, `"$@"`, `"${_TO_INSTALL[@]}"`. no bare `$var`. exception: intentional word splitting with shellcheck annotation (`#shellcheck disable=SC2086`).
- **prefer parameter expansion over external tools** `${defer_cmd%%;}`, `${existing_cmd#'status=$?; '}`, `${test_name:-default}`. avoid `awk`/`sed`/`cut` for string ops the shell can do natively.
- **prefer shell builtins over external tools** only reach for external tools when the shell has no equivalent (`mktemp`, `grep`, `find`). in bash scripts, C-style `for ((i=1; i<=n; i++))` not `seq`.
- **C-style for loops for numeric iteration in bash** `for ((i=0; i<n; i++))`. bash-only, so only in `#!/bin/bash` scripts. cleaner and faster than `seq` or `i=0; while [ $i -lt $n ]; do ... i=$((i+1)); done`.
- **`printf` over `echo`** `printf '%s\n' "${var}"` not `echo "$var"`. `printf` is portable, `echo` varies across shells and interprets backslash sequences unpredictably.
- **never `set -o pipefail`** creates more problems than it solves. check `${PIPESTATUS[0]}` explicitly when pipe exit codes matter, or capture intermediate output.
- **`grep -q` for test assertions** `cmd | grep -q "expected"` is the standard assertion pattern. use `-F` when matching a literal string (not a regex). prefer `-i` for case-insensitive tests unless it weakens the test.
- **array for reusable lists, `\` continuations for one-shot** build argument lists in arrays when the same list is used multiple times: `slices=(a b c); cmd "${slices[@]}"`. for one-shot long commands, use `\` continuations instead.

### output

- **error messages to stderr** `printf "Error: ...\n" >&2`. stdout is for function return values and intentional output; diagnostics go to stderr.

### other

- **list multiple choices in `(...)`** for case patterns, test conditions, array values. groups alternatives visually: `case "$1" in (add|remove|list) ...`, `[ "$mode" = (a|b) ]` (dash-compatible form), `_TO_INSTALL=(...)`.
