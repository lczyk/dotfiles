---
name: to-pr
description: Write up all the changes on the current branch as a single well-formatted pull request in markdown, ready to open. Conventional-commits-style title, body in the user's writing style. Reads the branch diff and commits; does not push or open the PR unless asked.
disable-model-invocation: true
---

# To PR

Turn the changes on the current branch into **one** pull request -- a conventional-commits-titled, markdown-formatted write-up ready to paste into the PR form.

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

### 3. Draft the PR

**Title** -- a conventional-commits-like line: `<type>: <short subject>`, e.g. `feat: retry on 429`, `fix: off-by-one in cursor paging`, `ci: pin runner image`. Reuse the commit-type vocab (`feat`, `fix`, `ci`, `docs`, `refactor`, `chore`, `test`, `perf`, `bench`, `revert`, `release`, ...). Lowercase subject, no trailing full stop. It's a memory-jogger, not a description -- terse, and skip specific identifiers unless the identifier *is* the change. A single-commit branch usually just reuses that commit's subject.

**Body** -- write it in the user's personal writing style: lofi (lowercase, en-GB, ascii, casual short forms like `b/c` / `w/out` / `->`). Source of truth: `~/.config/agent-styles/lofi.md`. Use the template below, trimming any section that doesn't apply:

<pr-template>

## what / why

one or two lines: what this branch changes, and why -- the problem it solves or the thing it adds.

## changes

the notable moving parts, as a short bullet list -- the things a reviewer should know to look at. group by area if the diff is wide. skip the line-by-line; the diff has that.

## testing

how it was checked -- tests added/run, manual verification, commands. drop this section if there's genuinely nothing to say.

## notes (optional)

anything a reviewer needs: follow-ups deferred, trade-offs taken, open questions, things deliberately left out of scope.

</pr-template>

If the branch closes an issue, add a `closes #<n>` line so the merge wires it up.

Keep it tight. Avoid pasting large code snippets -- the diff already shows them. Exception: when one line encodes a fact more precisely than prose can (the exact command run, a before/after value, a type shape), inline just that part.

### 4. Hand it over

Output two things:

- the **title** on its own line, as inline code -- so it drops straight into the PR title field.
- the **body** in a fenced ` ```markdown ` block -- so it copy-pastes clean into the description field.

Don't push and don't open the PR. The user reviews and opens it. If they then ask, open it with `gh pr create` (matching the title and body above).
