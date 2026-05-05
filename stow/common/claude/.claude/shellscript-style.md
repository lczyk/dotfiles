## shellscript style

### portability

- **match existing repo convention first** if every script in the repo uses `#!/bin/bash`, match that -- don't force dash into a bash project. the default-only kicks in for greenfield scripts or repos with no established pattern.
- **dash-compatible by default** for new scripts with no repo precedent, write to run under `#!/bin/sh` (dash). no bash-isms in portable scripts. when bash is required, use `#!/bin/bash -e` and make it obvious -- don't try to look dash-compatible while using bash features.
- **`[` standard; `[[` bash-only** both fine in bash scripts, but `[[` is a syntax error in dash. default to `[`; reach for `[[` only in `#!/bin/bash` scripts where pattern matching or null-safety justify it.

### structure

- **`#!/bin/bash -e` for bash, `#!/bin/sh -e` for dash** scripts fail on first error. libraries use a source-guard shebang instead (see defer.sh).
- **single entry point** `function main() { ... }; main "$@"` at the bottom. keeps scope explicit, avoids top-level side effects.

### naming

- **`_` prefix for private functions and variables** `_defer_extract()`, `_PATTERNS_TO_RETRY`. signals "internal; don't call from outside this module".
- **`ALL_CAPS` for top-level constants** `_ALL_CAPS` when private. `PATTERNS_TO_RETRY`, `_PATTERNS_TO_RETRY`.

### expressions

- **`local` for all function-local variables** `local defer_cmd="$1"`; `local rootfs="$(mktemp -d)"`. no global leak. `local` suppresses word splitting on the RHS so `local x=$(cmd)` needs no outer quotes.
- **quote all expansions** `"${defer_name}"`, `"$@"`, `"${_PATTERNS_TO_RETRY[@]}"`. no bare `$var`. exception: intentional word splitting with shellcheck annotation (`#shellcheck disable=SC2086`).
- **prefer parameter expansion over external tools** `${defer_cmd%%;}`, `${existing_cmd#'status=$?; '}`, `${test_name:-default}`. avoid `awk`/`sed`/`cut` for string ops the shell can do natively.
- **prefer shell builtins over external tools** only reach for external tools when the shell has no equivalent (`mktemp`, `grep`, `find`). in bash scripts, C-style `for ((i=1; i<=n; i++))` not `seq`.
- **C-style for loops for numeric iteration in bash** `for ((i=0; i<n; i++))`. bash-only, so only in `#!/bin/bash` scripts. cleaner and faster than `seq` or `i=0; while [ $i -lt $n ]; do ... i=$((i+1)); done`.
- **`printf` over `echo`** `printf '%s\n' "${var}"` not `echo "$var"`. `printf` is portable, `echo` varies across shells and interprets backslash sequences unpredictably.
- **never `set -o pipefail`** creates more problems than it solves. check `${PIPESTATUS[0]}` explicitly when pipe exit codes matter, or capture intermediate output.

### output

- **error messages to stderr** `printf "Error: ...\n" >&2`. stdout is for function return values and intentional output; diagnostics go to stderr.

### other

- **list multiple choices in `(...)`** for case patterns, test conditions, array values. groups alternatives visually: `case "$1" in (add|remove|list) ...`, `[ "$mode" = (a|b) ]` (dash-compatible form), `_PATTERNS_TO_RETRY=(...)`.
