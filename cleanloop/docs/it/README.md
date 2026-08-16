# Documentazione cleanloop (italiano)

[English version](../en/README.md)

cleanloop è un plugin per Claude Code che tiene il contesto della conversazione sotto una soglia (default 25% della finestra), salva un checkpoint su `PROGRESS.md`/`CLAUDE.md` e fa avanzare un task lungo per iterazioni a **contesto pulito**.

## Guida utente
| Documento | Per chi | Contenuto |
|---|---|---|
| [Primi passi](user-guide/getting-started.md) | chi inizia | installazione, primo task in 10 minuti |
| [Guida all'uso](user-guide/usage.md) | uso quotidiano | modalità loop, modalità interattiva, uso in team, buone pratiche |
| [Configurazione](user-guide/configuration.md) | riferimento | tutte le variabili, comandi del runner, codici di uscita |
| [Risoluzione problemi](user-guide/troubleshooting.md) | quando qualcosa non va | domande frequenti e diagnosi |

## Documentazione tecnica
| Documento | Contenuto |
|---|---|
| [Architettura](technical/architecture.md) | perché skill + hook + runner, flussi, diagrammi, decisioni di design |
| [Hook](technical/hooks.md) | i quattro hook: input, output, condizioni di attivazione |
| [Runner](technical/runner.md) | `cleanloop.sh`: iterazione, condizioni di stop, argomenti passati a `claude` |
| [Formati dei file](technical/file-formats.md) | `TASK.md`, `PROGRESS.md`, `.cleanloop/config`, stato |
| [Sviluppo](technical/development.md) | struttura del repo, test, rilascio sul marketplace |

Versione documentata: **0.4.0** — vedi [CHANGELOG](../../CHANGELOG.md).
