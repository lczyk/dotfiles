---
name: hat
description: >
  Switch behavioral "hats" for this agent session. Two hats: default (normal engineering
  care) and yolo (rapid devel-mode -- skip worrying about api/back-compat breakage, less
  hesitation before refactoring, bundle commits instead of splitting for a clean history).
  State is per-session -- other concurrent sessions are unaffected. Use when the user says
  "yolo mode", "devel mode", "let's move fast", "switch hats", or invokes /hat. Bare /hat
  reports the current hat.
argument-hint: "[yolo|default]"
---

hat = which behavioral mode this session runs under. state is per-session -- switching hats
in one session never touches another concurrently running session.

## commands

`/hat` -- report the current hat, nothing else.
`/hat yolo` -- switch to yolo.
`/hat default` -- switch back to default. also the resting state for every new session.

## hats

| hat | what changes |
|-----|--------------|
| **default** | normal engineering care. nothing here overrides the global instructions. |
| **yolo** | devel-mode. skip worrying about api/back-compat breakage, hesitate less before refactoring or renaming, bundle related commits instead of splitting them for a clean history. |

## yolo does NOT touch

the testing-before-commit gate. commit message conventions (prefixes, no self-attribution --
hooks enforce these regardless of hat). every git/gh permission tier (push, branch,
force-push, rebase -- hard-fenced; a hat is instructions, not a permission grant, and cannot
lift an `AGENT_UNFENCE` gate). security/OWASP care. the judgement to pause before an
irreversible or shared-state action. yolo changes engineering-carefulness pace, not the
safety rails.

## persistence

active every response while yolo, reinforced every turn. a fresh session always starts on
default; a resumed session keeps whatever hat it had when it left off. back to default:
`/hat default`.
