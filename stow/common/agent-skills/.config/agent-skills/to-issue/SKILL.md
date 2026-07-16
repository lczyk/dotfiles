---
name: to-issue
description: Convert the most recent conversation subject -- a researched bug, enhancement, or task -- into a single well-formatted issue in markdown, ready to post to the issue tracker. Title and body shaped the way the user actually writes issues: lowercase, freeform, repro-first, no boilerplate template. Aware of a repo's own issue form when one exists.
disable-model-invocation: true
---

# To Issue

Turn the thing we just researched into **one** issue -- markdown-formatted, ready to paste into the tracker, written the way the user actually writes issues.

The point: after digging into a bug or enhancement, invoke this to get a correctly-shaped write-up without re-teaching the format each time.

## Process

### 1. Pick the subject

Convert only the **most recent** conversation subject into an issue.

- If there's no clear subject to write up, **prompt the user** for what to convert -- don't invent one.
- If several distinct issues have been discussed recently and the user hasn't said which one, **prompt the user** to pick -- don't guess.

Work from what's already in the conversation. If the user passed a reference (a path, an issue number or URL) as an argument, that reference *is* the subject -- fetch it and read its full body and comments.

### 2. Get the facts right (optional)

If you haven't already, look at the relevant code so the issue uses the project's real names and reflects the actual state. Keep it light -- enough to get the facts and the vocabulary right, not a full audit.

### 3. Check for a repo issue template

Before drafting, see whether the target repo enforces its own issue form (`.github/ISSUE_TEMPLATE/`, the form that pops up when opening an issue). If it does: fill every required section, terse, and keep the real voice in the free-text fields. If it doesn't -- most upstream OSS, and all the user's own repos -- go freeform, as below. Voice constriction tracks template presence, not personal-vs-team: a template-free upstream repo gets the same freeform voice as a personal one.

### 4. Draft the issue

**Title** -- lowercase, no trailing full stop, a single clause under ~10 words, symptom- or action-first (all elaboration goes in the body). Backtick every command, flag, filename, package, or symbol named in the title -- e.g. `` bug: `compile-tree -no-optimize` doesn't resolve stale edges ``. Prefix with a conventional-commits-ish tag **matching whatever the target repo's recent issues use**: `bug:` (note: `bug`, *not* `fix` -- `fix:` is reserved for commits), `feat:` / `enhancement:` (interchangeable), `chore:`, optionally a disambiguating scope (`bug(26.10): ...`). If the repo has no tag convention (most third-party OSS), drop the prefix and just write a plain lowercase symptom phrase. Append `?:` when you're not even sure the report is valid (`bug?: ...`).

**Body** -- the user's voice: lofi (lowercase everywhere incl. `i`, en-GB, ascii, casual short forms like `b/c` / `w/out` / `->`). Source of truth: `~/.config/agent-styles/lofi.md`. **No fixed template** -- shape follows what the issue actually needs:

- open **directly on the symptom / claim / context**. the first sentence states the fact. no greeting, no "i noticed", no preamble.
- **evidence** is the load-bearing part: a minimal runnable repro (a short shell / python snippet, sometimes literally `mwe.py`), a pasted terminal transcript or log, a diff, or a quoted doc excerpt (`>` blockquote). show expected-vs-actual as an inline `// comment` in the code (`// expected 512 512, got None None`), not a separate expected/actual heading pair.
- a **root-cause guess**, if you have one, stays hedged -- "i think", "looks like", "seems to be", trailing `...?` -- never asserted as settled unless verified.
- **fix ideas / open questions** go as a short `-` bullet list at the very end, kept out of the main narrative.
- **links**: a single reference inline (`see https://...`); several as a trailing bullet list of bare URLs or a `## see also` appendix.

Only add headings once the body is genuinely long enough to need sectioning, and name them after the actual topic -- never generic `## steps` / `## expected` / `## actual`. A short issue (especially on a personal repo) is often just one or two sentences plus a code fence, no headings at all.

Length is bimodal: a quick observation is 1-3 sentences; a real bug report or a persuade-the-maintainer ask is several dense paragraphs plus code / log blocks -- but never padded, every sentence carries new info. Match structure to content: don't inflate a one-liner into paragraphs, and don't flatten two distinct failure modes into one blob.

References: same-repo sibling issues as bare `#N`; never `closes #` / `fixes #` (that's a PR convention -- these are issues). @-mention a maintainer only for a direct personal ask (`hi @user! any chance you could ...`). Emoji: at most one, ironic / self-aware, and most issues have none.

### 5. Hand it over

Output two things:

- the **title** on its own line, as inline code -- so it drops straight into the tracker's title field
- the **body** in a fenced ` ```markdown ` block -- so it copy-pastes clean into the description field

Don't post anything. The user reviews and posts. If they then ask, publish it to the tracker.
