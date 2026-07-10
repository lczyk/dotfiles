# codex harness bridge

claude code is the primary harness. the harness-neutral personal workflow rules
in `~/.claude/CLAUDE.md` remain the source of truth; a codex `SessionStart` hook
injects that file as developer context.

if codex reports that the hook is untrusted or skipped, read
`~/.claude/CLAUDE.md` before substantive work.

translate harness-specific names by capability:

- `Bash` means codex's shell-command tools.
- `Write`, `Edit`, and `NotebookEdit` mean `apply_patch`, codex's file-edit
  tool. (if codex grows another file-edit tool, add a matcher for it in
  `hooks.json` -- only `Bash` and `apply_patch` are hooked today.)
- claude-only settings, plugins, statusline behaviour, and hook setup notes are
  descriptive context, not instructions to modify the claude installation.
- codex system and developer instructions win when a claude-specific mechanism
  conflicts with codex runtime behaviour.

