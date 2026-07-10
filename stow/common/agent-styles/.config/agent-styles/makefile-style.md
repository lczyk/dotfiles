## makefile style

iff a repo has no automation and the user has explicitly asked to add some, prefer a `makefile` (lowercase filename -- both `make` and the user prefer it; some of the user's older repos still use `Makefile`, leave those alone). style:

- **`.SUFFIXES:` at the top** disables built-in implicit rules; everything in the makefile is then explicit.
- **`help` is the default target** sits first (before the first `##@` section, so it renders ungrouped), prints all public targets. canonical recipe -- use it verbatim, adjust only the `%-14s` column width:

    ```make
    help:  ## Show this help
    	@awk 'BEGIN {FS = ":.*?## "} /^##@/ {printf "\n\033[1m%s\033[0m\n", substr($$0, 5)} /^[a-zA-Z_.\/-]+:.*?## / {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
    ```

- **`##@ <section>` headers group the help output** e.g. `##@ checks`, `##@ build`, `##@ images`. a couple of sections is plenty; skip them entirely in a makefile with ~5 targets.
- **self-documenting via trailing `## <description>`** on each public target rule, two spaces before the `##`. descriptions are sentence case starting with a verb (`## Build the wheel into dist/`) -- an exception to the lowercase-prose rule, matching existing makefiles. mention the narrowing knobs where they exist (`## Build sandbox images (narrow via VER=.. ARCH=..)`).
- **internal targets skip the `## ` doc** only public, user-invokable targets get one. helpers, file rules and intermediate steps stay undocumented so they don't clutter `make help`.
- **`.PHONY:` per target, inline** declare `.PHONY: foo` on the line directly above the `foo:` rule, not batched at the top of the file. keeps the declaration next to the thing it describes.
- **recipes go through the project's env runner** `uv run pytest`, not bare `pytest`; `npx ...`, not a globally-installed binary. targets must work from a fresh clone w/out activating anything.
- **file targets list real deps** rules that produce a file (e.g. `./bin/foo:`) name every input that should trigger a rebuild -- source globs (`SRCS := $(shell find ...)`), the `makefile` itself, package/lockfiles (`go.mod`, `go.sum`, `package-lock.json`, `uv.lock`). including the `makefile` and the package files means a change to the build recipe or to declared deps invalidates the cached artefact, just like a source-file edit would.
- **`mkdir -p` before writes** any rule that produces a file in a directory creates the directory first.
- **optional tools are soft** wrap with `command -v <tool> >/dev/null 2>&1` and either fall back (e.g. `gotest` -> `go test`) or skip with a message. don't hard-fail on a missing nice-to-have.
- **overridable knobs** `VAR ?= <default>` for the plain case; `$(or $(VAR),<default>)` / `$(if $(strip $(VAR)),...)` when an explicitly-empty value should also fall back (e.g. `make images VER=`). lets the caller narrow or retune w/out touching the makefile.
- **aggregate gate target** a `verify` target that chains `lint typecheck test ...` -- one entry point for "is this commit healthy", and what ci should call.
- **kebab-case target names** `cover-open`, `generate-version`, not `cover_open` or `coverOpen`.
- **expensive non-file work gets a stamp** for rules whose output is not a file make can date-compare (container images, uploads), gate on `.stamp/<name>: FORCE | .stamp` with the change-detection (input hashing) inside the called script; `clean-<thing>` removes the stamps. see pats' `images` target for the full shape.
