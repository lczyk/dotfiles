## shellscript style

### portability

- **match the repo first** if every script in the repo uses `#!/bin/bash`, match it. the defaults below are for greenfield scripts or repos with no pattern.
- **dash-compatible by default** new scripts target `#!/bin/sh -e` (dash), no bash-isms. when bash is genuinely needed, be open about it: `#!/usr/bin/env bash` (finds bash in `$PATH`) plus a `set -e` line -- never `#!/usr/bin/env bash -e`, linux `env` can't split that. don't half-pretend to be dash-compatible.
- **bash-only features stay in bash scripts** arrays, the `function` keyword, `[[`, `(( ))` and C-style `for`, `PIPESTATUS`, `set -o pipefail`. default to `[`; `[[` only where pattern matching or null-safety justify it.
- **skip `-e`** only when a `_fail`-style helper handles errors and calls `exit` directly. libraries use a source-guard shebang instead.

### structure

- **3-layer layout for utility scripts** config vars set once -> `_`-prefixed private helpers -> `main` -> `main "$@"` at the bottom:
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
- **all functions at module scope** never nest a definition -- it gets redefined on every outer call and its scope turns murky. helpers go top level, not inside `main`.
- **flat is fine for tests and one-shot tasks** the layout above is for reusable library / utility scripts.
- **4-space indent** throughout, no mixing.

### naming

- **`_` prefix for private** functions and vars: `_fail()`, `_TO_INSTALL`.
- **`ALL_CAPS` for top-level constants and config** (`_ALL_CAPS` when private), effectively read-only once `main` starts.

### expressions

- **`local` for every function variable** no global leaks. `local x=$(cmd)` needs no quotes (no word splitting in bash or dash), but it masks `cmd`'s exit status under `-e` -- write `local x; x=$(cmd)` when the status matters.
- **quote every expansion** `"${name}"`, `"$@"`, `"${_TO_INSTALL[@]}"`. exception: intentional splitting with `# shellcheck disable=SC2086`.
- **builtins and parameter expansion over external tools** `${cmd%%;}`, `${name:-default}` instead of `awk` / `sed` / `cut`; external tools only when the shell has no equivalent (`mktemp`, `grep`, `find`). in bash, numeric loops are `for ((i=0; i<n; i++))`, not `seq` or a `while` counter.
- **`printf` over `echo`** `printf '%s\n' "${var}"`; `echo` varies across shells and mangles backslashes.
- **never `set -o pipefail`** check `${PIPESTATUS[0]}` when a pipe's exit codes matter (bash-only; in dash, capture intermediate output and check each stage).
- **`grep -q` for test assertions** `cmd | grep -q "expected"`; `-F` for literal strings; `-i` unless it weakens the test.
- **arrays for reused lists, `\` for one-shot** `slices=(a b c); cmd "${slices[@]}"` when the list is used more than once; `\` continuations for a single long command.

### output

- **diagnostics to stderr** `printf 'error: ...\n' >&2`; stdout is for return values and intended output.

### other

- **alternatives in `(...)`** case patterns and array values: `case "$1" in (add|remove|list) ...`, `_TO_INSTALL=(...)`.
- **`-n` / `--dry-run` for dry runs** any script with outward-facing or hard-to-undo side effects (push, PR creation, delete, deploy, remote writes) takes both spellings and prints what it _would_ do without touching anything. parse it in `main` with the same `case` that handles `-h`/`--help`, and exit non-zero on an unknown argument. an env var (`DRY_RUN=1`) may back it, but the flag is the interface.
