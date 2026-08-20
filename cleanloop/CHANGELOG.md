# Changelog

All notable changes to cleanloop are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [SemVer](https://semver.org/).

## [Unreleased]

## [0.6.1] — 2026-08-20
### Fixed
- `cleanloop_context_window()` autodetect ignored `CLEANLOOP_MODEL` (the model actually passed to `claude --model` for this project's iterations) and only ever read the global, user-wide `~/.claude/settings.json` `.model` field. `CLEANLOOP_MODEL` is now checked first, falling back to the global setting only when no per-project model is configured.
- `cleanloop_context_window()`'s core heuristic — guessing 1M vs 200k from a literal `[1m]` substring in the model name/settings — was based on an older model generation and no longer matches reality: verified live (see below) that no current Claude model name or setting ever carries `[1m]`, yet a plain `"sonnet"` session was actually running at 1M context, making cleanloop report ~5x the real percentage (94% computed vs. 19% shown by the actual status line for the same session). Replaced with: 200k if the model name contains "haiku", otherwise 1M — every current Claude model has a 1M standard context window except Haiku 4.5, confirmed against the live model table.
- Root-caused by live-instrumenting the actually-running `context-guard.sh` (not just the dev copy) to dump its real `PostToolUse` hook input: confirmed Claude Code never sends a `context_window` field to that hook (only the Statusline hook receives it), so cleanloop's window can only ever be inferred, never read — documented this limitation in `docs/*/technical/architecture.md` and `docs/*/user-guide/troubleshooting.md`, and pointed users at `CLEANLOOP_CONTEXT_WINDOW` as the reliable override when the model-name guess doesn't match their actual plan.

### Investigated, left as-is (by design, documented)
- **Fixed per-session token floor.** Measured directly (character-counted the actual system-prompt text for a real multi-plugin setup): a session's first assistant turn — before any work — already spends a few thousand tokens on the user's own enabled plugins/skills, plus a much larger amount (typically 90%+ of the floor) on Claude Code's own core system prompt and native tool schemas, which cleanloop has no visibility into or control over. Since `CLEANLOOP_THRESHOLD`/`CLEANLOOP_HARD` are absolute percentages of the window (not relative to session start), a large floor can make the soft/hard threshold fire almost immediately after every checkpoint in interactive use, independent of the window-size fix above. Considered and explicitly declined: measuring `used` relative to the post-`SessionStart` baseline instead of absolute window %. Documented as a known limitation with the workaround (raise the thresholds) in `docs/*/user-guide/troubleshooting.md`.
- **`.cleanloop/state/last.json` is one file per project, not per session.** Two concurrent Claude Code sessions on the same project can overwrite each other's last-measurement snapshot, so `cleanloop status` and the LOOPLOG `↻` row's `prev_ctx` can occasionally show a reading that belongs to the other session. Cosmetic only — the hard/soft threshold check itself always reads the *current* session's own transcript, never this file — so left unfixed and documented in `docs/*/user-guide/troubleshooting.md`.

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
