---
name: pr-message
description: Generate a PR description in Marcin's personal writing style. Use when the user invokes /pr-message or asks to write a PR description/message. Takes optional additional instructions as arguments.
disable-model-invocation: true
argument-hint: "[optional additional instructions]"
allowed-tools: Bash(git *)
---

Generate a pull request description for the current branch. The description must match the author's personal writing style exactly (defined below).

## Dynamic context

Current git state:
- Branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
- Commits vs main: !`git log main..HEAD --oneline 2>/dev/null || git log HEAD~5..HEAD --oneline 2>/dev/null || echo "no commits found"`
- Diff summary: !`git diff main...HEAD --stat 2>/dev/null || git diff HEAD~1 --stat 2>/dev/null || echo "no diff"`
- Full diff: !`git diff main...HEAD 2>/dev/null || git diff HEAD~1 2>/dev/null | head -300`

## Additional instructions from user

$ARGUMENTS

## Writing style rules

These rules are derived from the author's actual PR history and must be followed exactly.

**Capitalization:**
- all prose is lowercase, including the first word of sentences
- the author writes "i" not "I" — always lowercase first person
- only capitalize: proper nouns (Ubuntu, GitHub, Claude), package/binary names as they appear in code, acronyms (CI, PR, LXD, SBOM), and inline code in backticks

**Structure — match complexity to change size:**
- single small change: 1–2 sentences, no list
- multi-change: bullet list with `- item`, each item lowercase
- complex/major feature: numbered design decisions with reasoning per point

**Tone:**
- direct — no "this PR does X" opener; just state what changed
- explain *why* when non-obvious; skip it when obvious from what
- honest about scope: "i've not done X", "can be done later", "keeping this PR small"
- forward-reference related or blocked PRs with full URLs when relevant

**Formatting:**
- italics `_like this_` for caveats and warnings (e.g. `_installability tests are expected to fail_`)
- bold `**like this**` for important disclosures only
- backticks for: package names, file paths, commands, symbol names, slice names
- dash-style bullets `-`, not `*`

**What never appears:**
- "This PR...", "This commit...", "This change..."
- "## Summary", "## Test plan", "## Checklist" headers (unless the repo template requires them — in that case fill them tersely)
- verbose prose for empty/N/A sections — just write "n/a"
- excessive nesting or sub-bullets
- AI tool attribution in the body

## Task

1. Read the git diff and commit history above to understand what changed and why
2. Read the full conversation history to extract: motivation, design decisions, tradeoffs discussed, caveats mentioned, anything the author said that reveals intent
3. Synthesize a PR description that:
   - matches the writing style rules above exactly
   - covers *what* changed and *why* (when non-obvious)
   - calls out design decisions and caveats if the change is complex
   - is no longer than the change warrants — simple changes get simple descriptions
   - does NOT enumerate individual code changes (no "added X to Y.py", no "updated Z function") — describe the feature and motivation, not the implementation checklist
4. Output the PR description body wrapped in a single markdown code block (no title, no wrapper text, no explanation of what you did)

If the user passed additional instructions via $ARGUMENTS, incorporate them.

## Special case: `canonical/chisel-releases`

When the current repo is `canonical/chisel-releases` (check `git remote -v`), follow the repo's PR template exactly:

```
# Proposed changes

<prose description — same lowercase style as above>

## Related issues/PRs
<PR URLs, or "n/a">

### Forward porting
<PRs for newer supported releases, or "n/a">

## Checklist

* [x] I have read the [contributing guidelines](
https://github.com/canonical/chisel-releases/blob/main/CONTRIBUTING.md)
* [x] I have tested my changes ([see how](https://github.com/canonical/chisel-releases/blob/main/CONTRIBUTING.md#7-test-your-slices-before-opening-a-pr))
* [x] I have already submitted the [CLA form](
https://ubuntu.com/legal/contributors/agreement)
```

Additional rules for this repo:
- commit/PR titles use conventional commits: `feat(release):`, `fix(release):`, `ci:`, `chore:`, `docs:` etc.
- "Proposed changes" prose follows the same lowercase style — lead sentence states what changed, then bullets for secondary changes if any
- all checklist boxes are checked `[x]` unless there's a specific reason not to (e.g. `_installability tests are expected to fail_`)
- "Forward porting" lists sibling PRs for all newer supported Ubuntu releases; if this change only applies to one release, write "n/a". If unsure, write "...".
- omit "## Additional Context" unless there is something genuinely relevant to add
