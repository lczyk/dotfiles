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

### 3. Check for a repo issue form

Before drafting, check whether the target repo enforces its own issue form (`.github/ISSUE_TEMPLATE/`, the form that pops up when opening an issue). Actually check rather than assuming: freeform is still the majority upstream, but roughly two in five third-party repos here impose a form, and it skews towards the big, heavily-trafficked ones (cpython, vscode, mattermost, fzf, the astral-sh repos, setuptools). Note also that a form is often bug-report-only -- a chore or feature ask on the same repo may have nothing to fill in.

If a form applies: fill every required section, terse. Tick only the boxes that are literally true -- OS / shell radio buttons, "information attached" lists, maintainer-agreement acknowledgements -- and leave the rest unchecked. Don't blanket-tick a form. Keep the real voice in the free-text fields, don't invent sub-headings on top of the mandated ones, and leave the template's own instructional HTML comments in place rather than tidying them away.

If no form applies, go freeform, as below. Voice constriction tracks template presence, not personal-vs-team: a template-free upstream repo gets the same freeform voice as a personal one.

### 4. Draft the issue

**Title** -- lowercase, no trailing full stop, a single clause under ~10 words, symptom- or action-first (all elaboration goes in the body). Backtick commands, flags, filenames, packages and symbols named in the title -- e.g. `` bug: `compile-tree -no-optimize` doesn't resolve stale edges ``. Strong default, not absolute; a bare flag does slip through. Prefix with a conventional-commits-ish tag **matching whatever the target repo's recent issues use**: `bug:` (note: `bug`, *not* `fix` -- `fix:` is reserved for commits), `feat:` / `enhancement:` (interchangeable), `ci:` for anything about the pipeline itself, `chore:`, `docs:`, and `nit:` / `nitpick:` for a cosmetic papercut. Optional disambiguating scope in parens -- a release version, component or subsystem (`bug(26.10):`, `feat(testing):`, `bug(reviewer):`). Scope is a work/shared-repo device -- it shows up on canonical and team repos and essentially never on personal or upstream ones. If the repo has no tag convention -- most third-party OSS -- dropping the prefix for a plain symptom phrase is fine, but recent practice keeps the tag anyway (`bug: malformed writer stream for size=0` on `ulikunitz/xz`); lowercase either way. Append `?:` when you're not even sure the report is valid (`bug?: ...`, `feat?: ...`).

**Body** -- the user's voice: lofi (lowercase everywhere incl. `i`, en-GB, ascii, casual short forms like `b/c` / `w/out` / `->`). Source of truth: `~/.config/agent-styles/lofi.md`. ascii applies to your own prose only -- a pasted transcript, log, or product UI string keeps whatever glyphs the source had. **No fixed template.** the default is short: a couple of lowercase sentences, often plus one code fence. median body is ~340 characters and only about one issue in seven carries a heading at all. the tag is a decent length guide -- a `nit:` or `enhancement:` runs 2-4 lines, a `bug:` a short paragraph plus evidence, and a `ci:` the longest of the lot because it carries a pasted failure log.

- open **directly on the symptom / claim / context**. the first sentence states the fact. no greeting, no "i noticed", no preamble. two standard shapes:
    - a bug opens on the failing behaviour, stated flatly.
    - a feature / enhancement / nit opens on current behaviour -- `at the moment ...`, `at present ...`, `atm ...`, `currently ...` -- and only then the ask.
- **the ask is `we should ...`** -- the standing modal for what ought to happen (`we should add a teardown fixture`, `we should make sure they are deleted before running any agents`). used freely, ~20x per 100 issues.
- add a **provenance line** when the issue came from somewhere identifiable: `raised here: <url>`, `spotted by copilot while reviewing #171`, `see title. proposed by @handle`, `reviewing the strace slice (PRs #1022 / #1023 / #1024), ...`.
- **evidence** is the load-bearing part:
    - a fenced pasted terminal transcript / log / error is the single most common device -- about a third of issues have one.
    - a minimal runnable repro: a short shell / python / go snippet, sometimes literally `mwe.py`, sometimes a paste-this-into-`foo_test.go` test function that fails on the bug.
    - expected-vs-actual is usually just the pasted output itself -- the log line or traceback already says what went wrong. when the repro is a short snippet you ran by hand, note the mismatch as an inline comment on the relevant line (`print(a.height, a.width)  # None None, expected 512 512`). never a separate expected/actual heading pair.
    - a permalink to the failing CI run (`.../actions/runs/<id>`) -- evidence in its own right, often paired with a pasted excerpt from that run. common on ci-heavy work repos, rare elsewhere.
    - a screenshot for anything visible -- the most frequent evidence device after a pasted fence (~1 in 9 issues), and sometimes the body is nothing but one `<img>`. leave a `<!-- screenshot here -->` placeholder for the user to drop it in.
    - a `>` blockquote for a quoted doc or upstream excerpt; `_"..."_` for a short quoted phrase inline.
    - a version / environment block when it might matter: pasted `--version` and `git rev-parse HEAD`, or a `## environment` bullet list.
- **repro steps** as a numbered list when the failure needs a sequence to reach.
- a **root-cause guess**, if you have one, stays hedged -- "i think", "looks like", "seems to be", "unsure", a trailing `...?`, bare `?` or doubled `??` -- never asserted as settled unless verified.
- **fix ideas / open questions** land at the end, under a heading of their own as often as a bare `-` bullet list (`## fix ??`, `**fix proposal**`, `### suggested fixes`, `possible fixes, not mutually exclusive:`, `proposed solution:`). a ```diff fence is right when the fix is a couple of lines.
- **links**: a single reference inline (`see https://...`); several as a trailing bullet list of bare URLs, under a short appendix heading named for what it is (`### see also`, `### links`) or after a bare `related to:` line. when sibling issues share a chain of thought, list them all and bold the current one `**(this issue)**`.

Only add headings once the body is genuinely long enough to need sectioning -- most issues never get there. When they do, both kinds are in use, lowercase: **topic-named** after the actual thing (`### root cause (the skill gap)`, `### what's going on`, `## part 1: hostname rename leaves dqlite unable to elect a raft leader`), and **plain generic** for the wrapper around it (`### the issue`, `## summary`, `## steps to reproduce`, `## environment`, `### what can we do about it`, `### suggested fixes`, `### see also`, `### links`).

Length is not padded -- every sentence carries new info. Match structure to content: don't inflate a one-liner into paragraphs, and don't flatten two distinct failure modes into one blob (`## part 1:` / `## part 2:` when there genuinely are two).

References: same-repo sibling issues as bare `#N`; cross-repo as full `https://github.com/...` URLs. Never `closes #` / `fixes #` -- that's a PR convention, and it appears nowhere in the issue corpus. @-mentions are mostly credit and provenance -- who raised it, who had the good idea, whose machine it reproduced on (`proposed by @handle`, `good discussion @handle`, `courtesy of @handle`) -- and only occasionally a direct personal ask to a maintainer (`hi @user! any chance you could ...`). A table only for a real matrix (which package, which files). A `<details>` block only to fold a long env dump or log when filing into someone else's tracker -- never on a work or personal repo.

### 5. Hand it over

Output two things:

- the **title** on its own line, as inline code -- so it drops straight into the tracker's title field
- the **body** as plain markdown, not wrapped in a fence -- it carries fenced blocks of its own, and an outer fence breaks the paste

Don't post anything. The user reviews and posts. If they then ask, publish it to the tracker.
