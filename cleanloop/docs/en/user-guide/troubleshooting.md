# Troubleshooting

### `/cleanloop` does not show up in the session
- Is the plugin installed? `claude plugin details cleanloop`.
- The session started before the installation: open a new session.
- With `--plugin-dir` the path must point to the `cleanloop/` folder (the one containing `.claude-plugin/`).

### The hooks do nothing
By design they are inert until the project is enabled: you need `.cleanloop/enabled` (created by `cleanloop init`) or `CLEANLOOP_ACTIVE=1`. Check with `cleanloop status` (`active:` line).

### The context percentage looks wrong
- The window is auto-detected: 1M if the model in `~/.claude/settings.json` contains `[1m]`, otherwise 200k. If you use a different model in the loop (`CLEANLOOP_MODEL`), set `CLEANLOOP_CONTEXT_WINDOW` explicitly.
- The measurement comes from the `usage` of the last assistant message in the transcript (`input + cache_creation + cache_read`), refreshed at every tool call: right after `/clear` it may show the old value until the first tool call runs.
- `cleanloop status` shows the last measurement (`.cleanloop/state/last.json`).

### I want to see when and why iterations ended
Open `LOOPLOG.md` in the project: one row per iteration with time, context at exit, reason and STATUS (and `↻` rows for interactive `/clear`). For details, `cleanloop log` (or `-n 20`): for each iteration `iter_end` reports duration, `ctx=` (context percentage at exit) and `reason=` (`natural_end`, `soft_threshold`, `hard_threshold`); each `session_start` reports `prev_ctx=`, i.e. the percentage before the restart. This also covers interactive sessions with `/clear`.

### The loop stops for "stall"
Three consecutive iterations did not modify `PROGRESS.md`. Typical causes:
- permissions denied in `-p` (look at the latest log in `.cleanloop/logs/`): add permissions to the project's `.claude/settings.json`;
- `claude` exits with an error (budget exhausted, authentication): the runner prints the exit code;
- the handoff in `PROGRESS.md` is ambiguous and every iteration starts exploring again: rewrite it by hand, more precisely.
Once fixed: `cleanloop run` resumes from the iteration after `ITERATION`.

### An iteration never ends / is very long
- Lower `CLEANLOOP_THRESHOLD`/`CLEANLOOP_HARD` (especially with a 1M window).
- Put a cap: `CLEANLOOP_MAX_BUDGET_USD=2 cleanloop run`.
- The sub-task in the *Plan* is too big: split it in `PROGRESS.md`.

### `STATUS: DONE` but the work is not complete
The stop condition is the *Definition of done* in `TASK.md`: if it is vague, Claude considers it satisfied too early. Make it verifiable with commands. You can set `STATUS: IN_PROGRESS` again, add the missing step to the handoff and rerun `run`.

### `Stop` hook: "You cannot end the iteration without updating PROGRESS.md"
Intended: in loop mode an iteration cannot end without a checkpoint. It blocks only once (then Claude Code passes `stop_hook_active` and the hook lets it exit) — so even if the model insists, the loop never gets stuck.

### In an interactive session Claude tells me to `/clear` but I would rather continue
You may ignore it; the hook repeats the reminder every `CLEANLOOP_REMIND_EVERY` tool calls. To silence it in the project: `cleanloop disable`.

### macOS: `timeout: command not found`
The runner does not use `timeout`; if you wrap `cleanloop run` with it yourself, install `coreutils` (`gtimeout`).

### How to update the plugin
```
/plugin marketplace update peretti-plugins
/plugin update cleanloop
```
The copy in `~/.claude/plugins/marketplaces/peretti-plugins/cleanloop` is refreshed from the repo; the alias keeps working.
