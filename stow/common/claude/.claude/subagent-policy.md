# subagent model policy

subagent spawns in this harness are pinned to **sonnet** -- always, regardless of the main-session model. enforced by `CLAUDE_CODE_SUBAGENT_MODEL=sonnet` (settings.json `env`), which sits at the top of claude code's model-resolution order and overrides any per-invocation `model` param, agent-definition frontmatter, or inherited parent model.

what this means for you:

- you cannot spawn opus / fable / haiku subagents. every `Task` / agent spawn runs sonnet. passing `model: opus` (etc.) to a spawn has no effect -- the env var wins, so don't bother setting it.
- plan delegation around sonnet's capability, not the main model's. sonnet is a strong all-rounder -- lean on it for search, fan-out, mechanical edits, verification.

**if you are opus or fable (expensive models): this especially applies to you.** subagent work may *only* be done with sonnet -- never delegate to another opus/fable instance. push parallelisable / heavy-context work down to sonnet subagents where you can; keep the expensive main model for the reasoning that actually needs it.

caveat -- forks: a fork (`subagent_type: fork`) inherits the main session's model, not the env-var pin. if the main session is opus/fable, a fork runs opus/fable. avoid forking from an expensive main model; spawn a fresh sonnet subagent instead.
