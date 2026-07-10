# dotfiles

see https://brandon.invergo.net/news/2012-05-26-using-gnu-stow-to-manage-your-dotfiles.html

## Setup

Build and install binaries:

```
make build install
```

Stow dotfiles:

```
make stow
```

See `make help` for all targets.

## profiles

packages live under:

- `stow/common/<pkg>/` -- stowed on every host.
- `stow/mac/<pkg>/` -- stowed on macos only.
- `stow/x1/<pkg>/` -- stowed on the x1 linux laptop.
- `stow/armstrong/<pkg>/` -- stowed on the headless armstrong server.

profile auto-detected from `uname -s` then `uname -n`: Darwin -> mac, host `armstrong` -> armstrong, else x1. override with `make stow PROFILE=mac|x1|armstrong`.

sub-file splits use the host program's own include mechanism. e.g. `stow/common/git/.config/git/config` ends with `[include] path = ~/.config/git/config.local`; profiles may provide their own `config.local` for host-specific bits (mac adds `osxkeychain` credential helper; x1 has none -- git silently ignores the missing include). same import-on-disk pattern for alacritty (`local.toml`).

## claude settings churn

claude-code rewrites transient keys (`effortLevel`, `model`, `theme`, `tui`, `voiceEnabled`) back into the stowed `stow/common/claude/.claude/settings.json`, which used to cause git churn and stash conflicts. a `claudecfg` git clean filter strips those keys from the tracked version while leaving your live file untouched:

- filter def: `[filter "claudecfg"]` in `stow/common/git/.config/git/config` (`jq -S`, sorted so key-reordering can't churn either).
- `.gitattributes` (repo root) maps `settings.json` to the filter.

to add a newly-discovered transient key: append it to the `del(...)` list in the filter def, then `make normalize-claude-settings` and commit. the make target is idempotent -- restages the file through the filter, no-op if already clean.

caveat: needs `jq`, and the filter def must be live (`make stow`) before committing that file from a fresh machine. the filter is marked `required`, so a missing def hard-fails `git add` rather than silently staging the raw file with the transient keys still in it.

## agent harnesses

claude code is the primary harness. its `~/.claude/CLAUDE.md` remains the
source of truth for harness-neutral workflow instructions. opencode and codex
are secondary harnesses that adapt those rules and share the safety hooks under
`~/.config/agent-hooks/`.

the codex stow package manages `~/.codex/AGENTS.md`, `~/.codex/hooks.json`, and
`~/.codex/config.toml`. codex writes machine-local project trust, tui onboarding
state, hook trust hashes, and the `/model` picker choice into the live config.
the `codexcfg` git clean filter (also `required`, same hard-fail guarantee as
`claudecfg`) removes those from the committed version while retaining them in
the live file. run `make normalize-codex-config` after adding another transient
table to the filter. it is a denylist: a transient table codex invents later
ships to the repo by default until added to the filter.

after `make stow`, start codex and open `/hooks` to review and trust the stowed
hook definitions. codex records trust against each definition's hash, so repeat
that review after hook configuration changes.

caveat: there is no smudge filter, so any checkout that rewrites `config.toml`
(`git checkout` / `restore` / `stash pop`) replaces the live file with the
stripped version -- project trust, hook trust hashes, and the model pin are
lost. codex re-prompts for trust; harmless but noisy.


# todo

- [x] fuzzy time
- [ ] ? cmd+tab switcher
- [ ] screensaver in sway
- [ ] cmd+backspace / alt+backspace
- [ ] alt+shift vs shift+alt ordering

# links

https://git.korhonen.cc/FunctionalHacker/dotfiles
