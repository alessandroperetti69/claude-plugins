# Troubleshooting

### `/cleanloop` does not show up in the session
- Is the plugin installed? `claude plugin details cleanloop`.
- The session started before the installation: open a new session.
- With `--plugin-dir` the path must point to the `cleanloop/` folder (the one containing `.claude-plugin/`).

### The hooks do nothing
By design they are inert until the project is enabled: you need `.cleanloop/enabled` (created by `cleanloop init`) or `CLEANLOOP_ACTIVE=1`. Check with `cleanloop status` (`active:` line).

### I pasted a task list into the wizard and it got mangled
The wizard reads line by line (`read` in a TTY prompt): pasted text with blank lines or punctuation can be misread as a separator between tasks. Skip interactive pasting entirely with **brief mode**: `pbpaste | cleanloop init` (or `cleanloop init --brief file.md`). The text goes into `BRIEF.md` intact, and the first iteration reads it and organises the `TASK.md` queue itself — no line-by-line parsing in the terminal. Details in [Configuration](configuration.md#task-input-brief-instead-of-the-wizard).

### The context percentage looks wrong
- `used` (tokens consumed) is reliable: it's the same formula and the same transcript that feed Claude Code's own status line — verified live by comparing the two, they only differed by the seconds elapsed between the two readings.
- The window, however, is a **guess**, not a reading: Claude Code's `PostToolUse` hook never receives the real `context_window` field (only the status line gets it, and plugins have no access to it). cleanloop infers the window from the model name: 200k if it contains "haiku", otherwise 1M (every current Claude model has a 1M standard context window except Haiku). If your account/plan has a different window than the model's default, set `CLEANLOOP_CONTEXT_WINDOW` explicitly — that's the only way to be sure; compare against what your own status line shows.
- Right after `/clear`, the `used` measurement may show the old value until the first tool call of the new session runs.
- `cleanloop status` shows the last measurement (`.cleanloop/state/last.json`); it's **one file per project, not per session** — with two Claude Code sessions open on the same folder at once, whichever writes last wins and the number shown can belong to the other session (cosmetic: it doesn't cause false warnings, since the hook's own threshold check always uses the current session's transcript, not this file).

### The threshold fires again almost immediately after every checkpoint, even with the window detected correctly
This isn't a measurement bug — it's the fixed "floor" of every session. The very first assistant turn of a session — before any real work — already includes system prompt + tool schemas + the catalog of installed skills, all recreated on every `/clear`. With many plugins/skills enabled (especially the Vercel plugin, which alone brings ~30 skills) this floor can be a few thousand tokens; the rest — usually the larger share, often 90%+ of the floor — is Claude Code's own core system prompt and native tool schemas, not something plugins or cleanloop control. If you work interactively (not in the fresh-session loop) and the checkpoint request reappears almost immediately after every `/clear`, the threshold (default 25%/40%) is probably too tight for your fixed floor: raise `CLEANLOOP_THRESHOLD`/`CLEANLOOP_HARD` (`cleanloop config THRESHOLD=... HARD=...`) instead of looking for a bug — cleanloop has no way to subtract the floor from the calculation (percentages are absolute over the window, not relative to session start).

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
