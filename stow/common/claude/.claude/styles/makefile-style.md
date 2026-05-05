## makefile style

iff a repo has no automation and the user has explicitly asked to add some, prefer a `makefile` (lowercase filename -- both `make` and the user prefer it; some of the user's older repos still use `Makefile`, leave those alone). style:

- **`.SUFFIXES:` at the top** disables built-in implicit rules; everything in the makefile is then explicit.
- **`help` is the default target** sits first, prints all public targets. self-documenting via a trailing `## description` on each public target rule, rendered with a `grep` + `awk` one-liner. internal targets (helpers, intermediate steps) omit the `## ` so they don't show up.
- **`.PHONY:` per target, inline** declare `.PHONY: foo` on the line directly above the `foo:` rule, not batched at the top of the file. keeps the declaration next to the thing it describes.
- **file targets list real deps** rules that produce a file (e.g. `./bin/foo:`) name every input that should trigger a rebuild -- source globs, the `makefile` itself, package/lockfiles (`go.mod`, `go.sum`, `package-lock.json`, `uv.lock`). including the `makefile` and the package files means a change to the build recipe or to declared deps invalidates the cached artefact, just like a source-file edit would.
- **`mkdir -p` before writes** any rule that produces a file in a directory creates the directory first.
- **optional tools are soft** wrap with `command -v <tool> >/dev/null 2>&1` and either fall back (e.g. `gotest` -> `go test`) or skip with a message. don't hard-fail on a missing nice-to-have.
- **overridable knobs use `$(or $(VAR),<default>)`** lets the caller pass `BENCH=...` / `PKG=...` w/out touching the makefile, with a sensible default baked in.
- **aggregate gate target** a `verify` (or similar) target that chains `lint test spellcheck ...` -- one entry point for "is this commit healthy".
- **internal targets skip the `## ` doc** only public, user-invokable targets get the trailing `## description`. helpers and intermediate file rules stay undocumented so they don't clutter `make help`.
- **kebab-case target names** `cover-open`, `generate-version`, not `cover_open` or `coverOpen`.
