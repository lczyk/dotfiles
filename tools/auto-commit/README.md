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
auto-commit -a       # git add -A first, then as above
auto-commit --model claude-sonnet-4-6 ...
```

only the index is ever read. if nothing is staged it does nothing and says so
-- either "nothing staged" when the worktree has changes you could have added,
or "working tree clean" when there's nothing to commit at all.

one model call, always. when the staged diff exceeds the size cap, every file
gets a fair share of the budget -- small files go whole, large ones are trimmed
to their allowance -- so every file is represented in the prompt rather than
the tail being cut off. `-v` says what got trimmed.

nothing is staged until you answer `y`. `-a` previews its `git add -A` against
a throwaway copy of the index, so answering `n`, hitting ctrl+c, passing `-p`,
or hitting an error all leave the repo byte-for-byte as it was.

## flags

- `-p`, `--print` -- print to stdout instead of committing
- `-y`, `--yes` -- skip the confirmation prompt
- `-a`, `--all` -- stage everything (`git add -A`) before generating
- `--model <id>` -- override the model id (default: `claude-haiku-4-5`)
- `--variant <name>` -- override the model variant (default: `none`, i.e. the
  model's own default). passed through to the `claude` cli as `--effort`.

`-v` is repeatable, and everything it prints goes to stderr:

- `-v` -- resolved flags, and one line per phase instead of the in-place
  progress line, so nothing gets overwritten
- `-vv` -- adds the model's own output: thinking and text blocks as they
  complete, the parsed structured output, and a summary line with the stop
  reason, resolved model, cost, thinking tokens and latency split
- `-vvv` -- adds what we sent: the full prompt including the diff, the sandbox
  the cli reported building, and the child's stderr when it wrote any

a `stop_reason` of `max_tokens` warns at any verbosity, since it explains
whatever fails next. the tool list in the cli's init event is checked against
what `--tools ""` should leave behind, and an unexpected tool is a hard failure
-- `--permission-mode bypassPermissions` is only safe while that list is empty
of anything escalatable.

colour is dropped unless both stdout and stderr are ttys, or when `NO_COLOR` is
set -- so `ac | cat` comes out plain.

## shell completion

```
ac --completion fish | source                              # one-shot
ac --completion fish > ~/.config/fish/completions/ac.fish # persist
```

uses whatever name you invoked the binary as (`ac` or `auto-commit`), so install the completion under that name.
