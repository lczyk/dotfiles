---
name: to-issue
description: Convert the most recent conversation subject -- a researched bug, enhancement, or task -- into a single well-formatted issue in markdown, ready to post to the issue tracker. Conventional-commits-style title, body in the user's writing style.
disable-model-invocation: true
---

# To Issue

Turn the thing we just researched into **one** issue -- a conventional-commits-titled, markdown-formatted digest ready to paste into the issue tracker.

The point: after digging into a bug or enhancement, invoke this to get a correctly-shaped write-up without re-teaching the format each time.

## Process

### 1. Pick the subject

Convert only the **most recent** conversation subject into an issue.

- If there's no clear subject to write up, **prompt the user** for what to convert -- don't invent one.
- If several distinct issues have been discussed recently and the user hasn't said which one, **prompt the user** to pick -- don't guess.

Work from what's already in the conversation. If the user passed a reference (a path, an issue number or URL) as an argument, that reference *is* the subject -- fetch it and read its full body and comments.

### 2. Explore the codebase (optional)

If you haven't already, look at the relevant code so the issue uses the project's real names and reflects the actual state. Keep it light -- enough to get the facts and the vocabulary right, not a full audit.

### 3. Draft the issue

**Title** -- a conventional-commits-like line: `<type>: <short subject>`, e.g. `ci: lxd prep failure`, `feat: retry on 429`, `fix: off-by-one in cursor paging`. Reuse the commit-type vocab (`feat`, `fix`, `ci`, `docs`, `refactor`, `chore`, `test`, `perf`, `bench`, `revert`, `release`, ...). Lowercase subject, no trailing full stop. It's a memory-jogger, not a description -- keep it terse and skip specific identifiers unless the identifier *is* the subject.

**Body** -- write it in the user's personal writing style: lofi (lowercase, en-GB, ascii, casual short forms like `b/c` / `w/out` / `->`). Source of truth: `~/.config/agent-styles/lofi.md`. Use the template below, trimming any section that doesn't apply:

<issue-template>

## what / why

one or two lines: what's wrong (bug) or what to add (enhancement), and why it matters.

## context

where it shows up -- the component, file area, or flow, using the real names from the codebase.

## evidence

for a bug: repro steps, the error, expected vs actual. for an enhancement: the current gap and what triggered wanting it. drop this section if there's nothing concrete to show.

## direction (optional)

proposed approach or options, iff the research turned some up. not a full design -- just the lead. open questions go here too.

</issue-template>

Keep it tight. Avoid specific file paths or code snippets -- they go stale. Exception: when one encodes a fact more precisely than prose can (the exact error string, a failing command, a type shape), inline just that part.

### 4. Hand it over

Output two things:

- the **title** on its own line, as inline code -- so it drops straight into the tracker's title field
- the **body** in a fenced ` ```markdown ` block -- so it copy-pastes clean into the description field

Don't post anything. The user reviews and posts. If they then ask, publish it to the tracker.
