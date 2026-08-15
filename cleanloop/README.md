# cleanloop — plugin per Claude Code

Tiene il contesto **sotto una soglia (default 25%, dura 40%)** e fa avanzare un task lungo con la disciplina *stato-nei-file*: quando la soglia viene superata il modello aggiorna `PROGRESS.md` (avanzamento) e `CLAUDE.md` (fatti durevoli), chiude l'iterazione, e il loop riparte con **contesto vuoto**.

```
cleanloop/
├── .claude-plugin/plugin.json     manifest
├── skills/cleanloop/SKILL.md      il protocollo (checkpoint, ripresa, loop)
├── hooks/hooks.json               SessionStart · PostToolUse · PreCompact · Stop
├── scripts/
│   ├── cleanloop.sh               runner: init | run | once | status | reset | disable
│   ├── context-guard.sh           PostToolUse: misura i token dal transcript, avvisa alla soglia
│   ├── session-start.sh           SessionStart: reinietta TASK.md + PROGRESS.md
│   ├── pre-compact.sh             PreCompact: preserva lo stato nel riassunto
│   ├── stop-guard.sh              Stop (solo in loop): niente uscita senza PROGRESS.md aggiornato
│   └── lib.sh
├── prompts/iteration-system.md    system prompt aggiunto a ogni iterazione -p
└── templates/{TASK,PROGRESS}.md
```

## Perché non basta una skill
Una skill è testo: non può misurare la finestra di contesto né eseguire `/clear`. Qui:
- la **misura** la fa un hook `PostToolUse` leggendo l'`usage` dell'ultimo messaggio nel transcript (`input + cache_creation + cache_read`) rispetto alla finestra (200k, o 1M se il modello in `~/.claude/settings.json` è `[1m]`; override `CLEANLOOP_CONTEXT_WINDOW`);
- la **pulizia** la fa il loop: ogni iterazione è un processo `claude -p` nuovo. In sessione interattiva il modello ti chiede di fare `/clear`, e `SessionStart` reinietta lo stato.

## Prerequisiti
`claude` (Claude Code ≥ 2.1), `bash`, `jq` (`brew install jq`).

## Installazione dal marketplace
```
/plugin marketplace add alessandroperetti69/claude-plugins
/plugin install cleanloop@peretti-plugins
```
Una volta installato, la skill `/cleanloop` e gli hook sono disponibili in ogni sessione (gli hook restano inerti finché non esegui `init` in un progetto). Il runner è in `~/.claude/plugins/…/cleanloop/scripts/cleanloop.sh`; per trovarlo: `claude plugin details cleanloop`.

## Uso rapido

```bash
# 1. nel progetto su cui lavorare
bash /path/to/cleanloop/scripts/cleanloop.sh init --task "Migrare l'auth da sessioni a JWT"
$EDITOR TASK.md            # definizione di fatto, vincoli
# 2. loop autonomo (terminale)
bash /path/to/cleanloop/scripts/cleanloop.sh run
# 3. oppure sessione interattiva con gli hook attivi
claude --plugin-dir /path/to/cleanloop
> /cleanloop
```

Se non vuoi usare il marketplace: `--plugin-dir` funziona senza installazione (il runner lo passa da solo per le iterazioni).

## Configurazione (`.cleanloop/config`, o env)
| Variabile | Default | Significato |
|---|---|---|
| `CLEANLOOP_THRESHOLD` | 25 | % contesto → richiesta checkpoint |
| `CLEANLOOP_HARD` | 40 | % contesto → chiusura forzata dell'iterazione |
| `CLEANLOOP_MAX_ITER` | 20 | iterazioni massime per `run` |
| `CLEANLOOP_STALL_LIMIT` | 3 | iterazioni senza modifiche a PROGRESS.md → stop |
| `CLEANLOOP_PERMISSION_MODE` | auto | `auto` · `acceptEdits` · `bypassPermissions` (solo sandbox) |
| `CLEANLOOP_MODEL` | (default) | modello per le iterazioni |
| `CLEANLOOP_MAX_BUDGET_USD` | (nessuno) | budget per iterazione |
| `CLEANLOOP_CONTEXT_WINDOW` | autodetect | token della finestra |

Gli hook sono **inerti** nei progetti senza `.cleanloop/enabled` (o senza `CLEANLOOP_ACTIVE=1`).

## Condizioni di stop del loop
`STATUS: DONE` (exit 0) · `STATUS: BLOCKED` (3) · stallo (2) · max iterazioni (4).

## Concetti di loop applicati
- **Fresh session per iterazione** (stile Ralph loop): niente accumulo, stato nei file.
- **Un'iterazione = un sotto-task verificato**: ogni checkpoint è a stato consistente.
- **Handoff esplicito**: `Prossimo passo` deve bastare a un agente con contesto vuoto.
- **Guardie**: soglia morbida/dura sul contesto, Stop hook, stallo, max iter, budget.
- **Rete di sicurezza**: `--autocompact` impostato oltre la soglia dura, e `PreCompact` che protegge lo stato se scatta prima.
