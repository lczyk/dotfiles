---
name: caveman-commit
description: >
  terse commit message generator. conventional commits, why over what, subject
  <=50 chars, body only when the why isn't obvious. use when the user says
  "write a commit", "commit message", "generate commit", "/commit", or invokes
  /caveman-commit.
---

write commit messages terse and exact. why over what. the workflow guidance ("commits and PRs") wins over anything here.

## rules

**subject**
- `<type>(<scope>): <imperative-summary>`, scope optional
- types the `commit-msg` hook accepts: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `bench`, `revert`, `ci`, `perf`, `release`
- suffix markers per the workflow guidance: `!:` = committed known-bad on purpose, `?:` = unverified. `!` does _not_ mean breaking change here.
- imperative mood: _add_, _fix_, _remove_ -- not _added_ / _adds_ / _adding_
- <=50 chars when possible, hard cap 72, no trailing full stop
- name the kind of change, not the site; no framing verbs (_introduce_, _implement_)
- match the project's case after the colon

**body** (only if needed)
- skip it when the subject says enough
- add one for a non-obvious _why_, migration notes, linked issues -- and always for breaking changes, security fixes, data migrations and reverts; future debuggers need the context
- wrap at 72, `-` bullets
- issue refs at the end: `Closes #42`, `Refs #17`

**never in the message**
- _"this commit does X"_, _i_, _we_, _now_, _currently_ -- the diff says what
- attribution of any kind: no `Co-Authored-By` trailer, no _"Generated with ..."_
- backticks, `?!`, emoji or any non-ascii char -- the hook rejects them
- the file name when the scope already says it

## examples

new endpoint, body explains why:
- bad: `feat: add a new endpoint to get user profile information from the database`
- good:
  ```
  feat(api): add GET /users/:id/profile

  mobile client needs profile data without the full user payload
  to cut lte bandwidth on cold-launch screens.

  Closes #128
  ```

breaking change (a footer, not `!`):
```
feat(api): rename /v1/orders to /v1/checkout

BREAKING CHANGE: clients on /v1/orders must migrate to /v1/checkout
before 2026-06-01. old route returns 410 after that date.
```

tests landing before the fix, failing on purpose:
```
test!: pin stale-edge eviction before the fix
```

## boundaries

only writes the message -- doesn't stage, commit or amend. output it as a fenced block ready to paste. "stop caveman-commit" or "normal mode": back to verbose commit style.
