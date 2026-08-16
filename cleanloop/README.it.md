# cleanloop

*[Read in English](README.md)*

Plugin per Claude Code che tiene il contesto **sotto una soglia (default 25% della finestra)** e fa avanzare task lunghi con la disciplina *stato-nei-file*: superata la soglia il modello fa checkpoint su `PROGRESS.md` (avanzamento) e `CLAUDE.md` (fatti durevoli), chiude l'iterazione, e il loop riparte con **contesto vuoto**.

- **Skill** `/cleanloop` — il protocollo di checkpoint/ripresa
- **Hook** — misurano il contesto a ogni tool call, avvisano al 25%, forzano al 40%, reiniettano lo stato dopo `/clear`, sorvegliano la fine di un'iterazione
- **Runner** `cleanloop.sh` — loop a sessioni fresche (`claude -p` per iterazione) fino a `STATUS: DONE`, con guardie su stallo / max iterazioni / budget

## Avvio rapido
```
/plugin marketplace add alessandroperetti69/claude-plugins
/plugin install cleanloop@peretti-plugins
```
```bash
alias cleanloop='bash ~/.claude/plugins/marketplaces/peretti-plugins/cleanloop/scripts/cleanloop.sh'
cd mio-progetto
cleanloop init                       # wizard: obiettivo, task uno per riga, vincoli
cleanloop add "Aggiornare la doc"    # accoda altri task, anche a loop avviato
cleanloop run                        # loop autonomo
# oppure: claude → /cleanloop                              # interattivo, hook attivi
```
Richiede Claude Code ≥ 2.1, `bash`, `jq`.

## Documentazione
| | Italiano | English |
|---|---|---|
| Indice | [docs/it](docs/it/README.md) | [docs/en](docs/en/README.md) |
| Primi passi | [primi passi](docs/it/user-guide/getting-started.md) | [getting-started](docs/en/user-guide/getting-started.md) |
| Guida all'uso | [guida all'uso](docs/it/user-guide/usage.md) | [usage](docs/en/user-guide/usage.md) |
| Configurazione | [configurazione](docs/it/user-guide/configuration.md) | [configuration](docs/en/user-guide/configuration.md) |
| Risoluzione problemi | [risoluzione problemi](docs/it/user-guide/troubleshooting.md) | [troubleshooting](docs/en/user-guide/troubleshooting.md) |
| Architettura | [architettura](docs/it/technical/architecture.md) | [architecture](docs/en/technical/architecture.md) |
| Hook · Runner · Formati · Sviluppo | [hook](docs/it/technical/hooks.md) · [runner](docs/it/technical/runner.md) · [formati](docs/it/technical/file-formats.md) · [sviluppo](docs/it/technical/development.md) | [hooks](docs/en/technical/hooks.md) · [runner](docs/en/technical/runner.md) · [formats](docs/en/technical/file-formats.md) · [development](docs/en/technical/development.md) |

## Struttura
```
.claude-plugin/plugin.json     manifest
skills/cleanloop/SKILL.md      protocollo: setup, checkpoint, ripresa, loop, anti-pattern
hooks/hooks.json               SessionStart · PostToolUse · PreCompact · Stop
scripts/                       cleanloop.sh (runner), context-guard.sh, session-start.sh, pre-compact.sh, stop-guard.sh, lib.sh
prompts/iteration-system.md    system prompt aggiunto a ogni iterazione -p
templates/                     TASK.md, PROGRESS.md
docs/{en,it}/                  documentazione
```

Vedi [CHANGELOG](CHANGELOG.md) · [CONTRIBUTING](CONTRIBUTING.md).
