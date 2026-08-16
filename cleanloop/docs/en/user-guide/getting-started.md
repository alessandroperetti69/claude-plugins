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
cleanloop init --task "Add pagination to the GET /api/orders endpoint"
```
This creates:
- `TASK.md` — task description (for you to complete)
- `PROGRESS.md` — progress state (updated by Claude)
- `.cleanloop/` — configuration (`config`), switch (`enabled`), state and logs

> From now on the cleanloop hooks are active **in this folder**. In other projects they stay inert.

## 4. Write a good `TASK.md`

Open `TASK.md` and fill in above all the **Definition of done**: conditions verifiable with a command. Example:
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
