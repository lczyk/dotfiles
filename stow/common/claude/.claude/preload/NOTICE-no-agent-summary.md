vendored from https://gist.github.com/flamerix-ai/c3905705cc4205e5de3011fa2e74efce (MIT). see `LICENSE-no-agent-summary`.

upstream version: v3 (gist revision 4f1ad563fbe4fb830af5dd67fbde4c1860f9caa6, 2026-10-29)

vendored files:
- `no-agent-summary.js` -- bun `--preload` that stops claude code's `agent_summary` side query (the 30s per-background-agent "describe in 3-5 words" transcript resend)

local modifications:
- one em-dash in the header comment replaced with `--` (ascii-only pre-commit hook)

wiring: `~/.config/fish/conf.d/10_claude.fish` passes `BUN_OPTIONS=--preload=<this file>` to `claude`, so it reaches only claude started from fish. after stowing, `claude daemon stop --any` so the daemon and pre-warmed sessions pick it up.

verify (after every claude code update -- the match is by callback source text, so a renamed anchor fails open and summaries quietly return):

```fish
CC_AGENT_SUMMARY_LOG=/tmp/ai/nas.log claude --version; cat /tmp/ai/nas.log
```

(`env VAR=... claude` would bypass the fish wrapper and run the bare binary without the preload.)

expect `preload active mode=off ... hooked=global.setTimeout`. `CC_AGENT_SUMMARY_MODE=pass` is the a/b control (loads, arms every timer).
