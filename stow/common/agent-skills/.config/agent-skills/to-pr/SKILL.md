---
name: to-pr
description: write up all the changes on the current branch as one pull request in markdown, ready to open. title and body shaped the way the user writes PRs -- lowercase, freeform, length-driven, root-cause-first, no boilerplate template. aware of a repo's own PR template. reads the branch diff and commits; never pushes or opens the PR.
disable-model-invocation: true
---

# to-pr

turn the changes on the current branch into **one** PR -- markdown, ready to paste into the PR form, in the user's voice, w/out re-teaching the format each time.

## process

### 1. establish the diff range

- current branch: `git branch --show-current`
- base: the default branch (`main` / `master`), unless the branch clearly forks from something else. fork point: `git merge-base HEAD <base>`
- range: `<merge-base>..HEAD`

if the current branch **is** the default branch, there's nothing to write up -- tell the user and stop, don't diff against a guess.

### 2. read the changes

read, don't skim: `git log <base>..HEAD` (subjects and bodies carry the intent), then `git diff <base>..HEAD --stat` and the diff itself. explore surrounding code only if the diff doesn't give the real names or the _why_; the _why_ may also live in the conversation.

### 3. check for a repo PR template

look for `.github/PULL_REQUEST_TEMPLATE.md`, or one a `CONTRIBUTING` doc points at. no template -> freeform, below. the split is repo-imposed, not a formality dial: a template-free team repo gets the same freeform voice as a personal one, scaled to the change.

with a template:

- fill the mandated headings / checkboxes mechanically and minimally: `[x]` for what's true, `[ ]` for what isn't or wasn't done, a bare `n/a` under a heading that doesn't apply.
- real voice goes in the free text: the mechanism as prose under the template's first heading; _why now_ / meta / caveats under `Additional Context` if there is one, else a short note after a `---`.
- keep the template's order and divider. some put the checklist first (`chisel`, homebrew: checkboxes, `-----`, body), others last (`rockcraft`, `airflow-rocks`: body, `---`, checklist).
- no invented sub-headings inside a templated body, even for a big change.
- a cross-branch ledger field (chisel-releases' `### Forward porting`) lists every sibling PR as a full url, the current one bolded `**(this PR)**`.
- a genuine throwaway / test PR may leave the template untouched -- boxes unchecked, html comments intact.

### 4. draft the PR

**title** `<type>(<scope>): <lowercase-subject>`, no full stop, 2-8 words, the _kind_ of change rather than a restated diff.

- types: `feat`, `fix`, `chore`, `test`, `refactor`, `perf`, `docs`, `ci`. `ci` works as the type (`ci(24.04): backport lxd launch update`) or, more often lately, the scope (`fix(ci): ...`).
- scope: a release version (the most common), component or area (`feat(26.10):`, `fix(lxd):`, `perf(simscreen):`), never a module path.
- no framing verbs (_add support for_, _implement_, _introduce_).
- backtick an identifier only when it _is_ the point (`` fix: `no-optimize` determinism ``); otherwise stay abstract (`chore: bump chisel to v1.4.2`, `feat: rust port`).
- markers as in the workflow guidance: `!` for an intentionally broken / known-bad branch (`test!: ...`), `?` for one that's believed fine but not fully verified (`fix?: ...`).
- a single-commit branch usually reuses that commit's subject. a repo's own strong title convention wins (e.g. homebrew formula PRs).

**body** lofi voice (`~/.config/agent-styles/lofi.md`). no fixed skeleton: the most common shape is one unstructured lowercase paragraph, no bullets, no headings. add structure only when the change genuinely has parts. judge the tier by the narrative you'd write, not total length -- in a templated repo the checklist / CLA scaffolding alone is a few hundred chars that say nothing about the change.

- **trivial / mechanical** empty body, one short sentence, or `@handle fyi`. don't manufacture a summary. a personal `lczyk/*` repo lands here more readily than a team one -- an unremarkable `feat:` often ships with no body at all.
- **small-to-medium** 1-3 sentences fusing what + why. a flat `-` list is an option for genuinely parallel changes, not the default. optionally close with `### tests` / `tested with:` + a fenced command; a bare "yes" is a legit full answer under tests.
- **big** (root-cause bugfix, perf work, new feature) open with what prompted it, usually first-person narrative (_"noticed this while setting up a local validation pipeline"_, _"turns out it was at least four separate teardown bugs"_). then lowercase `##` / `###` sections, freely mixing topic-named ones after the actual bug or mechanism -- the default for bugfix / perf (`### stale flushed edges`, `### the platter`) -- and plain generic ones for process wrappers and big features (`### tests`, `### notes`, `### out of scope`, `## how it works`, `## api changes`). each mechanism gets a short explanation, optional nested bullets and an optional fenced repro with real pasted terminal / benchmark output. headings stay optional even here; a long perf PR can be flat prose + bullets + before / after fences.

cross-cutting:

- lead a bugfix / perf PR with the root-cause mechanism, not a restated diff; skip the _what_ when the diff says it.
- the first line is often just the PR's relation to its neighbours: `builds on #372.`, `follow-up to #321.`, `resubmission of <url> after fork reattach surgery`, `just a proposal.`
- a hygiene / grab-bag / review PR opens by naming the _kind of pass_: `proofread pass:`, `minor polish PR.`, `grab-bag of ci / build hygiene fixes that were quietly wrong.`
- when the change needs a grammatical subject it's `this PR` (_"this PR pins it back at 0.15.*"_), used freely.
- label unrelated adjacent changes rather than hiding them: `driveby: narrow the event check in validate-hints.yaml`, or a `driveby fixes/feats:` list after a `---`.
- a wip / do-not-merge / blocked PR opens with a loud ascii banner on its own line (`!! WORK IN PROGRESS !!`, `!! just a joke! do not merge !!`) and says what it's blocked on.
- realistic, not upbeat: concrete signal (tests passing, before / after sizes, `p99 240ms -> 90ms on the bench`), never _"significant improvement"_. no measurement yet -> say so.
- proof is pasted terminal output in a fence, or a ci run permalink + a one-line summary (`18/18 supported lanes green; amd64 3-5m, arm64 13-26m`). anything visible (progress bar, diagram, dashboard) gets a screenshot: leave `<!-- screenshot here -->`, a before / after pair for visual fixes.
- backtick every identifier, flag, command, filename, version string. `X -> Y` for renames, corrections and version bumps. `_"..."_` for a quoted concept.
- a tangent goes in round brackets as its own paragraph, spaces inside: `( i was looking into some driveby fixes but they went a bit deep ... )`.
- bold marks a flag on one entry of a reference / forward-port list (`**(this PR)**`, `**(new)**`, `**(not new but was also v broken)**`) or labels a bullet group in place of a heading (`**fixes**`, `**hardening / ci**`, `**aarch64**`).
- credit inline (`ty @handle`, `thanks @handle for catching this`), not in a section.
- close a substantial PR with an out-of-scope note (_"btw, still needs ...; kept this PR small"_) or a direct q to a named reviewer (`wdyt @person ??`).
- a substantially ai-authored change gets a bold disclosure: `**AI DISCLOSURE**: ...`.
- no tables, no `<details>`, no self-review checklist in a freeform body; checkboxes only inside a repo template.

references: same-repo issues / PRs as bare `#N` in prose (_"follow-up to #321"_); cross-repo as full `https://github.com/...` urls. `closes` / `fixes` / `addresses <ref>` never gets its own line -- it rides the opening sentence (`fixes <url>, backport of <url>`) or ends a notes list (`- closes #90 as best as it can be closed anyway`); most PRs just reference w/out auto-closing. @-mentions inline, never a `cc:` line.

### 5. hand it over

- the **title** on its own line as inline code, for the title field
- the **body** as plain markdown, not fenced -- it has fences of its own and an outer one breaks the paste

don't push or open the PR; `gh` writes are blocked anyway. the user reviews and opens it -- if they want a command, give them the matching `gh pr create`.
