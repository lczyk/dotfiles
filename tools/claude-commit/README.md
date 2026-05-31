# claude-commit

tiny cli that asks the cheapest claude model (haiku 4.5) to write a conventional-commit message for your staged changes.

requires the `claude` cli on PATH (claude code).

## install

```
make install
```

symlinks `claude-commit` (and short alias `clc`) into `~/.local/bin`.

## use

stage some changes, then:

```
claude-commit          # generate, show, prompt y/n, commit
claude-commit -y       # generate and commit, no prompt
claude-commit -p       # just print the message, dont commit
claude-commit --model claude-sonnet-4-6 ...
```

## flags

- `-p`, `--print` -- print to stdout instead of committing
- `-y`, `--yes` -- skip the confirmation prompt
- `-a`, `--all` -- stage everything (`git add -A`) before generating
- `-P`, `--push` -- `git push` after committing (cancelled by `--print`)
- `--staged` -- only use already-staged changes (overrides `all` in `CLC_DEFAULT_OPTS`)
- `--model <id>` -- override the model id (default: `claude-haiku-4-5`)
- `--effort <level>` -- override effort level (default: `low`)

## env

- `CLC_DEFAULT_OPTS` -- comma-separated default flags. valid tokens (case-insensitive): `all`, `yes`, `print`, `push`. `yes`/`push` are mutually exclusive with `print`. unknown tokens are a hard error. cli flags override: `--staged` cancels `all`, `--print` cancels `yes`/`push`, `--yes` cancels `print`.

  e.g. `export CLC_DEFAULT_OPTS=all,yes` -- always `git add -A` and skip the prompt; pass `--staged` for a one-off commit of only what's already staged.

- `CLC_MODEL` -- default model id (overridden by `--model`).
- `CLC_EFFORT` -- default effort level (overridden by `--effort`).

run with `-v` to see the resolved flag/model/effort values.

## shell completion

```
clc --completion fish | source                              # one-shot
clc --completion fish > ~/.config/fish/completions/clc.fish # persist
```

uses whatever name you invoked the binary as (`clc` or `claude-commit`), so install the completion under that name.
