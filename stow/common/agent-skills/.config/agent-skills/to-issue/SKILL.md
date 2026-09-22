---
name: to-issue
description: convert the most recent conversation subject -- a researched bug, enhancement or task -- into one well-formatted issue in markdown, ready to post. title and body shaped the way the user writes issues -- lowercase, freeform, repro-first, no boilerplate template. aware of a repo's own issue form.
disable-model-invocation: true
---

# to-issue

turn what we just researched into **one** issue -- markdown, ready to paste into the tracker, in the user's voice, w/out re-teaching the format each time.

## process

### 1. pick the subject

only the **most recent** conversation subject. if there's no clear one, or several distinct issues came up and the user didn't say which, ask -- don't invent or guess. if the user passed a reference (a path, an issue number or url), that _is_ the subject: fetch it and read its full body and comments.

### 2. get the facts right (optional)

if you haven't yet, look at the relevant code so the issue uses the project's real names and current state. light touch -- enough for the facts and vocabulary, not an audit.

### 3. check for a repo issue form

actually check `.github/ISSUE_TEMPLATE/` rather than assuming. freeform is still the majority upstream, but plenty of third-party repos impose a form, skewing towards the big, busy ones (cpython, vscode, mattermost, fzf, the astral-sh repos, setuptools). a form is often bug-report-only -- a chore / feature ask on the same repo may have nothing to fill in.

with a form: fill every required section, tersely. tick only boxes that are literally true (os / shell radios, "information attached" lists, maintainer-agreement acks); never blanket-tick. real voice in the free-text fields, no invented sub-headings on top of the mandated ones, and the template's instructional html comments stay in place.

no form -> freeform, below. voice tracks template presence, not personal-vs-team: a template-free upstream repo gets the same freeform voice as a personal one.

### 4. draft the issue

**title** lowercase, no full stop, one clause under ~10 words, symptom- or action-first; elaboration goes in the body. backtick commands, flags, filenames, packages and symbols (`` bug: `compile-tree -no-optimize` doesn't resolve stale edges ``) -- a strong default, though a bare flag does slip through.

- prefix matches the target repo's recent issues: `bug:` (_not_ `fix:`, that's for commits), `feat:` / `enhancement:` (interchangeable), `ci:` for the pipeline itself, `chore:`, `docs:`, `nit:` / `nitpick:` for a cosmetic papercut.
- optional scope in parens -- release version, component or subsystem (`bug(26.10):`, `feat(testing):`, `bug(reviewer):`). a work / shared-repo device; essentially never on personal or upstream repos.
- a repo with no tag convention (most third-party oss) allows a plain symptom phrase, but the tag usually stays anyway (`bug: malformed writer stream for size=0` on `ulikunitz/xz`).
- `?:` when unsure the report is even valid (`bug?: ...`, `feat?: ...`).

**body** lofi voice (`~/.config/agent-styles/lofi.md`); ascii applies to your own prose only -- a pasted transcript, log or ui string keeps its glyphs. no fixed template. the default is short: a couple of lowercase sentences, often plus one code fence; headings are rare. the tag guides length: `nit:` / `enhancement:` 2-4 lines, `bug:` a short paragraph + evidence, `ci:` the longest b/c it carries a pasted failure log.

- open directly on the symptom / claim / context; the first sentence states the fact. no greeting, no _"i noticed"_, no preamble. a bug opens on the failing behaviour, stated flatly; a feature / enhancement / nit opens on current behaviour (`at the moment ...`, `at present ...`, `atm ...`, `currently ...`), then the ask.
- the ask is `we should ...` -- the standing modal, used freely (`we should add a teardown fixture`).
- a provenance line when it came from somewhere identifiable: `raised here: <url>`, `spotted by copilot while reviewing #171`, `see title. proposed by @handle`.
- evidence is the load-bearing part:
    - a fenced pasted terminal transcript / log / error -- the most common device
    - a minimal runnable repro: a short shell / python / go snippet, sometimes literally `mwe.py`, or a paste-into-`foo_test.go` test that fails on the bug
    - expected-vs-actual is usually just the pasted output. for a hand-run snippet, an inline comment on the relevant line (`print(a.height, a.width)  # None None, expected 512 512`); never a separate expected / actual heading pair.
    - a ci run permalink (`.../actions/runs/<id>`), often with a pasted excerpt -- common on ci-heavy work repos, rare elsewhere
    - a screenshot for anything visible -- the next most common device after a fence, sometimes the whole body. leave `<!-- screenshot here -->` for the user.
    - a `>` blockquote for a quoted doc / upstream excerpt; `_"..."_` for a short inline phrase
    - a version / env block when it might matter: pasted `--version` + `git rev-parse HEAD`, or a `## environment` list
- repro steps as a numbered list when reaching the failure takes a sequence.
- a root-cause guess stays hedged (_i think_, _looks like_, _seems to be_, _unsure_, a trailing `...?`, `?` or `??`) unless verified.
- fix ideas / open qs go last, under a heading of their own as often as a bare `-` list (`## fix ??`, `**fix proposal**`, `### suggested fixes`, `possible fixes, not mutually exclusive:`). a `diff` fence when the fix is a couple of lines.
- links: one inline (`see https://...`); several as a trailing list of bare urls under `### see also` / `### links`, or after a bare `related to:` line. sibling issues sharing a chain of thought: list them all, bold the current one `**(this issue)**`.

headings only once the body genuinely needs sectioning -- most issues never get there. then lowercase, either topic-named after the actual thing (`### root cause (the skill gap)`, `## part 1: hostname rename leaves dqlite unable to elect a raft leader`) or plain generic (`### the issue`, `## summary`, `## steps to reproduce`, `## environment`, `### see also`). no padding -- every sentence carries new info. don't inflate a one-liner into paragraphs, and don't flatten two failure modes into one blob (`## part 1:` / `## part 2:`).

references: same-repo sibling issues as bare `#N`; cross-repo as full `https://github.com/...` urls. never `closes #` / `fixes #` -- that's a PR convention, absent from past issues. @-mentions are mostly credit and provenance (`proposed by @handle`, `good discussion @handle`, `courtesy of @handle`), only occasionally a direct ask (`hi @user! any chance you could ...`). a table only for a real matrix. `<details>` only to fold a long env dump / log in someone else's tracker, never on a work or personal repo.

### 5. hand it over

- the **title** on its own line as inline code, for the title field
- the **body** as plain markdown, not fenced -- it has fences of its own and an outer one breaks the paste

don't post anything; `gh` writes are blocked anyway. the user reviews and posts -- if they want a command, give them the matching `gh issue create`.
