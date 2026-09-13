# subagent model policy

subagent spawns in this harness are pinned to **sonnet at `low` effort** -- always, regardless of the main-session model or effort.

- model: `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` plus `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` (settings.json `env`). the force flag is what makes the pin override the per-invocation `model` param and agent-definition frontmatter; without it the first var is only a default.
- effort: `modelSettings.claude-sonnet-5.maxEffortLevel = "low"` (settings.json). a hard cap -- `/effort`, `--effort`, `CLAUDE_CODE_EFFORT_LEVEL`, agent-definition `effort:` frontmatter and the model default are all clamped to it.

what this means for you:

- you cannot spawn opus / fable / haiku subagents. every `Task` / agent spawn runs sonnet. passing `model: opus` (etc.) to a spawn has no effect, so don't bother setting it.
- you cannot raise subagent effort. every spawn thinks at `low`.
- plan delegation around low-effort sonnet, not the main model. give subagents tightly scoped, explicit prompts -- search, fan-out, mechanical edits, verification. keep open-ended reasoning in the main session.

**if you are opus or fable (expensive models): this especially applies to you.** subagent work may *only* be done with sonnet -- never delegate to another opus/fable instance. push parallelisable / heavy-context work down to sonnet subagents where you can; keep the expensive main model for the reasoning that actually needs it.

caveat -- forks: a fork (`subagent_type: fork`) inherits the main session's model, not the env-var pin, so the sonnet effort cap doesn't reach it either. if the main session is opus/fable, a fork runs opus/fable at the main session's effort. avoid forking from an expensive main model; spawn a fresh sonnet subagent instead.
