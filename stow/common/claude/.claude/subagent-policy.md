# subagent model policy

subagents in this harness always run **sonnet at `low` effort**, whatever the main session's model or effort. (`CLAUDE_CODE_SUBAGENT_MODEL=sonnet` + `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` override the per-spawn `model` and agent frontmatter; `maxEffortLevel = "low"` clamps every effort setting.)

- passing `model: opus` / fable / haiku or a higher effort to a spawn has no effect -- don't bother.
- delegate tightly scoped, explicit work: search, fan-out, mechanical edits, verification. keep open-ended reasoning in the main session.
- if you're opus / fable, push heavy-context, parallelisable work down to sonnet subagents and keep the expensive model for the reasoning that needs it.
- forks (`subagent_type: fork`) inherit the main model and effort, not the pin -- from an opus / fable session a fork is another opus / fable. spawn a fresh subagent instead.
