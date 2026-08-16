# cleanloop documentation (English)

[Versione italiana](../it/README.md)

cleanloop is a Claude Code plugin that keeps the conversation context under a threshold (default 25% of the window), checkpoints to `PROGRESS.md`/`CLAUDE.md`, and drives a long task forward through **fresh-context** iterations.

## User guide
| Document | Audience | Content |
|---|---|---|
| [Getting started](user-guide/getting-started.md) | newcomers | installation, first task in 10 minutes |
| [Usage guide](user-guide/usage.md) | daily use | loop mode, interactive mode, team use, best practices |
| [Configuration](user-guide/configuration.md) | reference | every variable, runner commands, exit codes |
| [Troubleshooting](user-guide/troubleshooting.md) | when something is off | FAQ and diagnostics |

## Technical documentation
| Document | Content |
|---|---|
| [Architecture](technical/architecture.md) | why skill + hooks + runner, flows, diagrams, design decisions |
| [Hooks](technical/hooks.md) | the four hooks: inputs, outputs, activation conditions |
| [Runner](technical/runner.md) | `cleanloop.sh`: iteration, stop conditions, arguments passed to `claude` |
| [File formats](technical/file-formats.md) | `TASK.md`, `PROGRESS.md`, `.cleanloop/config`, state |
| [Development](technical/development.md) | repo layout, testing, releasing to the marketplace |

Documented version: **0.4.0** — see [CHANGELOG](../../CHANGELOG.md).
