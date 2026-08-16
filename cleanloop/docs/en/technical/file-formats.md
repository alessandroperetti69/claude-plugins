# File formats

## `TASK.md` (written by the user)
Free text, but the runner and the skill expect a **Definition of done** section with checkboxes: it is the condition the model must verify before writing `STATUS: DONE`. Template in `templates/TASK.md`:
```markdown
# TASK
<goal, context, what NOT to touch>

## Definition of done
- [ ] <condition verifiable with a command>

## Constraints
- ...
```
Injected by the `SessionStart` hook (first 6000 bytes).

## `PROGRESS.md` (rewritten by Claude at each checkpoint)
The first two lines after the title are **read by the runner** with `grep`:
```
STATUS: IN_PROGRESS      # IN_PROGRESS | DONE | BLOCKED   (start of line, uppercase)
ITERATION: 3             # integer
```
Expected sections (template in `templates/PROGRESS.md`):
| Section | Content |
|---|---|
| Goal (1 line) | what must be true at the end |
| Done | concise bullets, with "how verified" |
| In progress | what is half-done and exactly where (normally empty at a checkpoint) |
| Next step (handoff) | file, command, what to verify: enough to resume with an empty context |
| Plan (sub-tasks, tick) | sub-task checklist |
| Decisions | choice + reason, 1 line each |
| Pitfalls / notes | things that waste time |
| Verification | command(s) to check that it works |

Constraints: ~40 lines max, **replace** rather than accumulate (the file is re-injected in full at every iteration, first 8000 bytes). An iteration's progress is detected via the file checksum: an iteration that does not modify it counts as a stall.

## `CLAUDE.md`
No format imposed by cleanloop. Rule: durable facts only (commands, conventions, constraints, environment gotchas), 1-3 lines per checkpoint, never progress state.

## `.cleanloop/config`
Shell file sourced by `lib.sh`; each line is `export CLEANLOOP_X="${CLEANLOOP_X:-default}"` so the environment takes precedence. Variable list in [Configuration](../user-guide/configuration.md).

## `.cleanloop/enabled`
Empty file; its existence enables the hooks in the project.

## `.cleanloop/state/`
| File | Content |
|---|---|
| `last.json` | `{"session","used","window","pct","ts"}` — last context measurement (any session) |
| `<session_id>.start` | checksum of `PROGRESS.md` at session start (used by the Stop hook) |
| `<session_id>.level` | `0`/`1`/`2`: warning level already emitted |
| `<session_id>.count` | tool calls since the last warning (for reminders) |

## `.cleanloop/logs/`
`iter-<NNN>-<YYYYmmdd-HHMMSS>.log`: full `claude -p` output for iteration `NNN`.
