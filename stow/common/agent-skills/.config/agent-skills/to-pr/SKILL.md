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

Before drafting, see whether the target repo enforces a PR template (`.github/PULL_REQUEST_TEMPLATE.md`, or one a CONTRIBUTING doc points at). If it does: fill the mandated headings / checkboxes mechanically and minimally -- tick `[x]` for what's true, leave an inapplicable or not-done item unchecked (`[ ]`), or write a bare `n/a` under a heading that doesn't apply. Put the real voice in the free-text areas: the mechanism as plain prose under the template's own first heading, the *why now* / meta / caveats under `Additional Context` if there is one, or a short note after a `---` divider. Keep the template's ordering and divider: some repos put the checklist above the free text (`chisel`, Homebrew -- checkbox block, `-----`, then the body), others below (`rockcraft`, `airflow-rocks` -- body, `---`, then the checklist). Don't invent sub-headings inside a templated body, even for a big change. If the repo keeps a cross-branch ledger field (chisel-releases' `### Forward porting`), list every sibling PR as a full URL and bold the current one `**(this PR)**`. For a genuine throwaway / test PR, leaving the template entirely untouched -- boxes unchecked, HTML comments intact -- is fine. If there's no template, go freeform, as below. The template-vs-freeform split is repo-imposed, not a formality dial: a template-free team repo gets the same freeform voice as a personal one, just scaled to the change.

### 4. Draft the PR

**Title** -- `<type>(<scope>): <lowercase subject>`, no trailing full stop, 2-8 words, describing the *kind* of change abstractly rather than restating the diff. Types: `feat`, `fix`, `chore`, `test`, `refactor`, `perf`, `docs`, `ci` -- `ci` works as either the type (`ci(24.04): backport lxd launch update`) or, more often lately, the scope (`fix(ci): ...`). Optional scope in parens is a release version, component or area (`feat(26.10):`, `fix(ci):`, `fix(lxd):`, `perf(simscreen):`), never a module path; a release version is by far the most common. Drop framing verbs the prefix already implies (`add support for`, `implement`, `introduce`). Backtick an identifier only when the identifier itself *is* the point (`` fix: `no-optimize` determinism ``); otherwise keep it abstract (`chore: bump chisel to v1.4.2`, `feat: rust port`). Append `!` when the branch is intentionally broken / not fully verified (`test!: ...`). A single-commit branch usually just reuses that commit's subject. Exception: match the target repo's own strong title convention when it has one (e.g. Homebrew formula PRs).

**Body** -- the user's voice: lofi (lowercase everywhere incl. `i`, en-GB, ascii, casual short forms like `b/c` / `w/out` / `->`). Source of truth: `~/.config/agent-styles/lofi.md`. **No fixed skeleton.** the default shape is a single unstructured lowercase paragraph -- roughly half of all freeform bodies are exactly that, no bullets and no headings. reach for more structure only when the change genuinely has parts.

- **trivial / mechanical**: leave the body **empty**, or one short lowercase sentence, or just `@handle fyi`. don't manufacture a summary. a personal repo where the author is the only reviewer lands here more readily than a team repo does -- an unremarkable `feat:` in `lczyk/*` often ships with no body at all.

    judge the tier by the *narrative* you'd write, not by total body length: in a templated repo the checklist / CLA scaffolding alone is a ~400-680 char floor that says nothing about the change.
- **small-to-medium**: 1-3 sentences fusing what + why. a flat `-` bullet list is an option, not the default -- use it when there really are discrete parallel changes. optionally close with `### tests` / `tested with:` + a fenced command. a bare "yes" is a legitimate full answer under tests.
- **big / substantial** (root-cause bugfix, perf work, new feature): a prose opening saying what prompted it, usually first-person and narrative -- "noticed this while setting up a local validation pipeline", "i profiled X the way sd-tools drives it", "turns out it was at least four separate teardown bugs". then split into `##` or `###` sections, lowercase, mixing two kinds of name freely:
    - **topic-named**, after the actual bug or mechanism -- the default for a bugfix / perf PR (`### stale flushed edges`, `### the platter`, `### base-refresh masked make failures`).
    - **plain generic**, for the process wrapper and for big *feature* PRs, where a conventional structure is common (`### tests`, `### notes`, `### out of scope`, `## changes`, `## validation`, `## issue` / `## solution`, `## how it works`, `## api changes`).

    each mechanism section gets a short explanation, optional nested bullets, and an optional fenced repro with **real pasted terminal / benchmark output**. headings aren't mandatory even here: a long perf PR can stay flat prose + bullets + before/after fenced blocks.

Cross-cutting:

- lead a bugfix / perf PR with the **root-cause mechanism**, not a restatement of the diff. skip the *what* entirely when the diff is the answer.
- the first line is often nothing but the PR's relation to its neighbours: `builds on #372.`, `follow-up to #321.`, `resubmission of <url> after fork reattach surgery`, `proposed sloppy fix to <url>`, `just a proposal.`, `just an idea.`
- for a hygiene / grab-bag / review PR, open by naming the *kind of pass* rather than the changes: `proofread pass:`, `minor polish PR.`, `dashboard maintenance pass.`, `grab-bag of ci / build hygiene fixes that were quietly wrong.`
- when the change needs a grammatical subject it's `this PR` -- `this PR adds a guard to each scheduled workflow`, `this PR pins it back at 0.15.*`, `this PR makes tests much more boring`. used freely, ~30x across 100 PRs.
- label unrelated adjacent changes rather than hiding them: `driveby: narrow the event check in validate-hints.yaml`, or a `driveby fixes/feats:` list at the end after a `---`.
- lead a wip / do-not-merge / blocked PR with a loud banner on its own line at the top -- a warning-sign emoji, doubled, bracketing a shouted `WORK IN PROGRESS` or `just a joke! do not merge!` -- and say what it's blocked on.
- be realistic, not vaguely upbeat: concrete signal (tests passing, before/after sizes, `p99 240ms -> 90ms on the bench`), never "significant improvement". if there's no measurable result yet, say so plainly.
- proof is pasted terminal output in a fence, or a permalink to the CI run plus a one-line summary of what it shows (`18/18 supported lanes green; amd64 3-5m, arm64 13-26m`). for anything *visible* -- a progress bar, a rendered diagram, a dashboard -- the proof is a screenshot: leave a `<!-- screenshot here -->` placeholder for the user, before/after pair when the fix is visual.
- backtick every identifier, flag, command, filename, version string. use `X -> Y` for renames, corrections, and version bumps. `_"..."_` for a quoted concept.
- a tangent goes in round brackets as its own paragraph, spaces inside the brackets: `( i was looking into some driveby fixes but they went a bit deep ... )`.
- bold carries two small annotations beyond emphasis: a parenthetical flag on one entry in a reference or forward-port list (`**(this PR)**`, `**(new)**`, `**(not new but was also v broken)**`), and an inline label leading a bullet group in place of a further heading (`**fixes**` / `**hardening / ci**` / `**coverage**`, or `**aarch64**` / `**riscv64**` per-arch).
- credit collaborators inline (`ty @handle`, `thanks @handle for catching this`), not in a dedicated section.
- close a substantial PR with an explicit out-of-scope note ("btw, still needs ...; kept this PR small") or a direct question to a named reviewer (`wdyt @person ??`).
- if the change was substantially AI-authored, disclose it in bold (`**AI DISCLOSURE**: ...`) -- the user does this on significant AI-written contributions.
- no tables, no collapsible `<details>`, no self-review checklist in a freeform body -- checkboxes appear only inside a repo template.

References: same-repo issues / PRs as bare `#N` in prose ("follow-up to #321", "addresses #801"); cross-repo as full `https://github.com/...` URLs. `closes` / `fixes` / `addresses <ref>` never gets a line of its own -- it rides the opening sentence (`fixes <url>, backport of <url>`) or lands as the last bullet of a notes list (`- closes #90 as best as it can be closed anyway`). most PRs just reference informationally without auto-closing at all. @-mentions inline, never a "cc:" line.

### 5. Hand it over

Output two things:

- the **title** on its own line, as inline code -- so it drops straight into the PR title field.
- the **body** as plain markdown, not wrapped in a fence -- it carries fenced blocks of its own, and an outer fence breaks the paste.

Don't push and don't open the PR. The user reviews and opens it. If they then ask, open it with `gh pr create` (matching the title and body above).
