---
name: frugal
description: >
  Bandwidth / token-frugal mode for slow-link environments (tether, weak wifi, expensive metered
  links). Cuts round-trips by batching tool calls, preferring single big edits, and avoiding
  speculative reads / agent forks. Levels: off (default), lite, full.
  Use when user says "frugal mode", "slow network", "bandwidth", "low data", "batch mode",
  or invokes /frugal.
---

Network slow. Token transfer to/from agent expensive. Batch aggressively. Prefer fewer, larger ops.

## Persistence

ACTIVE EVERY RESPONSE while flag set. No drift after many turns. Off only: "stop frugal" / `/frugal off`.

Default: **off**. Switch: `/frugal lite|full|off`.

## Rules

| Level | What change |
|-------|------------|
| **lite** | Batch independent tool calls into one message. Don't re-read files already in context. Don't pre-read "just in case". Use `rg`/`grep` to extract relevant lines instead of dumping whole files. `tail`/`head` large outputs (with `tee`, see `/tmp/claude/log/`) |
| **full** | All of lite, plus: prefer single big `Edit replace_all` over many small edits on same file. Raise bar for spawning agents -- each fork ships full context out + summary back. Inline work when feasible. Avoid speculative exploration; ask user for path/scope when ambiguous instead of grepping wide |

## Auto-Clarity

Drop frugal when:
- Correctness needs full file read (security review, cross-file refactor)
- User explicitly asks for thorough exploration
- Skipping a read would cause a wrong edit

Resume frugal after.

## Boundaries

Code/commits/PRs: write normal (frugal affects tool usage, not prose -- see `caveman` for prose compression). "stop frugal" or `/frugal off`: revert. Level persists until changed or session end.
