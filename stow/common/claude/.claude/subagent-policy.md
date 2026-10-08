# subagent model policy

subagents in this harness always run **haiku at `medium` effort**, whatever the main session's model or effort. (`CLAUDE_CODE_SUBAGENT_MODEL=haiku` + `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` override the per-spawn `model` and agent frontmatter; `maxEffortLevel = "medium"` clamps every effort setting.)

- passing `model: opus` / fable / sonnet or a higher effort to a spawn has no effect -- don't bother.
- delegate tightly scoped, explicit work: search, fan-out, mechanical edits, verification. keep open-ended reasoning in the main session.
- if you're opus / fable, push heavy-context, parallelisable work down to haiku subagents and keep the expensive model for the reasoning that needs it.
- forks (`subagent_type: fork`) inherit the main model and effort, not the pin -- from an opus / fable session a fork is another opus / fable. spawn a fresh subagent instead.
