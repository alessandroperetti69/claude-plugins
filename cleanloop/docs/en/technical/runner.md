# Runner `cleanloop.sh`

Bash script (`scripts/cleanloop.sh`) orchestrating the fresh-session loop. It uses neither `timeout` (absent on macOS) nor dependencies beyond `bash`, `jq`, `claude`, `md5|md5sum`. Written for bash 3.2 (macOS's default): no associative arrays, no `local -n`, indexed arrays are always guarded with `${#arr[@]} -gt 0` before expanding them as `"${arr[@]}"` (bash 3.2 treats expanding an empty array as an unset variable under `set -u`).

## Commands
See [Configuration → Runner commands](../user-guide/configuration.md#runner-commands). Internals below.

## Config: `CFG_KEYS`, `validate_cfg`, `set_cfg_var`
The variables configurable from the CLI are listed in `CFG_KEYS` (`THRESHOLD HARD MAX_ITER STALL_LIMIT REMIND_EVERY PERMISSION_MODE MODEL EFFORT MAX_BUDGET_USD CONTEXT_WINDOW PROGRESS_FILE TASK_FILE LOG_FILE USE_SUBAGENTS`). Three commands share the same logic:
- `validate_cfg KEY VALUE`: validates by type (integers for thresholds/limits, one of the allowed values for `PERMISSION_MODE`/`EFFORT`/`USE_SUBAGENTS`, non-empty for file names, free-form for `MODEL`); `die`s if invalid — nothing is written.
- `set_cfg_var KEY VALUE`: updates the `export CLEANLOOP_<KEY>="${CLEANLOOP_<KEY>:-...}"` line in `.cleanloop/config` if it already exists (replaces only the default inside `:-...}`, via `sed` with an `@` delimiter to tolerate `/` in paths), otherwise appends it at the end of the file.

`init`, `config`, and `run`/`once` all build their `--xxx` flags on the same pattern: parse into a `passed_keys` array, then run `validate_cfg` once over every collected key before writing or executing anything.

### `init`
1. `need_jq`.
2. Parses flags: `--task`, `--brief`, and one per `CFG_KEYS` entry (e.g. `--threshold`, `--model`, `--use-subagents`, …). Each config flag immediately updates the in-process `CLEANLOOP_*` variable and records it in `passed_keys`; once parsing is done, every collected key runs through `validate_cfg`.
3. Creates `.cleanloop/{state,logs}` and the empty file `.cleanloop/enabled`.
4. If `.cleanloop/config` is missing: writes it with every variable in the `export VAR="${VAR:-default}"` pattern, where `default` is the current value (reflecting any passed flags). If the file already exists and at least one config flag was passed, updates only those keys via `set_cfg_var` (other lines are left untouched).
5. If `TASK.md` is missing, in this priority order:
   1. `--task "text"` → literal `T1` (legacy behaviour).
   2. `--brief PATH` or `--brief -` → reads the file or stdin (`read_brief_into`), writes the content to `BRIEF.md` (project root).
   3. `BRIEF.md` already present at the root (no flag needed).
   4. non-interactive stdin with content (`pbpaste | cleanloop init`): read in full (`cat`), written to `BRIEF.md`.
   5. stdin is a terminal → `wizard` (goal, tasks, constraints, then `wizard_config`, see below).
   6. otherwise (non-interactive stdin, empty) → copies the empty template (unchanged behaviour for scripts/CI that pass nothing).
   Variants 2-4 call `write_brief_task_file`: generates a `TASK.md` with a single `T1` asking the first iteration to read `BRIEF.md` and derive the goal and real queue from it, **without** doing any application work in that turn (see [file formats](file-formats.md#briefmd)).
6. If `PROGRESS.md` is missing, `write_progress_file` generates it with Goal and Plan derived from `TASK.md`; in brief mode it gets a dedicated handoff (an optional function parameter) pointing explicitly at `BRIEF.md` instead of the generic text.
7. If the project is a git repo and `.gitignore` does not contain `.cleanloop/state`, appends `state/` and `logs/`.

### `wizard` / `wizard_config`
Only on the interactive path (stdin is a terminal, no `--task`/`--brief`, no pre-existing `BRIEF.md`). `wizard` asks for the goal, tasks (`read_block`, multi-line) and constraints as before, writes `TASK.md`, then calls `wizard_config`.

`wizard_config` asks, in sequence, with **enter keeping the shown default** (the default reflects any flags already passed to `init`):
1. Model — numbered menu (`sonnet`/`opus`/`fable`/`haiku`/"other" for a full id); text typed directly (not a number) is accepted as a literal value.
2. Effort — same pattern, `low/medium/high/xhigh/max` menu.
3. Permission mode — `auto`/`acceptEdits`/`bypassPermissions` menu.
4. Subagent use — yes/no.
5. Checkpoint threshold, hard threshold, max budget (number or empty = unlimited), max iterations, stall limit — numeric prompts that retry on invalid input (`ask_int`/`ask_num_or_empty`).
6. Yes/no gate for advanced parameters: if yes, also asks for remind-every, context-window, and the log file name (`ask_text`).

Each answer immediately writes the matching key to `.cleanloop/config` via `set_cfg_var` (the file already exists by this point, created in `init` step 4). `TASK_FILE`/`PROGRESS_FILE` are **not** asked in the wizard: changing them after `TASK.md` has already been written would misalign the file names — they stay configurable only via flags (`--task-file`/`--progress-file` on `init`) or by hand.

### `add ["text"]`
Inserts the block `- [ ] T<max+1>: first line` + indented continuations at the end of the `## Task` section of `TASK.md` (awk: first empty line after the heading; the block is passed via a temp file). Without argument and with a terminal stdin: `read_block` loop — an empty line closes the task, a lone `.` or EOF closes the list. Does not touch `PROGRESS.md` (aligning the Plan is the model's job on resume).

### `tasks`
Prints the `## Task` checkbox lines with ✔ if ticked in `TASK.md` or if `PROGRESS.md` contains `- [x] … T<n>`.

### `config [KEY=VALUE ...]`
With no arguments: prints `.cleanloop/config` in full. With arguments: for each `KEY=VALUE` pair (optional `CLEANLOOP_` prefix, stripped if present), validates with `validate_cfg` and writes with `set_cfg_var`, then exports the variable in the current process. `die`s on the first invalid pair (bad format or out-of-schema key/value) without having touched the file for that pair.

### `run [-n N] [config options]`
```
parsing: -n/--max-iter → max; every --xxx from CFG_KEYS → CLEANLOOP_xxx in-process, recorded in passed_keys
validate_cfg over every key in passed_keys (nothing written to disk: overrides apply to this run only)
start_iter = ITERATION(PROGRESS.md) + 1
stall = 0
for i in start_iter .. start_iter+max-1:
    STATUS == DONE    → exit 0
    STATUS == BLOCKED → exit 3
    before = checksum(PROGRESS.md)
    run_iteration(i)                       # see below
    after  = checksum(PROGRESS.md)
    before == after ? stall++ : stall = 0
    stall ≥ STALL_LIMIT → exit 2
STATUS == DONE ? exit 0 : exit 4
```
`ITERATION` is read from `PROGRESS.md` so an interrupted `run` resumes with the right numbering. `once` is implemented as `cmd_run "$@" -n 1`: `-n 1` is always the last argument passed, so it wins over any `-n`/`--max-iter` the user might also have passed to `once` (a single iteration is guaranteed regardless of other flags).

### `run_iteration i`
Arguments passed to `claude`:
| Argument | Value | Why |
|---|---|---|
| `-p --output-format stream-json --verbose` | | non-interactive; the JSON stream is saved raw to `iter-NNN-….jsonl`, rendered readable on screen by `stream_pretty` (text, `→ tool`, model, summary) and parsed by `iteration_summary` for model, tokens, cost, turns |
| `--plugin-dir` | plugin root | loads hooks and skill even if the plugin is not installed |
| `--permission-mode` | `CLEANLOOP_PERMISSION_MODE` | nobody answers prompts in `-p` |
| `--autocompact` | `window × (HARD+25)/100`, clamped to [100k, 1M] | safety net well beyond the hard threshold |
| `--append-system-prompt-file` | `prompts/iteration-system.md` | iteration rules guaranteed even if the skill is not invoked |
| `--forward-subagent-text` | always present | forwards subagent (Agent tool) events into the stream, tagged with `parent_tool_use_id`, so `stream_pretty` can render them even when `USE_SUBAGENTS=0` but the model launches one anyway |
| `--name` | `cleanloop-<i>` | recognisable in `/resume` |
| `--model` | `CLEANLOOP_MODEL` | only if set |
| `--effort` | `CLEANLOOP_EFFORT` | only if set |
| `--max-budget-usd` | `CLEANLOOP_MAX_BUDGET_USD` | only if set |
| prompt | "Iteration i/N of cleanloop. The task is in TASK.md, the state in PROGRESS.md (already injected). Resume from the handoff, complete and verify ONE sub-task, update PROGRESS.md, end." — if `CLEANLOOP_USE_SUBAGENTS=1`, a trailing sentence asks it to consider parallelising independent queued tasks with the Agent tool (subagents report back as text only, never write files; the `PROGRESS.md` checkpoint stays the main turn's job alone) | |

Environment exported to the process: `CLEANLOOP_ACTIVE=1` (enables the Stop hook and the "end the turn" messages), `CLEANLOOP_ITER=i`, `CLEANLOOP_ROOT`.

After each iteration it appends to `LOOPLOG.md` the row `| i | HH:MM:SS | model | pct% (used / window) | iteration tokens | API-equivalent cost | reason | STATUS |` (reason: natural end / threshold / hard threshold, plus `exit rc` if ≠ 0). Events: `iter_start` before launching `claude` (includes `subagents=0|1`); `iter_end` afterwards, with duration, exit code, last context measurement (`state/last.json`), tokens/cost/turns, `reason` derived from the threshold level reached in the session, and `progress`/`status`; `loop_start`/`loop_stop` around the cycle. All in `.cleanloop/logs/events.log`.

Output: raw stream in `.cleanloop/logs/iter-<NNN>-<ts>.jsonl`, readable version (+ stderr) in `.cleanloop/logs/iter-<NNN>-<ts>.log`; at the end of the iteration it prints `model · tokens in/out · API-equivalent cost · turns`; the `claude` exit code is `PIPESTATUS[0]` and is only reported (it does not stop the loop: the decision is based on `PROGRESS.md` progress).

### `stream_pretty` and subagent tagging
A `jq` filter that renders the stream-json readable: assistant text, `→ ToolName` per tool_use, final summary. It distinguishes main-turn events (`parent_tool_use_id` absent/null) from subagent events (`parent_tool_use_id` set, present thanks to `--forward-subagent-text`):
- the tool_use launching a subagent (`.name=="Agent"`) prints `→ subagente [tag] "description"`, where `tag` is the last 6 characters of its `id` (the `tool_use_id`, unique per invocation);
- every subsequent event sharing that `parent_tool_use_id` is printed with the same `[tag]` prefix (`[tag] → ToolName`, `[tag] text`), so multiple parallel subagents can be told apart line by line in the log.

Verified empirically by launching a real subagent: the relevant fields are `.parent_tool_use_id` (at the event's top level, not inside `.message`) and, on the `Agent` tool_use, `.input.description`/`.input.prompt`.

### `status`, `reset`, `disable`
- `status`: active?, `STATUS`/`ITERATION` from `PROGRESS.md`, thresholds and window, last `state/last.json`, latest `LOOPLOG.md` rows, last 5 events.
- `reset`: `rm -rf .cleanloop/state` — useful if a per-session marker was left dirty. Leaves `PROGRESS.md` and logs untouched.
- `disable`: removes `.cleanloop/enabled`; hooks become inert in the project (`init` re-enables them).

## Why the session is not run with `--no-session-persistence`
The hooks read the transcript to measure the context: persistence is required. The `cleanloop-<i>` sessions remain in the `/resume` picker and can be inspected afterwards.
