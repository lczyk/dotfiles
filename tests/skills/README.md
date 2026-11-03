agent-config behaviour tests using [`pats`](https://github.com/lczyk/pats). each pair runs a real agent in docker with its HOME seeded from this repo's stow packages (instructions, styles, skills, hooks), then scores what it did.

needs pats >= 0.7.3 and docker. claude runs keyless off `~/.claude/.credentials.json`.

```sh
go install github.com/lczyk/pats/cmd/pats@latest
cd tests/skills
pats run      # slow, live, billed against the subscription
pats score    # offline, scores the latest run
```

not part of `make test`.

- `tasks/_lib.sh` -- copies the tracked files of the stow packages into `$PATS_AGENT_HOME`, patches the copied `settings.json` (host-only keys out, commit signing off, canary marker hooks in), and runs git the way the sandbox does.
- `tasks/prepare_<id>.sh` -- one per task: seed the HOME, lay down the fixture repo.
- `tasks/collect.sh` -- canary markers and the fixture repo's git state, for every task.
- `scorers/scorer_<id>.py` -- uv scripts, shared helpers in `scorers/_lib.py`.

run the `canary` suite first after changing the hooks or the seeding. if it scores under 1, the other results don't mean anything.

## suites

- `canary` -- the seeded hooks fire and their text reaches the agent.
- `lofi` -- the writing style, caveman off. prose tasks (chat walk-through, PR text, commit, docs, comments, en-GB, repo rules, PR template, a long run) and the skill's toggles (off, on, status, starting off, off mid-prompt).
- `caveman` -- the density mode, lofi off. a terse reply, a full-sentence commit, the `normal mode` switch.
- `lofi-caveman` -- four `lofi-*` tasks rerun with both on.

the task id prefix sets the styles the agent starts with (`_seed_home`): `lofi-*` lofi only, `cave-*` caveman only, `lofi-cave-*` both. a task that reruns another links its prompt and prepare script to it.

to try out reminder wording without editing the stow tree, set `SKILLS_LOFI_REMINDER_APPEND` on the host. prepare appends it to the seeded `lofi-reminder.md`:

```sh
env SKILLS_LOFI_REMINDER_APPEND="..." pats run -t lofi-pr-body
```

one run per pair is noisy. run a suite a few times and compare averages, not single scores.
