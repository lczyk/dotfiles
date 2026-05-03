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

<<<<<<< Updated upstream
||||||| Stash base
stow -D <thing>
```
=======
## profiles

packages live under:

- `stow/common/<pkg>/` -- stowed on every host.
- `stow/mac/<pkg>/` -- stowed on macos only.
- `stow/x1/<pkg>/` -- stowed on linux only.

profile auto-detected from `uname -s` (Darwin -> mac, else x1). override with `make stow PROFILE=mac|x1`.

sub-file splits use the host program's own include mechanism. e.g. `stow/common/git/.config/git/config` ends with `[include] path = ~/.config/git/config.local`, and each profile package provides its own `config.local`. same idea for alacritty (`local.toml` import).

>>>>>>> Stashed changes

# todo

- [x] fuzzy time
- [ ] cmd+tab switcher
- [ ] screensaver in sway
- [ ] cmd+backspace / alt+backspace
- [ ] alt+shift vs shift+alt ordering

# links

https://git.korhonen.cc/FunctionalHacker/dotfiles