# Usage guide

## The mental model

cleanloop enforces one rule: **the state of the work lives in files, not in the conversation**.

- `TASK.md` — what must be done and when it is finished (you write it).
- `PROGRESS.md` — where we are, what is left, where to resume (Claude rewrites it at each *checkpoint*).
- `CLAUDE.md` — durable facts about the project (commands, conventions, constraints), never progress.

The conversation context is a disposable working buffer: when it exceeds the threshold (default 25% of the window) you checkpoint and restart clean.

## The two modes

### Autonomous loop (`cleanloop run`)
For long tasks you do not want to babysit.

```bash
cleanloop run            # until DONE/BLOCKED, max 20 iterations
cleanloop run -n 5       # at most 5 iterations
cleanloop once           # a single iteration (handy to try things out)
cleanloop status         # STATUS, iteration, last context %, latest logs
```

Each iteration is a separate `claude -p` process with an empty context. Inside the iteration:
- at **25%** the hook asks to close the current sub-task, checkpoint and exit;
- at **40%** it asks to stop immediately;
- on exit the `Stop` hook blocks termination if `PROGRESS.md` was not modified.

While the loop runs you see, for each iteration, the **model** in use (`· modello: claude-…`), the text and tools used, and at the end **tokens consumed and API-equivalent cost** (`total_cost_usd`: not charged on a subscription, but it measures consumption). Every iteration exit lands in **`LOOPLOG.md`**, next to `TASK.md`/`PROGRESS.md`: a table with number, time, model, context usage at exit, tokens, cost (plus reason and STATUS). Subscription limits (5h/7-day windows) are not exposed in `-p`: check them with `/usage` in an interactive session. In interactive mode it also records each restart via `/clear`/`/compact` (row `↻`, with the context *before* the restart). The machine-readable detail is in `.cleanloop/logs/events.log` (`cleanloop log`, see [formats](../technical/file-formats.md#looplogmd)).

The loop stops on: `STATUS: DONE` · `STATUS: BLOCKED` (a human is needed) · **stall** (3 iterations without changes to `PROGRESS.md`) · maximum iterations. See [exit codes](configuration.md#runner-exit-codes).

With `CLEANLOOP_USE_SUBAGENTS=1` the iteration can delegate independent tasks to subagents (Agent tool) instead of doing them sequentially: their log lines are tagged with a short id (e.g. `[7SuPBn] → Bash`) so you can follow them separately from the main turn. Details in [Configuration](configuration.md#subagents-cleanloop_use_subagents).

Every parameter (thresholds, model, `--effort`, permission mode, budget, etc.) can be set from the command line: `cleanloop init --threshold 15 ...` at setup, `cleanloop config KEY=VALUE` afterwards, or `cleanloop run/once --model opus ...` as a one-off override valid only for that run, without touching the saved configuration. See [Configuring from the command line](configuration.md#configuring-from-the-command-line).

### Interactive session (`claude` + `/cleanloop`)
For when you want to watch or step in.

```
claude
> /cleanloop
```
The skill reads `PROGRESS.md` and continues from the handoff. When the context crosses the threshold, Claude:
1. closes the sub-task, updates `PROGRESS.md` (and `CLAUDE.md` if needed);
2. tells you: *"Checkpoint saved to PROGRESS.md. Run `/clear` and then `/cleanloop` to resume with a clean context."*

You run `/clear` and `/cleanloop`: the `SessionStart` hook re-injects `TASK.md` + `PROGRESS.md` and work resumes from the handoff. Claude **cannot** run `/clear` itself: that is the only manual step.

If you prefer `/compact` to `/clear`, it works too: the `PreCompact` hook asks the summary to preserve the state.

### Mixing them
An effective pattern:
1. **Interactive** to define the plan in `PROGRESS.md` (*Plan* section) and take the first delicate steps.
2. **`cleanloop run`** to grind through the repetitive sub-tasks.
3. **Interactive** to polish and close.

## The task queue

`TASK.md`, section `## Task`, is an **ordered queue** owned by you:
```markdown
## Task (coda: aggiungi con `cleanloop add`)
- [ ] T1: Add page/size to GET /api/orders
- [ ] T2: Tests in tests/api
```
- `cleanloop init` creates it with the wizard; `cleanloop add "…"` appends (progressive `Tn` id), also **while the loop is running**: the next iteration sees it. A task may be multi-line (wizard and interactive `add`: empty line = next task, `.` = end; as an argument: `cleanloop add $'first line\nsecond line'`); lines after the first are stored indented under the bullet.
- An alternative to the wizard if you already have a long prompt or a ready task list (e.g. on your clipboard) and want to avoid pasting it line by line: **brief mode** — `pbpaste | cleanloop init` or `cleanloop init --brief file.md`. The text goes into `BRIEF.md`, and the **first iteration** reads it and organises the `TASK.md` queue itself, without doing any application work in that turn. Details in [Configuration](configuration.md#task-input-brief-instead-of-the-wizard).
- The *Plan* in `PROGRESS.md` mirrors it with the same ids; on every resume Claude compares queue and Plan and adds new entries. It may split a task into sub-tasks, never remove undone entries.
- `cleanloop tasks` shows the queue with ✔ on entries ticked in the Plan.
- The loop ends (`STATUS: DONE`) when the Definition of done is verified: by default "all queued tasks completed and verified". If you enqueue a task after `DONE`, set `STATUS: IN_PROGRESS` again and rerun `run`.

## What happens at a checkpoint

Claude, in order:
1. brings files to a consistent state and runs the quick verification available (tests/build);
2. **rewrites** `PROGRESS.md` (no accumulation): `STATUS`, `ITERATION`, *Done*, *In progress*, *Next step (handoff)*, ticked *Plan*, *Decisions*, *Pitfalls*, *Verification* — about 40 lines max;
3. adds to `CLAUDE.md` only durable facts discovered (1-3 lines), never a session log;
4. ends the turn (loop) or asks you to `/clear` (interactive).

The **handoff** is the most important part: it must let an agent with an empty context resume without re-exploring the project (file, command, what to verify).

## Team use

### Automatic activation in a shared repo
In the project repo, `.claude/settings.json` (versioned):
```json
{
  "extraKnownMarketplaces": {
    "peretti-plugins": { "source": { "source": "github", "repo": "alessandroperetti69/claude-plugins" } }
  },
  "enabledPlugins": { "cleanloop@peretti-plugins": true }
}
```
Whoever opens the project with Claude Code is prompted to install the marketplace and the plugin.

### `TASK.md` and `PROGRESS.md` as a handoff between people
Version them: `PROGRESS.md` is already a readable handoff ("where we are, what is left, decisions taken"). Only `.cleanloop/state/` and `.cleanloop/logs/` should be ignored (`init` adds them to `.gitignore`).

### Permissions
In `-p` mode nobody can answer permission prompts. If iterations stop on denied tools:
- add permissions to the project's `.claude/settings.json` (e.g. `Bash(pytest *)`), or
- `CLEANLOOP_PERMISSION_MODE=bypassPermissions` **only in a sandbox/container**.

## Best practices
- **Verifiable definition of done** in `TASK.md`: it is the loop's stop condition.
- **Small sub-tasks**: one iteration = one sub-task closed and verified. If a sub-task does not fit in an iteration, split it.
- **Do not ignore the threshold** "because it's almost done": a large context degrades quality *before* it fills up.
- **`CLAUDE.md` is not a diary**: only facts that will still matter in a month.
- **Review the diff** at the end of the loop like a PR: the loop is autonomous, the responsibility stays yours.
- **Budget**: `CLEANLOOP_MAX_BUDGET_USD` per iteration and `-n` to bound experiments.
- **Model**: `CLEANLOOP_MODEL=sonnet` for mechanical sub-tasks, the default model for delicate ones; `CLEANLOOP_EFFORT` to tune reasoning effort the same way.
- **Subagents**: `CLEANLOOP_USE_SUBAGENTS=1` helps when the queue has several genuinely independent tasks (no shared files); on sequential or small tasks the model usually chooses on its own not to use them.
