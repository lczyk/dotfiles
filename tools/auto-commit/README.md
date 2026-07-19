# auto-commit

tiny cli that asks the cheapest claude model (haiku 4.5) to write a conventional-commit message for your staged changes.

requires the `claude` cli on PATH (claude code).

## install

```
make install
```

symlinks `auto-commit` (and short alias `ac`) into `~/.local/bin`.

## use

stage some changes, then:

```
auto-commit          # generate, show, prompt y/n, commit
auto-commit -y       # generate and commit, no prompt
auto-commit -p       # just print the message, dont commit
auto-commit --model claude-sonnet-4-6 ...
```

## flags

- `-p`, `--print` -- print to stdout instead of committing
- `-y`, `--yes` -- skip the confirmation prompt
- `-a`, `--all` -- stage everything (`git add -A`) before generating
- `--staged` -- only use already-staged changes (overrides `all` in `AC_DEFAULT_OPTS`)
- `--model <id>` -- override the model id (default: `claude-haiku-4-5`)
- `--effort <level>` -- override effort level (default: `low`)

## env

- `AC_DEFAULT_OPTS` -- comma-separated default flags. valid tokens (case-insensitive): `all`, `yes`, `print`. `yes` is mutually exclusive with `print`. unknown tokens are a hard error. cli flags override: `--staged` cancels `all`, `--print` cancels `yes`, `--yes` cancels `print`.

  e.g. `export AC_DEFAULT_OPTS=all,yes` -- always `git add -A` and skip the prompt; pass `--staged` for a one-off commit of only what's already staged.

- `AC_MODEL` -- default model id (overridden by `--model`).
- `AC_EFFORT` -- default effort level (overridden by `--effort`).

run with `-v` to see the resolved flag/model/effort values.

## shell completion

```
ac --completion fish | source                              # one-shot
ac --completion fish > ~/.config/fish/completions/ac.fish # persist
```

uses whatever name you invoked the binary as (`ac` or `auto-commit`), so install the completion under that name.
