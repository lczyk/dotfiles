# hax harness bridge

`~/.config/agent-guidance/workflow.md` is injected through hax's
`system_prompt_append` setting and remains the shared workflow source of truth.

- `Bash` means hax's shell-command tool.
- `Write` and `Edit` mean hax's file-edit tools.
- hax has no pre-tool hook API. shared safety policy is instruction-only here;
  it cannot enforce `agent-hooks/evaluate.sh`.
- hax system and developer instructions win when they conflict with a
  harness-specific mechanism.
