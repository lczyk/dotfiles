# conventional commits spec

the commit-message conventions used in this repo, in plain prose.

## subject must be conventional commits

shape: `<type>(<scope>)?<marker>?: <subject>`

- **types** -- `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `bench`, `revert`, `ci`, `perf`, `release`. anything else is rejected.
    - `release:` is a local extension to the standard set -- used for release-cut commits (version bumps, tag-prep, changelog roll-ups). not part of the upstream cc spec.
- **scope** is optional. if present: lowercase, may contain `a-z 0-9 . _ -`. no spaces, no uppercase, no empty `()`.
- **markers** (optional, after scope, before colon):
    - `!:` -- commit is intentionally broken (failing tests, mid-refactor checkpoint, tdd's red step). distinguishes deliberate breakage from accidental.
    - `?:` -- best effort; might fail ci or other remote validation. signals "watch ci".
- a single space must follow the colon.

## body / full-message rules

- **ASCII only, whole message** -- no emoji, em-dash, en-dash, smart quotes, ellipsis glyph, arrows, etc. use the ASCII equivalents (`--`, `"`, `...`, `->`).
