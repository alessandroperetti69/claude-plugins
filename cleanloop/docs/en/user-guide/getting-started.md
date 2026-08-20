# Getting started

In this guide you install cleanloop and complete a first task in autonomous loop mode. Time: about 10 minutes.

## Prerequisites
- **Claude Code** ≥ 2.1 (`claude --version`)
- **jq** (`brew install jq` on macOS; `apt install jq` on Debian/Ubuntu)
- `bash` (present on macOS and Linux)
- Access to the marketplace repo `alessandroperetti69/claude-plugins` with authenticated `git` (`gh auth login` or an SSH key)

## 1. Install

Inside a Claude Code session:
```
/plugin marketplace add alessandroperetti69/claude-plugins
/plugin install cleanloop@peretti-plugins
```
or from a terminal:
```bash
claude plugin marketplace add alessandroperetti69/claude-plugins
claude plugin install cleanloop@peretti-plugins
```

Check: `claude plugin details cleanloop` should list 1 skill and 4 hooks.

## 2. Alias for the runner (recommended)

The loop runner is a bash script inside the installed plugin. Add to `~/.zshrc` (or `~/.bashrc`):
```bash
alias cleanloop='bash ~/.claude/plugins/marketplaces/peretti-plugins/cleanloop/scripts/cleanloop.sh'
```
Reload the shell (`source ~/.zshrc`) and check with `cleanloop` (prints usage).

## 3. Enable cleanloop in the project

In the root of the project you want to work on:
```bash
cleanloop init
```
A short wizard opens: the **goal** (1 line), then the **tasks**, then optional **constraints**. Each task may span several lines (you can paste a whole prompt): an **empty line** moves to the next task, a lone **`.`** ends the list. Example:
```
Obiettivo (1 riga): Pagination for GET /api/orders
Task in ordine di esecuzione. Ogni task può occupare più righe (incolla pure):
  riga vuota = task successivo · "." da sola = fine elenco
  T1> Add page/size parameters to GET /api/orders.
      The response must include total, page, size metadata.
                                          ← empty line: closes T1
  T2> Tests in tests/api/test_orders.py

  T3> .                                   ← end of list
Vincoli (cosa non toccare, stile, ...): riga vuota = prossimo · "." = fine
  - Do not touch authentication

  - .
```
Note: an empty line *inside* pasted text is read as a task separator; if your prompt has paragraphs, paste them one at a time or remove blank lines.
(Prompts are in Italian; answers can be in any language. Alternatively `cleanloop init --task "…"` creates everything without questions, with a single task.)

**Already have a long prompt or a ready task list (e.g. on your clipboard) and want to avoid pasting it line by line?** Use brief mode: `pbpaste | cleanloop init` (or `cleanloop init --brief path/to/file.md`). The text goes into `BRIEF.md`, and the **first iteration** reads it and organises the `TASK.md` queue itself, without starting any application work in that turn — then run `cleanloop once` to review the plan before letting `run` proceed unsupervised. Details in [Configuration](configuration.md#task-input-brief-instead-of-the-wizard).

This creates:
- `TASK.md` — task description (for you to complete)
- `PROGRESS.md` — progress state (updated by Claude)
- `LOOPLOG.md` — readable log: one row per iteration exit with time and context %
- `.cleanloop/` — configuration (`config`), switch (`enabled`), state and logs

> From now on the cleanloop hooks are active **in this folder**. In other projects they stay inert.

## 4. Refine `TASK.md`

The `## Task` section is your **queue**: you can add entries at any time, even while the loop is running, with `cleanloop add "…"` (or `cleanloop add` to enter several). `cleanloop tasks` shows it with status.

Open `TASK.md` and complete the **Definition of done** with conditions verifiable by a command. Example:
```markdown
## Definition of done
- [ ] `GET /api/orders?page=2&size=20` returns 20 items plus `total`, `page`, `size` metadata
- [ ] `pytest tests/api/test_orders.py` passes
- [ ] no database schema changes

## Constraints
- Do not touch authentication
- Style: follow `docs/api-conventions.md`
```
The more precise the definition, the better the loop knows **when to stop**.

## 5. Run the loop

```bash
cleanloop run
```
Each iteration is a **new** `claude -p` session (empty context) that:
1. receives `TASK.md` and `PROGRESS.md`,
2. resumes from the "Next step (handoff)",
3. completes and verifies **one** sub-task,
4. updates `PROGRESS.md` and exits.

The loop stops when `PROGRESS.md` reports `STATUS: DONE` (or `BLOCKED`, or after the maximum number of iterations). From another terminal:
```bash
cleanloop status
```

## 6. Review

When the loop ends, read `PROGRESS.md` (*Done*, *Decisions*, *Verification*) and review the diff as you would a pull request. Per-iteration logs are in `.cleanloop/logs/`.

## Next steps
- [Usage guide](usage.md): interactive mode, team use, best practices
- [Configuration](configuration.md): thresholds, model, budget, permissions
