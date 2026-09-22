vendored from https://github.com/JuliusBrussee/caveman (MIT). see `LICENSE-caveman`.

vendored files:
- `skills/caveman/` -- caveman mode skill
- `skills/caveman-commit/` -- commit message generator skill
- `skills/caveman-compress/` -- memory file compression skill + scripts
- `hooks/caveman-activate.js` -- session start activation hook
- `hooks/caveman-mode-tracker.js` -- per-turn mode tracking hook
- `hooks/caveman-config.js` -- shared config resolver

local modifications:
- `skills/caveman/` -- lofi composition (lofi = surface, caveman = density), lofi typography, commit messages routed to `/caveman-commit`
- `skills/caveman-commit/` -- type list matches the `commit-msg` hook; `!:` / `?:` follow the workflow guidance (known-bad / unverified), not breaking change; no attribution, backticks or non-ascii; no auto-trigger on staging; lofi prose
- `skills/caveman-compress/` -- lofi prose
