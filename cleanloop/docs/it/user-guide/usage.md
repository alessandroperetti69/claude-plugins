# Guida all'uso

## Il modello mentale

cleanloop applica una regola sola: **lo stato del lavoro vive nei file, non nella conversazione**.

- `TASK.md` — cosa va fatto e quando è finito (lo scrivi tu).
- `PROGRESS.md` — dove siamo, cosa resta, da dove riprendere (lo aggiorna Claude a ogni *checkpoint*).
- `CLAUDE.md` — fatti durevoli sul progetto (comandi, convenzioni, vincoli), non lo stato.

Il contesto della conversazione è un buffer di lavoro usa-e-getta: quando supera la soglia (default 25% della finestra) si fa checkpoint e si riparte puliti.

## Le due modalità

### Loop autonomo (`cleanloop run`)
Per task lunghi su cui non vuoi stare a guardare.

```bash
cleanloop run            # fino a DONE/BLOCKED, max 20 iterazioni
cleanloop run -n 5       # al massimo 5 iterazioni
cleanloop once           # una sola iterazione (utile per provare)
cleanloop status         # STATUS, iterazione, ultimo % contesto, ultimi log
```

Ogni iterazione è un processo `claude -p` separato con contesto vuoto. Dentro l'iterazione:
- a **25%** l'hook chiede di chiudere il sotto-task corrente, fare checkpoint e terminare;
- a **40%** chiede di fermarsi subito;
- all'uscita l'hook `Stop` blocca la fine se `PROGRESS.md` non è stato modificato.

Ogni avvio/uscita di iterazione, superamento di soglia e ripartenza viene registrato in `.cleanloop/logs/events.log` con la percentuale di contesto del momento (`cleanloop log`, vedi [formati](../technical/file-formats.md#cleanlooplogseventslog)).

Il loop si ferma per: `STATUS: DONE` · `STATUS: BLOCKED` (serve un umano) · **stallo** (3 iterazioni senza modifiche a `PROGRESS.md`) · massimo iterazioni. Vedi [codici di uscita](configuration.md#codici-di-uscita-del-runner).

### Sessione interattiva (`claude` + `/cleanloop`)
Per quando vuoi seguire o intervenire.

```
claude
> /cleanloop
```
La skill legge `PROGRESS.md` e prosegue dall'handoff. Quando il contesto supera la soglia, Claude:
1. chiude il sotto-task, aggiorna `PROGRESS.md` (e se serve `CLAUDE.md`);
2. ti scrive: *"Checkpoint salvato in PROGRESS.md. Esegui `/clear` e poi `/cleanloop` per riprendere con contesto pulito."*

Tu fai `/clear` e `/cleanloop`: l'hook `SessionStart` reinietta `TASK.md` + `PROGRESS.md` e il lavoro riprende dall'handoff. Claude **non può** eseguire `/clear` da solo: è l'unico passaggio manuale.

Se preferisci `/compact` a `/clear`, funziona lo stesso: l'hook `PreCompact` chiede al riassunto di preservare lo stato.

### Mescolarle
Un pattern efficace:
1. **Interattivo** per definire il piano in `PROGRESS.md` (sezione *Piano*) e fare i primi passi delicati.
2. **`cleanloop run`** per macinare i sotto-task ripetitivi.
3. **Interattivo** per rifinire e chiudere.

## La coda dei task

`TASK.md`, sezione `## Task`, è una **coda ordinata** di proprietà tua:
```markdown
## Task (coda: aggiungi con `cleanloop add`)
- [ ] T1: Aggiungere page/size a GET /api/orders
- [ ] T2: Test in tests/api
```
- `cleanloop init` la crea con il wizard; `cleanloop add "…"` accoda (ID progressivo `Tn`), anche **mentre il loop gira**: la prossima iterazione la vede. Un task può essere multiriga (nel wizard e in `add` interattivo: riga vuota = task successivo, `.` = fine; da argomento: `cleanloop add $'prima riga\nseconda riga'`); le righe oltre la prima sono salvate indentate sotto il punto elenco.
- Il *Piano* in `PROGRESS.md` la rispecchia con gli stessi ID; a ogni ripresa Claude confronta coda e Piano e aggiunge le voci nuove. Può spezzare un task in sotto-task, mai rimuovere voci non fatte.
- `cleanloop tasks` mostra la coda con ✔ sulle voci spuntate nel Piano.
- Il loop termina (`STATUS: DONE`) quando la Definizione di fatto è verificata: di default "tutti i task della coda completati e verificati". Se accodi un task dopo il `DONE`, rimetti `STATUS: IN_PROGRESS` e rilancia `run`.

## Cosa succede a un checkpoint

Claude, in ordine:
1. porta i file a uno stato consistente ed esegue la verifica veloce disponibile (test/build);
2. **riscrive** `PROGRESS.md` (non accumula): `STATUS`, `ITERATION`, *Fatto*, *In corso*, *Prossimo passo (handoff)*, *Piano* spuntato, *Decisioni*, *Trappole*, *Verifica* — circa 40 righe al massimo;
3. aggiunge a `CLAUDE.md` solo fatti durevoli scoperti (1-3 righe), mai il log di sessione;
4. termina il turno (loop) o ti chiede di fare `/clear` (interattivo).

L'**handoff** è la parte più importante: deve permettere a un agente con contesto vuoto di ripartire senza ri-esplorare il progetto (file, comando, cosa verificare).

## Uso in team

### Attivazione automatica in un repo condiviso
Nel repo del progetto, `.claude/settings.json` (versionato):
```json
{
  "extraKnownMarketplaces": {
    "peretti-plugins": { "source": { "source": "github", "repo": "alessandroperetti69/claude-plugins" } }
  },
  "enabledPlugins": { "cleanloop@peretti-plugins": true }
}
```
Chi apre il progetto con Claude Code riceve la proposta di installare marketplace e plugin.

### `TASK.md` e `PROGRESS.md` come handoff tra persone
Versionali: `PROGRESS.md` è già un handoff leggibile ("dove siamo, cosa resta, decisioni prese"). Solo `.cleanloop/state/` e `.cleanloop/logs/` vanno ignorati (`init` li aggiunge a `.gitignore`).

### Permessi
In modalità `-p` nessuno può rispondere ai prompt di permesso. Se le iterazioni si fermano su tool negati:
- aggiungi permessi al `.claude/settings.json` del progetto (es. `Bash(pytest *)`), oppure
- `CLEANLOOP_PERMISSION_MODE=bypassPermissions` **solo in sandbox/container**.

## Buone pratiche
- **Definizione di fatto verificabile** in `TASK.md`: è la condizione di stop del loop.
- **Sotto-task piccoli**: un'iterazione = un sotto-task chiuso e verificato. Se un sotto-task non sta in un'iterazione, va spezzato.
- **Non ignorare la soglia** "perché manca poco": il contesto grande degrada la qualità *prima* di finire.
- **`CLAUDE.md` non è un diario**: solo fatti che serviranno anche fra un mese.
- **Rivedi il diff** a fine loop come una PR: il loop è autonomo, la responsabilità resta tua.
- **Budget**: `CLEANLOOP_MAX_BUDGET_USD` per iterazione e `-n` per limitare gli esperimenti.
- **Modello**: `CLEANLOOP_MODEL=sonnet` per i sotto-task meccanici, il modello di default per quelli delicati.
