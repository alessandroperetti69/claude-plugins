# Runner `cleanloop.sh`

Bash script (`scripts/cleanloop.sh`) orchestrating the fresh-session loop. It uses neither `timeout` (absent on macOS) nor dependencies beyond `bash`, `jq`, `claude`, `md5|md5sum`.

## Commands
See [Configuration → Runner commands](../user-guide/configuration.md#runner-commands). Internals below.

### `init`
1. `need_jq`.
2. Creates `.cleanloop/{state,logs}` and the empty file `.cleanloop/enabled`.
3. If missing, writes `.cleanloop/config` with every variable in the `export VAR="${VAR:-default}"` pattern.
4. If `TASK.md` is missing: with `--task` it generates it with goal = text and `T1` = text; if stdin is a terminal it opens the wizard (`read` for goal, tasks, constraints); otherwise it copies the template. If `PROGRESS.md` is missing, it generates it with Goal and Plan derived from `TASK.md`.

### `add ["text"]`
Inserts the block `- [ ] T<max+1>: first line` + indented continuations at the end of the `## Task` section of `TASK.md` (awk: first empty line after the heading; the block is passed via a temp file). Without argument and with a terminal stdin: `read_block` loop — an empty line closes the task, a lone `.` or EOF closes the list. Does not touch `PROGRESS.md` (aligning the Plan is the model's job on resume).

### `tasks`
Prints the `## Task` checkbox lines with ✔ if ticked in `TASK.md` or if `PROGRESS.md` contains `- [x] … T<n>`.
5. If the project is a git repo and `.gitignore` does not contain `.cleanloop/state`, appends `state/` and `logs/`.

### `run [-n N]`
```
start_iter = ITERATION(PROGRESS.md) + 1
stall = 0
for i in start_iter .. start_iter+N-1:
    STATUS == DONE    → exit 0
    STATUS == BLOCKED → exit 3
    before = checksum(PROGRESS.md)
    run_iteration(i)                       # see below
    after  = checksum(PROGRESS.md)
    before == after ? stall++ : stall = 0
    stall ≥ STALL_LIMIT → exit 2
STATUS == DONE ? exit 0 : exit 4
```
`ITERATION` is read from `PROGRESS.md` so an interrupted `run` resumes with the right numbering.

### `run_iteration i`
Arguments passed to `claude`:
| Argument | Value | Why |
|---|---|---|
| `-p --output-format stream-json --verbose` | | non-interactive; the JSON stream is saved raw to `iter-NNN-….jsonl`, rendered readable on screen by `stream_pretty` (text, `→ tool`, model, summary) and parsed by `iteration_summary` for model, tokens, cost, turns |
| `--plugin-dir` | plugin root | loads hooks and skill even if the plugin is not installed |
| `--permission-mode` | `CLEANLOOP_PERMISSION_MODE` | nobody answers prompts in `-p` |
| `--autocompact` | `window × (HARD+25)/100`, clamped to [100k, 1M] | safety net well beyond the hard threshold |
| `--append-system-prompt-file` | `prompts/iteration-system.md` | iteration rules guaranteed even if the skill is not invoked |
| `--name` | `cleanloop-<i>` | recognisable in `/resume` |
| `--model` | `CLEANLOOP_MODEL` | only if set |
| `--max-budget-usd` | `CLEANLOOP_MAX_BUDGET_USD` | only if set |
| prompt | "Iteration i/N of cleanloop. The task is in TASK.md, the state in PROGRESS.md (already injected). Resume from the handoff, complete and verify ONE sub-task, update PROGRESS.md, end." | |

Environment exported to the process: `CLEANLOOP_ACTIVE=1` (enables the Stop hook and the "end the turn" messages), `CLEANLOOP_ITER=i`, `CLEANLOOP_ROOT`.

After each iteration it appends to `LOOPLOG.md` the row `| i | HH:MM:SS | pct% (used / window) | reason | STATUS |` (reason: natural end / threshold / hard threshold, plus `exit rc` if ≠ 0). Events: `iter_start` before launching `claude`; `iter_end` afterwards, with duration, exit code, last context measurement (`state/last.json`), `reason` derived from the threshold level reached in the session, and `progress`/`status`; `loop_start`/`loop_stop` around the cycle. All in `.cleanloop/logs/events.log`.

Output: raw stream in `.cleanloop/logs/iter-<NNN>-<ts>.jsonl`, readable version (+ stderr) in `.cleanloop/logs/iter-<NNN>-<ts>.log`; at the end of the iteration it prints `model · tokens in/out · API-equivalent cost · turns`; the `claude` exit code is `PIPESTATUS[0]` and is only reported (it does not stop the loop: the decision is based on `PROGRESS.md` progress).

### `status`, `reset`, `disable`
- `status`: active?, `STATUS`/`ITERATION` from `PROGRESS.md`, thresholds and window, last `state/last.json`, latest 3 logs.
- `reset`: `rm -rf .cleanloop/state` — useful if a per-session marker was left dirty. Leaves `PROGRESS.md` and logs untouched.
- `disable`: removes `.cleanloop/enabled`; hooks become inert in the project (`init` re-enables them).

## Why the session is not run with `--no-session-persistence`
The hooks read the transcript to measure the context: persistence is required. The `cleanloop-<i>` sessions remain in the `/resume` picker and can be inspected afterwards.
