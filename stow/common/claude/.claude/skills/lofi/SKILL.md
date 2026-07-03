---
name: lofi
description: >
  Toggle the lofi personal writing style (lowercase, en-GB, ascii-only, casual
  short forms). Style is on by default via SessionStart/UserPromptSubmit hooks;
  this skill turns it off/on. Use when the user invokes /lofi or says
  "lofi off", "lofi on", "stop lofi", "normal capitalisation".
argument-hint: "[on|off|status]"
---

lofi = the personal writing style injected by the hooks in `settings.json`
(full rules: `~/.claude/styles/lofi.md`; per-turn digest:
`~/.claude/styles/lofi-reminder.md`). on by default, no levels.

state = marker file `~/.claude/.lofi-off`. present -> hooks stay silent and
the statusline badge shows `[x]`. absent -> style active, badge `[L]`.

on invocation:

- `off` -- run `touch ~/.claude/.lofi-off`. stop applying the style for the
  rest of this session (normal capitalisation etc.). persists across sessions
  until turned back on.
- `on` or no argument -- run `rm -f ~/.claude/.lofi-off`. apply the style from
  the next reply onward (the full rules were injected at session start; if
  this session started with lofi off, read `~/.claude/styles/lofi.md` now).
- `status` -- report on/off from the marker file, don't change anything.

confirm the toggle in one short line. nothing else to do -- the hooks and
statusline pick the marker up by themselves.
