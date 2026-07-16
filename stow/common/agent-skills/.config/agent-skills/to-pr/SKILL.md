---
name: to-pr
description: Write up all the changes on the current branch as a single pull request in markdown, ready to open. Title and body shaped the way the user actually writes PRs: lowercase, freeform, length-driven, root-cause-first, no boilerplate template. Aware of a repo's own PR template when one exists. Reads the branch diff and commits; does not push or open the PR unless asked.
disable-model-invocation: true
---

# To PR

Turn the changes on the current branch into **one** pull request -- markdown-formatted, ready to paste into the PR form, written the way the user actually writes PRs.

The point: once a branch's work is done, invoke this to get a correctly-shaped PR description without re-teaching the format each time.

## Process

### 1. Establish the diff range

Work out what this PR actually contains:

- current branch: `git branch --show-current`.
- base: the repo's default branch (`main` / `master`), unless the branch clearly forks from something else. Find the fork point with `git merge-base HEAD <base>`.
- the range is `<merge-base>..HEAD`.

If the current branch **is** the default branch, there's no branch to write up -- **tell the user** and stop, rather than diffing against a guess.

### 2. Read the changes

This is the source material -- read it, don't skim:

- `git log <base>..HEAD` -- the commits, their subjects and bodies. These carry the intent.
- `git diff <base>..HEAD --stat` then the diff itself -- what actually changed.

Explore the surrounding code only if the diff alone doesn't give you the real names or the *why*. Keep it light. Pull the "why" from the conversation too if the reasoning lives there rather than in the commit messages.

### 3. Check for a repo PR template

Before drafting, see whether the target repo enforces a PR template (`.github/PULL_REQUEST_TEMPLATE.md`, or one a CONTRIBUTING doc points at). If it does: fill the mandated headings / checkboxes mechanically and minimally -- tick `[x]` for what's true, and for an inapplicable item use `~~strikethrough~~ ( reason )` rather than leaving it blank or deleting it. Put the real voice in the free-text areas: a one-line context sentence prepended before the template, or a short note appended after a `---` divider, or -- for substantial changes -- your own topic-named `#` / `##` sub-headings inserted inside a free-text field. If there's no template, go freeform, as below. The template-vs-freeform split is repo-imposed, not a formality dial: a template-free team repo gets the same freeform voice as a personal one, just scaled to the change.

### 4. Draft the PR

**Title** -- `<type>(<scope>): <lowercase subject>`, no trailing full stop, 2-8 words, describing the *kind* of change abstractly rather than restating the diff. Types: `feat`, `fix`, `chore`, `perf`, `docs`, `test`, `ci`. Optional scope in parens is a version / component / area tag, not a module path (`feat(26.04):`, `perf(simscreen):`). Drop framing verbs the prefix already implies (`add support for`, `implement`, `introduce`). Backtick an identifier only when the identifier itself *is* the point (`` fix: `no-optimize` determinism ``); otherwise keep it abstract (`chore: bump chisel to v1.4.2`, `feat: rust port`). Append `!` when the branch is intentionally broken / not fully verified (`test!: ...`). A single-commit branch usually just reuses that commit's subject. Exception: match the target repo's own strong title convention when it has one (e.g. Homebrew formula PRs).

**Body** -- the user's voice: lofi (lowercase everywhere incl. `i`, en-GB, ascii, casual short forms like `b/c` / `w/out` / `->`). Source of truth: `~/.config/agent-styles/lofi.md`. **No fixed skeleton** -- length and shape follow the actual change:

- **trivial / mechanical** (version bump, obvious one-file fix, self-explanatory from the title): leave the body **empty**, or one short lowercase sentence. don't manufacture a summary.
- **small-to-medium**: 1-3 sentences fusing what + why, optionally a flat `-` bullet list (one bullet per discrete change), optionally closed with `### tests` / `tested with:` + a fenced command. a bare "yes" is a legitimate full answer under tests.
- **big / substantial** (root-cause bugfix, perf work, new feature): a prose opening saying what prompted it (a CVE, an issue, an upstream PR, something noticed in passing), then **invented topic-named `###` headings** -- named after the actual bug / topic, *never* generic `## summary` / `## changes` / `## testing`. each gets a short explanation of the mechanism, optional nested bullets, and an optional fenced repro command with **real pasted terminal / benchmark output** as proof. use a numbered list only to enumerate discrete design decisions / tradeoffs (not sequential steps); mark a later addition to it with `_edit:_` rather than renumbering. close with an explicit out-of-scope note ("btw, still needs ...; kept this PR small") or a direct question to a named reviewer (`wdyt @person ??`).

Cross-cutting:

- lead a bugfix / perf PR with the **root-cause mechanism**, not a restatement of the diff. skip the *what* entirely when the diff is the answer.
- be realistic, not vaguely upbeat: concrete signal (tests passing, before/after sizes, `p99 240ms -> 90ms on the bench`), never "significant improvement". if there's no measurable result yet, say so plainly.
- backtick every identifier, flag, command, filename, version string. use `X -> Y` for renames, corrections, and version bumps.
- credit collaborators inline (`ty @handle`, `thanks @handle for catching this`), not in a dedicated section.
- if the change was substantially AI-authored, disclose it in bold (`**AI DISCLOSURE**: ...`) -- the user does this on significant AI-written contributions.
- no tables, no collapsible `<details>`, no self-review checklist in a freeform body -- checkboxes appear only inside a repo template. emoji: at most one, deliberate; default to none.

References: same-repo issues / PRs as bare `#N` in prose ("follow-up to #321", "addresses #801"); cross-repo as full `https://github.com/...` URLs. To auto-close an issue, put `closes #<n>` lowercase on its own line -- most PRs just reference informationally without it. @-mentions inline, never a "cc:" line.

### 5. Hand it over

Output two things:

- the **title** on its own line, as inline code -- so it drops straight into the PR title field.
- the **body** in a fenced ` ```markdown ` block -- so it copy-pastes clean into the description field.

Don't push and don't open the PR. The user reviews and opens it. If they then ask, open it with `gh pr create` (matching the title and body above).
