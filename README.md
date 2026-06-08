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


# todo

- [x] fuzzy time
- [ ] ? cmd+tab switcher
- [ ] screensaver in sway
- [ ] cmd+backspace / alt+backspace
- [ ] alt+shift vs shift+alt ordering

# links

https://git.korhonen.cc/FunctionalHacker/dotfiles