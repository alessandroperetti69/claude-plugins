# Changelog

All notable changes to cleanloop are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [SemVer](https://semver.org/).

## [Unreleased]

## [0.6.0] — 2026-08-20
### Added
- `cleanloop init` accepts a flag per config variable (`--threshold`, `--hard`, `--max-iter`, `--stall-limit`, `--remind-every`, `--permission-mode`, `--model`, `--max-budget-usd`, `--context-window`, `--progress-file`, `--task-file`, `--log-file`), written into the generated `.cleanloop/config`; re-running `init` on an already-initialised project updates only the passed keys.
- `cleanloop config [KEY=VALUE ...]`: prints `.cleanloop/config` with no arguments, or validates and updates the given keys in place.
- All config values are validated before being written (integers for thresholds/limits, allowed set for `--permission-mode`, non-empty file names).
- `CLEANLOOP_USE_SUBAGENTS` (0/1, default 0): when enabled, the iteration prompt asks the main turn to delegate independent queued tasks to subagents (Agent tool) in parallel, have them report results as text (not write files), and apply changes / write `PROGRESS.md` itself. Iterations now always run with `--forward-subagent-text`; `stream_pretty()` tags subagent output lines with the launching tool_use id's last 6 characters so parallel subagents can be followed live in the iteration log.
- Brief mode for task input: `cleanloop init --brief PATH|-`, an existing `BRIEF.md` at the project root, or piped non-interactive stdin (`pbpaste | cleanloop init`) all save the given text to `BRIEF.md` and generate a `TASK.md` with a single planning `T1`; the first iteration reads the brief, derives the goal and real task queue, and rewrites `TASK.md` before doing any application work. Fixes the terminal line-by-line paste breaking on multi-line/bulleted text.
- `CLEANLOOP_EFFORT` (low/medium/high/xhigh/max, empty = session default): passed as `--effort` to iteration sessions; configurable via `--effort` on `init` or `cleanloop config`.
- The interactive `init` wizard now asks for model (menu with aliases + custom id), effort, permission mode, subagent use, thresholds, budget and max iterations after goal/tasks/constraints, with enter keeping the current default; a yes/no gate offers advanced parameters (reminder cadence, context window, log file name).
- `cleanloop run`/`once` accept the same config flags as `init` (plus `--max-iter` as an alias for `-n`) as one-off overrides for that run, without writing `.cleanloop/config`.
### Fixed
- `cleanloop init` (and any other command building a config from CLI flags) crashed with "unbound variable" on macOS's default bash 3.2 when no config flags were passed, due to referencing an empty array under `set -u`.

## [0.5.0] — 2026-08-16
### Added
- Per-iteration **model, tokens and API-equivalent cost**: iterations run with `--output-format stream-json`; the runner prints model at start, text/tools live, and a summary at the end; `LOOPLOG.md` gains `Modello`, `Token iterazione`, `Costo API eq.` columns; `iter_end` events carry `model tokens_in tokens_out cost_usd turns`. Raw stream saved as `iter-NNN-<ts>.jsonl`.
### Notes
- Subscription rate limits (5h/7d) are not exposed to `-p` sessions or hooks; use `/usage` interactively.

## [0.4.0] — 2026-08-16
### Added
- `LOOPLOG.md` next to `TASK.md`/`PROGRESS.md`: readable table with one row per iteration exit (`# | Ora | Contesto all'uscita | Motivo | STATUS`), plus `↻` rows for interactive `/clear`/`/compact` restarts with the context before the restart. Created by `init`; name via `CLEANLOOP_LOG_FILE`.
- `cleanloop status` shows the last `LOOPLOG.md` rows.

## [0.3.0] — 2026-08-16
### Added
- Event log `.cleanloop/logs/events.log`: `loop_start`, `iter_start`, `session_start` (with `prev_ctx`, the context % before the restart), `threshold` (soft/hard), `iter_end` (duration, exit code, context %, reason, progress, status), `loop_stop` (reason). Written by the runner and by the hooks, so it also covers interactive sessions with `/clear`.
- `cleanloop log [-n N]`; `cleanloop status` shows the last 5 events.

## [0.2.1] — 2026-08-16
### Changed
- Wizard and interactive `add` accept **multi-line tasks** (paste-friendly): an empty line moves to the next task, a lone `.` (or Ctrl-D) ends the list. Continuation lines are stored indented under the bullet in `TASK.md`; `tasks` shows `(+n righe)`.

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
