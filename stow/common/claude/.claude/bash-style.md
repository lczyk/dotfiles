## bash style

- **`_` prefix for private functions and variables** `_defer_extract()`, `_PATTERNS_TO_RETRY`. signals "internal; don't call from outside this module".
- **`local` for all function-local variables** `local defer_cmd="$1"`; `local rootfs="$(mktemp -d)"`. no global leak. `local` suppresses word splitting on the RHS so `local x=$(cmd)` needs no outer quotes.
- **quote all expansions** `"${defer_name}"`, `"$@"`, `"${_PATTERNS_TO_RETRY[@]}"`. no bare `$var`. exception: intentional word splitting with shellcheck annotation (`#shellcheck disable=SC2086`).
- **prefer parameter expansion over external tools** `${defer_cmd%%;}`, `${existing_cmd#'status=$?; '}`, `${test_name:-default}`. avoid `awk`/`sed`/`cut` for string ops bash can do natively.
- **prefer pure-bash over external tools** C-style `for ((i=1; i<=n; i++))` not `seq`. `[[` not `[` (bash builtin, safer). only reach for external tools when bash has no equivalent (`mktemp`, `grep`, `find`).
- **`printf` over `echo`** `printf '%s\n' "${var}"` not `echo "$var"`. `printf` is portable, `echo` varies across shells and interprets backslash sequences unpredictably.
- **error messages to stderr** `printf "Error: ...\n" >&2` / `echo "Warning: ..." >&2`. stdout is for function return values and intentional output; diagnostics go to stderr.
