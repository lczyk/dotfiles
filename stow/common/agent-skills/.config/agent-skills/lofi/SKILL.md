---
name: lofi
description: >
  toggle the lofi personal writing style (lowercase, en-GB, ascii only, casual
  short forms). on by default via SessionStart / UserPromptSubmit hooks; this
  skill turns it off / on. use when the user invokes /lofi or says "lofi off",
  "lofi on", "stop lofi", "normal capitalisation".
argument-hint: "[on|off|status]"
---

lofi = the personal writing style. full rules: `~/.config/agent-styles/lofi.md`; per-turn digest: `~/.config/agent-styles/lofi-reminder.md`; optional expressive markers: `~/.config/agent-styles/lofi-extras.md`. the claude, codex and copilot adapters inject it; on by default, no levels.

state = marker file `${XDG_CONFIG_HOME:-$HOME/.config}/agent-state/lofi-off`. present -> adapters stay silent and the claude statusline badge shows `[x]`. absent -> style active, badge `[L]`.

on invocation:

- `off` -- run `mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/agent-state" && touch "${XDG_CONFIG_HOME:-$HOME/.config}/agent-state/lofi-off"`. stop applying the style for the rest of this session (normal capitalisation etc.). persists across sessions until turned back on.
- `on` or no argument -- run `rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/agent-state/lofi-off"`. apply the style from the next reply on; if this session started with lofi off, read `~/.config/agent-styles/lofi.md` now.
- `status` -- report on / off from the marker file, change nothing.

confirm the toggle in one short line. nothing else to do -- the hooks and statusline pick up the marker by themselves.
