# Changelog

All notable changes to cleanloop are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [SemVer](https://semver.org/).

## [Unreleased]

## [0.2.0] — 2026-08-16
### Added
- `cleanloop init` interactive wizard (goal, tasks one per line, constraints) when run from a terminal without `--task`.
- `cleanloop add ["text"]`: append tasks to the `## Task` queue in `TASK.md`, also while the loop is running; interactive one-per-line mode without argument.
- `cleanloop tasks`: list the queue with completion marks.
- Queue semantics in the skill, session-start hook and iteration prompt: `TASK.md ## Task` is the user's queue; the *Plan* in `PROGRESS.md` mirrors it (same `Tn` ids).
### Changed
- `TASK.md` template now has `## Obiettivo`, `## Task`, `## Vincoli`, `## Definizione di fatto` sections; `PROGRESS.md` is generated with the plan pre-filled from the queue.

## [0.1.0] — 2026-08-15
### Added
- Skill `/cleanloop`: checkpoint protocol (`PROGRESS.md` + `CLAUDE.md`), resume after `/clear`/`/compact`, loop usage, anti-patterns.
- Hooks: `SessionStart` (re-injects `TASK.md` + `PROGRESS.md`), `PostToolUse` (context measured from the transcript; soft 25% / hard 40% thresholds; periodic reminders), `PreCompact` (state preservation), `Stop` (loop mode only: no exit without a `PROGRESS.md` update, blocks once).
- Runner `cleanloop.sh`: `init | run [-n] | once | status | reset | disable`; fresh `claude -p` session per iteration; stop on `DONE`, `BLOCKED`, stall, max iterations; per-iteration logs; `--autocompact` safety net.
- Project config `.cleanloop/config` (env overrides), templates for `TASK.md`/`PROGRESS.md`, iteration system prompt.
- Documentation in English and Italian (user guide + technical).
