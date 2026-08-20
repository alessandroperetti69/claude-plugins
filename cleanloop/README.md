# cleanloop

*[Leggi in italiano](README.it.md)*

A Claude Code plugin that keeps the context **under a threshold (default 25% of the window)** and drives long tasks with the *state-in-files* discipline: when the threshold is crossed the model checkpoints to `PROGRESS.md` (progress) and `CLAUDE.md` (durable facts), closes the iteration, and the loop restarts with an **empty context**.

- **Skill** `/cleanloop` — the checkpoint/resume protocol
- **Hooks** — measure the context at every tool call, warn at 25%, force at 40%, re-inject state after `/clear`, guard the end of an iteration
- **Runner** `cleanloop.sh` — fresh-session loop (`claude -p` per iteration) until `STATUS: DONE`, with stall / max-iteration / budget guards, optional subagents for independent tasks

## Quick start
```
/plugin marketplace add alessandroperetti69/claude-plugins
/plugin install cleanloop@peretti-plugins
```
```bash
alias cleanloop='bash ~/.claude/plugins/marketplaces/peretti-plugins/cleanloop/scripts/cleanloop.sh'
cd my-project
cleanloop init                       # wizard: goal/tasks/constraints, then model/thresholds/budget (enter = default)
cleanloop add "Update the docs"      # enqueue more tasks, even while the loop runs
cleanloop run                        # autonomous loop
# or: claude → /cleanloop                                    # interactive, hooks active
```
Already have a long prompt or a ready task list? `pbpaste | cleanloop init` (brief mode: the first iteration organises it itself, no line-by-line pasting). Every parameter is configurable from the CLI: `cleanloop init --model opus --threshold 15 ...`, `cleanloop config KEY=VALUE` afterwards, or as a one-off override on `run`/`once`.

Requires Claude Code ≥ 2.1, `bash`, `jq`.

## Documentation
| | English | Italiano |
|---|---|---|
| Index | [docs/en](docs/en/README.md) | [docs/it](docs/it/README.md) |
| Getting started | [getting-started](docs/en/user-guide/getting-started.md) | [primi passi](docs/it/user-guide/getting-started.md) |
| Usage guide | [usage](docs/en/user-guide/usage.md) | [guida all'uso](docs/it/user-guide/usage.md) |
| Configuration | [configuration](docs/en/user-guide/configuration.md) | [configurazione](docs/it/user-guide/configuration.md) |
| Troubleshooting | [troubleshooting](docs/en/user-guide/troubleshooting.md) | [risoluzione problemi](docs/it/user-guide/troubleshooting.md) |
| Architecture | [architecture](docs/en/technical/architecture.md) | [architettura](docs/it/technical/architecture.md) |
| Hooks · Runner · File formats · Development | [hooks](docs/en/technical/hooks.md) · [runner](docs/en/technical/runner.md) · [formats](docs/en/technical/file-formats.md) · [development](docs/en/technical/development.md) | [hook](docs/it/technical/hooks.md) · [runner](docs/it/technical/runner.md) · [formati](docs/it/technical/file-formats.md) · [sviluppo](docs/it/technical/development.md) |

## Layout
```
.claude-plugin/plugin.json     manifest
skills/cleanloop/SKILL.md      protocol: setup, checkpoint, resume, loop, anti-patterns
hooks/hooks.json               SessionStart · PostToolUse · PreCompact · Stop
scripts/                       cleanloop.sh (runner), context-guard.sh, session-start.sh, pre-compact.sh, stop-guard.sh, lib.sh
prompts/iteration-system.md    system prompt appended to every -p iteration
templates/                     TASK.md, PROGRESS.md
docs/{en,it}/                  documentation
```

See [CHANGELOG](CHANGELOG.md) · [CONTRIBUTING](CONTRIBUTING.md).
