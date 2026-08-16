# Runner `cleanloop.sh`

Script bash (`scripts/cleanloop.sh`) che orchestra il loop a sessioni fresche. Non usa `timeout` (assente su macOS) né dipendenze oltre `bash`, `jq`, `claude`, `md5|md5sum`.

## Comandi
Vedi [Configurazione → Comandi del runner](../user-guide/configuration.md#comandi-del-runner). Qui i dettagli interni.

### `init`
1. `need_jq`.
2. Crea `.cleanloop/{state,logs}` e il file vuoto `.cleanloop/enabled`.
3. Se manca, scrive `.cleanloop/config` con tutte le variabili nel pattern `export VAR="${VAR:-default}"`.
4. Se manca `TASK.md`: con `--task` lo genera con obiettivo = testo e `T1` = testo; se stdin è un terminale apre il wizard (`read` per obiettivo, task, vincoli); altrimenti copia il template. Se manca `PROGRESS.md`, lo genera con Obiettivo e Piano derivati da `TASK.md`.

### `add ["testo"]`
Inserisce il blocco `- [ ] T<max+1>: prima riga` + continuazioni indentate alla fine della sezione `## Task` di `TASK.md` (awk: prima riga vuota dopo l'intestazione; il blocco è passato via file temporaneo). Senza argomento e con stdin terminale: `read_block` in loop — riga vuota chiude il task, `.` da sola o EOF chiude l'elenco. Non tocca `PROGRESS.md` (l'allineamento del Piano è compito del modello alla ripresa).

### `tasks`
Stampa le righe checkbox di `## Task` con ✔ se spuntate in `TASK.md` o se in `PROGRESS.md` esiste `- [x] … T<n>`.
5. Se il progetto è un repo git e `.gitignore` non contiene `.cleanloop/state`, aggiunge `state/` e `logs/`.

### `run [-n N]`
```
start_iter = ITERATION(PROGRESS.md) + 1
stall = 0
for i in start_iter .. start_iter+N-1:
    STATUS == DONE    → exit 0
    STATUS == BLOCKED → exit 3
    before = checksum(PROGRESS.md)
    run_iteration(i)                       # vedi sotto
    after  = checksum(PROGRESS.md)
    before == after ? stall++ : stall = 0
    stall ≥ STALL_LIMIT → exit 2
STATUS == DONE ? exit 0 : exit 4
```
`ITERATION` viene letta da `PROGRESS.md` così una `run` interrotta riparte con la numerazione giusta.

### `run_iteration i`
Argomenti passati a `claude`:
| Argomento | Valore | Perché |
|---|---|---|
| `-p` | | non interattivo |
| `--plugin-dir` | radice del plugin | carica hook e skill anche se il plugin non è installato |
| `--permission-mode` | `CLEANLOOP_PERMISSION_MODE` | nessuno risponde ai prompt in `-p` |
| `--autocompact` | `window × (HARD+25)/100`, limitato a [100k, 1M] | rete di sicurezza ben oltre la soglia dura |
| `--append-system-prompt-file` | `prompts/iteration-system.md` | regole dell'iterazione garantite anche se la skill non viene invocata |
| `--name` | `cleanloop-<i>` | riconoscibile in `/resume` |
| `--model` | `CLEANLOOP_MODEL` | solo se impostato |
| `--max-budget-usd` | `CLEANLOOP_MAX_BUDGET_USD` | solo se impostato |
| prompt | "Iterazione i/N di cleanloop. Il task è in TASK.md, lo stato in PROGRESS.md (già iniettati). Riparti dall'handoff, completa e verifica UN sotto-task, aggiorna PROGRESS.md, termina." | |

Ambiente esportato al processo: `CLEANLOOP_ACTIVE=1` (attiva Stop hook e messaggi "termina il turno"), `CLEANLOOP_ITER=i`, `CLEANLOOP_ROOT`.

Dopo ogni iterazione aggiunge a `LOOPLOG.md` la riga `| i | HH:MM:SS | pct% (usati / finestra) | motivo | STATUS |` (motivo: fine naturale / soglia / soglia dura, più `exit rc` se ≠ 0). Eventi: `iter_start` prima di lanciare `claude`; `iter_end` dopo, con durata, exit code, ultima misura di contesto (`state/last.json`), `reason` derivato dal livello di soglia raggiunto nella sessione, e `progress`/`status`; `loop_start`/`loop_stop` intorno al ciclo. Tutto in `.cleanloop/logs/events.log`.

Output: stdout+stderr di `claude` in `tee` su `.cleanloop/logs/iter-<NNN>-<YYYYmmdd-HHMMSS>.log`; il codice di uscita di `claude` è quello di `PIPESTATUS[0]` e viene solo segnalato (non interrompe il loop: la decisione è basata sul progresso di `PROGRESS.md`).

### `status`, `reset`, `disable`
- `status`: attivo?, `STATUS`/`ITERATION` da `PROGRESS.md`, soglie e finestra, ultimo `state/last.json`, ultimi 3 log.
- `reset`: `rm -rf .cleanloop/state` — utile se un marker per sessione è rimasto sporco. Non tocca `PROGRESS.md` né i log.
- `disable`: rimuove `.cleanloop/enabled`; gli hook tornano inerti nel progetto (`init` li riattiva).

## Perché la sessione non è persistita con `--no-session-persistence`
Gli hook leggono il transcript per misurare il contesto: la persistenza serve. Le sessioni `cleanloop-<i>` restano nel picker di `/resume` e possono essere ispezionate a posteriori.
