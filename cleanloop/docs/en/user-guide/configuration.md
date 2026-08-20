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
| `CLEANLOOP_EFFORT` | *(empty)* | `--effort` passed to `claude -p`: `low`, `medium`, `high`, `xhigh`, `max`; empty = session default |
| `CLEANLOOP_MAX_BUDGET_USD` | *(empty)* | spending cap **per iteration** (`--max-budget-usd`) |
| `CLEANLOOP_CONTEXT_WINDOW` | *(autodetect)* | window tokens; if empty: 200,000 when the model (`CLEANLOOP_MODEL`, or failing that the global one in `~/.claude/settings.json`) contains "haiku", otherwise 1,000,000 (every current Claude model has 1M except Haiku) |
| `CLEANLOOP_PROGRESS_FILE` | `PROGRESS.md` | progress file name |
| `CLEANLOOP_TASK_FILE` | `TASK.md` | task file name |
| `CLEANLOOP_LOG_FILE` | `LOOPLOG.md` | name of the readable log (exits/restarts table) |
| `CLEANLOOP_USE_SUBAGENTS` | `0` | `1` = the iteration considers parallelism: independent tasks in the queue are delegated to subagents (Agent tool) instead of done sequentially |
| `CLEANLOOP_ACTIVE` | *(set by the runner)* | `1` = loop mode: enables the `Stop` hook and the "end the turn" messages |

### Subagents (`CLEANLOOP_USE_SUBAGENTS`)
With `1`, the iteration prompt instructs the main turn to: check whether the pending tasks in the queue are independent (no dependency, no shared files) and, if so, launch them in parallel with the Agent tool; have subagents return their result as text (not write files — some file-name patterns are blocked for subagents) and apply the changes itself; write `PROGRESS.md` only itself, at the end of the turn, after collecting all results.

Iterations always run with `--forward-subagent-text`: lines produced by subagents show up in the log (`.cleanloop/logs/iter-NNN-*.log`, and in the terminal if you run `run`/`once` in the foreground) tagged with the last 6 characters of the subagent's id, e.g.:
```
  → subagente [7SuPBn] "count the lines in a.txt"
  [7SuPBn] → Bash
  [7SuPBn] Ran wc -l: 42 lines.
```
To follow them live during a background `run`: `tail -f .cleanloop/logs/iter-NNN-*.log` (the exact name is printed by `run`/`once` at the start of the iteration, or find the latest with `ls -t .cleanloop/logs/iter-*.log | head -1`).

### Choosing thresholds
The threshold is a percentage of the window: with a 1M-token model, 25% = 250k tokens, already a lot of work per iteration. Indicative values:
- 200k window: 25/40 (default) is fine;
- 1M window: try 15/25 for shorter iterations and more frequent restarts.

## Configuring from the command line

Every variable above (except `CLEANLOOP_ACTIVE`, set by the runner) can be set from the CLI, without hand-editing `.cleanloop/config`:

- **at setup**, with `cleanloop init`: each variable has a matching flag (`--threshold`, `--hard`, `--max-iter`, `--stall-limit`, `--remind-every`, `--permission-mode`, `--model`, `--effort`, `--max-budget-usd`, `--context-window`, `--progress-file`, `--task-file`, `--log-file`, `--use-subagents`). E.g.:
  ```bash
  cleanloop init --task "Paginate API" --threshold 15 --hard 25 --permission-mode acceptEdits
  ```
- **at setup, interactively**: the wizard (`cleanloop init` from a terminal, without `--task`/`--brief`) asks, after goal/tasks/constraints, for model (menu with aliases + "other" for a full id), effort, permission mode, subagent use, thresholds, budget and max iterations, in sequence — **enter keeps the shown default** (which reflects any flags already passed to `init`). It ends with a yes/no question for advanced parameters (reminder cadence, context window, log name); `TASK.md`/`PROGRESS.md` names aren't editable there (already written by that point) — only via flags or by hand.
- **after setup**, with `cleanloop config KEY=VALUE` (variable name without the `CLEANLOOP_` prefix, multiple pairs at once). With no arguments it prints the current config:
  ```bash
  cleanloop config                          # show .cleanloop/config
  cleanloop config THRESHOLD=15 HARD=25     # update two thresholds
  cleanloop config MODEL=                   # clear it: back to the user default
  ```
- **re-running `init`** with new flags on an already-initialised project: updates only the passed keys, without touching an existing `TASK.md`/`PROGRESS.md`.
- **one-off, on `run`/`once`**: the same options act as overrides for that run only, without writing `.cleanloop/config` (useful to try a different model/threshold without changing the project's saved configuration):
  ```bash
  cleanloop once --model opus --effort high        # one iteration with different params, one-off
  cleanloop run -n 5 --permission-mode acceptEdits  # 5 iterations with different permissions than the default
  ```

Every value is validated (integers for thresholds, one of the three modes for `--permission-mode`, etc.) before being written; on error the config file is left untouched.

## Task input: brief instead of the wizard

An alternative to the wizard/`--task`: feed a free-form prompt or a document and let the **first iteration** organise the queue itself (Goal + `Tn`), instead of structuring it by hand. Also useful to avoid the line-by-line paste problem in the wizard (text with line breaks/bullets gets mangled in an interactive TTY prompt).

It activates in one of these ways, in priority order on `init`:
1. `cleanloop init --brief PATH` — reads the given file
2. `cleanloop init --brief -` — reads stdin explicitly
3. `BRIEF.md` already present at the project root when `init` runs (no flag needed)
4. non-interactive stdin with content, no flags: `pbpaste | cleanloop init` (if stdin is empty or non-interactive with no data, it falls back to normal behaviour)

In every case the content ends up in `BRIEF.md` (project root, tracked in git like `TASK.md`/`PROGRESS.md`), and `TASK.md` is generated with a single `T1` asking the first iteration to read `BRIEF.md`, derive the goal and the real queue, and rewrite `TASK.md` accordingly — **without** starting any application work in that turn (planning only). `PROGRESS.md` gets a dedicated handoff spelling this out. After `init` in brief mode it's best to run `cleanloop once` and review `TASK.md` before letting `run` proceed unsupervised.

`--task` always takes priority over `--brief` if both are passed.

## Runner commands

```
cleanloop init [--task "text" | --brief PATH|-] [config options]  creates TASK.md, PROGRESS.md,
                                  .cleanloop/{config,enabled,state,logs}; updates .gitignore. From a terminal with no
                                  flags: wizard, unless a brief is auto-detected (see above). Config options (see
                                  above) can also be applied by re-running init on an already-initialised project.
cleanloop add  ["text"]           appends a task (T<n>) to TASK.md; without argument: interactive (multi-line tasks:
                                  empty line = next, lone "." = end)
cleanloop tasks                   lists the queue with ✔ on tasks ticked in the Plan and "(+n righe)" for multi-line tasks
cleanloop run  [-n N] [config options]  loop until DONE/BLOCKED/stall/max iterations. Config options (see above)
                                  act as overrides for this run only, without writing .cleanloop/config.
cleanloop once [config options]   a single iteration (= run -n 1, same overrides as run)
cleanloop status                  state: active, STATUS, ITERATION, thresholds, window, last context %, last LOOPLOG.md rows and last 5 events
cleanloop config [KEY=VALUE ...]  no arguments: shows .cleanloop/config; with arguments: validates and updates the given keys
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
BRIEF.md                (brief mode only) starting prompt/document the first iteration derives TASK.md from
PROGRESS.md             progress state (Claude's)
LOOPLOG.md              readable log: one row per iteration exit / restart, with context %
.cleanloop/config       project configuration
.cleanloop/enabled      switch: if present, hooks are active here
.cleanloop/state/       last.json (last context measurement), per-session markers (level, counter, initial checksum)
.cleanloop/logs/        iter-NNN-<ts>.log (readable output), iter-NNN-<ts>.jsonl (raw stream), events.log (event log)
```
`state/` and `logs/` are added to `.gitignore` by `init` (if the project is a git repo).
