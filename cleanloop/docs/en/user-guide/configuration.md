# Configuration (reference)

## Where it is configured
Precedence (highest first): **environment variable** → project `.cleanloop/config` → default. `.cleanloop/config` is a shell file created by `init`, using the pattern `export VAR="${VAR:-default}"`, so the environment always wins.

## Variables

| Variable | Default | Effect |
|---|---|---|
| `CLEANLOOP_THRESHOLD` | `25` | % of the window above which the hook requests a checkpoint (soft threshold) |
| `CLEANLOOP_HARD` | `40` | % above which it asks to stop immediately (hard threshold) |
| `CLEANLOOP_REMIND_EVERY` | `6` | after the threshold, repeat the reminder every N tool calls |
| `CLEANLOOP_MAX_ITER` | `20` | maximum iterations for `run` (overridable with `-n`) |
| `CLEANLOOP_STALL_LIMIT` | `3` | consecutive iterations without changes to `PROGRESS.md` before stopping for stall |
| `CLEANLOOP_PERMISSION_MODE` | `auto` | `--permission-mode` passed to `claude -p`: `auto`, `acceptEdits`, `bypassPermissions` (sandbox only) |
| `CLEANLOOP_MODEL` | *(empty)* | model for iterations (`sonnet`, `opus`, full id); empty = user default |
| `CLEANLOOP_MAX_BUDGET_USD` | *(empty)* | spending cap **per iteration** (`--max-budget-usd`) |
| `CLEANLOOP_CONTEXT_WINDOW` | *(autodetect)* | window tokens; if empty: 1,000,000 when the model in `~/.claude/settings.json` contains `[1m]`, otherwise 200,000 |
| `CLEANLOOP_PROGRESS_FILE` | `PROGRESS.md` | progress file name |
| `CLEANLOOP_TASK_FILE` | `TASK.md` | task file name |
| `CLEANLOOP_LOG_FILE` | `LOOPLOG.md` | name of the readable log (exits/restarts table) |
| `CLEANLOOP_ACTIVE` | *(set by the runner)* | `1` = loop mode: enables the `Stop` hook and the "end the turn" messages |

### Choosing thresholds
The threshold is a percentage of the window: with a 1M-token model, 25% = 250k tokens, already a lot of work per iteration. Indicative values:
- 200k window: 25/40 (default) is fine;
- 1M window: try 15/25 for shorter iterations and more frequent restarts.

## Runner commands

```
cleanloop init [--task "text"]    creates TASK.md, PROGRESS.md, .cleanloop/{config,enabled,state,logs}; updates .gitignore.
                                  From a terminal without --task: wizard (goal, tasks one per line, constraints)
cleanloop add  ["text"]           appends a task (T<n>) to TASK.md; without argument: interactive (multi-line tasks:
                                  empty line = next, lone "." = end)
cleanloop tasks                   lists the queue with ✔ on tasks ticked in the Plan and "(+n righe)" for multi-line tasks
cleanloop run  [-n N]             loop until DONE/BLOCKED/stall/max iterations
cleanloop once                    a single iteration (= run -n 1)
cleanloop status                  state: active, STATUS, ITERATION, thresholds, window, last context %, last LOOPLOG.md rows and last 5 events
cleanloop log [-n N]              event log (iteration starts/ends, thresholds, restarts) with context %; -n = last N lines
cleanloop reset                   deletes .cleanloop/state (leaves PROGRESS.md and logs untouched)
cleanloop disable                 removes .cleanloop/enabled: hooks inert in the project
```
`init` and `run` check for `jq` (and `run` for `claude`).

## Runner exit codes
| Code | Meaning |
|---|---|
| `0` | `STATUS: DONE` |
| `1` | usage error or missing prerequisite (`jq`, `claude`, missing files, project not initialised) |
| `2` | stall: `CLEANLOOP_STALL_LIMIT` iterations without changes to `PROGRESS.md` |
| `3` | `STATUS: BLOCKED` |
| `4` | maximum iterations reached without `DONE` |

## Files and folders in the project
```
TASK.md                 task and definition of done (yours)
PROGRESS.md             progress state (Claude's)
LOOPLOG.md              readable log: one row per iteration exit / restart, with context %
.cleanloop/config       project configuration
.cleanloop/enabled      switch: if present, hooks are active here
.cleanloop/state/       last.json (last context measurement), per-session markers (level, counter, initial checksum)
.cleanloop/logs/        iter-NNN-<timestamp>.log (output of each iteration) and events.log (event log)
```
`state/` and `logs/` are added to `.gitignore` by `init` (if the project is a git repo).
