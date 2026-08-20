# Runner `cleanloop.sh`

Script bash (`scripts/cleanloop.sh`) che orchestra il loop a sessioni fresche. Non usa `timeout` (assente su macOS) né dipendenze oltre `bash`, `jq`, `claude`, `md5|md5sum`. Scritto per bash 3.2 (quello di default su macOS): niente array associativi, niente `local -n`, array indicizzati sempre dietro `${#arr[@]} -gt 0` prima di espanderli con `"${arr[@]}"` (bash 3.2 tratta l'espansione di un array vuoto come variabile non impostata sotto `set -u`).

## Comandi
Vedi [Configurazione → Comandi del runner](../user-guide/configuration.md#comandi-del-runner). Qui i dettagli interni.

## Config: `CFG_KEYS`, `validate_cfg`, `set_cfg_var`
Le variabili configurabili da CLI sono elencate in `CFG_KEYS` (`THRESHOLD HARD MAX_ITER STALL_LIMIT REMIND_EVERY PERMISSION_MODE MODEL EFFORT MAX_BUDGET_USD CONTEXT_WINDOW PROGRESS_FILE TASK_FILE LOG_FILE USE_SUBAGENTS`). Tre comandi condividono la stessa logica:
- `validate_cfg CHIAVE VALORE`: valida secondo il tipo (interi per soglie/limiti, uno dei valori ammessi per `PERMISSION_MODE`/`EFFORT`/`USE_SUBAGENTS`, non vuoto per i nomi file, libero per `MODEL`); `die` se non valido — nessuna scrittura avviene.
- `set_cfg_var CHIAVE VALORE`: aggiorna la riga `export CLEANLOOP_<CHIAVE>="${CLEANLOOP_<CHIAVE>:-...}"` in `.cleanloop/config` se esiste già (sostituisce solo il default dentro `:-...}`, con `sed` su delimitatore `@` per tollerare `/` nei path), altrimenti l'aggiunge in fondo al file.

`init`, `config` e `run`/`once` costruiscono tutti i loro flag `--xxx` sullo stesso schema: parsing in un array `passed_keys`, poi un solo giro di `validate_cfg` su tutte le chiavi raccolte prima di scrivere o eseguire qualsiasi cosa.

### `init`
1. `need_jq`.
2. Parsing dei flag: `--task`, `--brief`, e uno per ogni chiave di `CFG_KEYS` (es. `--threshold`, `--model`, `--use-subagents`, …). Ogni flag di config aggiorna subito la variabile `CLEANLOOP_*` in processo e la registra in `passed_keys`; a fine parsing tutte le chiavi raccolte passano per `validate_cfg`.
3. Crea `.cleanloop/{state,logs}` e il file vuoto `.cleanloop/enabled`.
4. Se manca `.cleanloop/config`: lo scrive con tutte le variabili nel pattern `export VAR="${VAR:-default}"`, dove `default` è il valore corrente (che riflette gli eventuali flag passati). Se il file esiste già ed è stato passato almeno un flag di config, aggiorna solo quelle chiavi con `set_cfg_var` (le altre righe restano intatte).
5. Se manca `TASK.md`, in quest'ordine di priorità:
   1. `--task "testo"` → `T1` letterale (comportamento storico).
   2. `--brief PATH` o `--brief -` → legge il file o stdin (`read_brief_into`), scrive il contenuto in `BRIEF.md` (radice del progetto).
   3. `BRIEF.md` già presente in radice (nessun flag necessario).
   4. stdin non interattivo con contenuto (`pbpaste | cleanloop init`): letto per intero (`cat`), scritto in `BRIEF.md`.
   5. stdin è un terminale → `wizard` (obiettivo, task, vincoli, poi `wizard_config`, vedi sotto).
   6. altrimenti (stdin non interattivo e vuoto) → copia il template vuoto (comportamento invariato per script/CI che non passano nulla).
   Le varianti 2-4 chiamano `write_brief_task_file`: genera un `TASK.md` con un solo `T1` che chiede alla prima iterazione di leggere `BRIEF.md` e derivarne Obiettivo + coda reale, **senza** eseguire lavoro applicativo in quel turno (vedi [formati](file-formats.md#briefmd)).
6. Se manca `PROGRESS.md`, `write_progress_file` lo genera con Obiettivo e Piano derivati da `TASK.md`; in modalità brief riceve un handoff dedicato (parametro opzionale della funzione) che punta esplicitamente a `BRIEF.md` invece del testo generico.
7. Se il progetto è un repo git e `.gitignore` non contiene `.cleanloop/state`, aggiunge `state/` e `logs/`.

### `wizard` / `wizard_config`
Solo nel percorso interattivo (stdin è un terminale, nessun `--task`/`--brief`, nessun `BRIEF.md` preesistente). `wizard` chiede obiettivo, task (`read_block`, multiriga) e vincoli come da sempre, scrive `TASK.md`, poi chiama `wizard_config`.

`wizard_config` chiede in sequenza, con **invio = mantieni il default mostrato** (il default riflette eventuali flag già passati a `init`):
1. Modello — menu numerato (`sonnet`/`opus`/`fable`/`haiku`/"altro" per un id completo); testo digitato direttamente (non un numero) è accettato come valore letterale.
2. Effort — stesso schema, menu `low/medium/high/xhigh/max`.
3. Permission mode — menu `auto`/`acceptEdits`/`bypassPermissions`.
4. Uso dei subagenti — s/N.
5. Soglia checkpoint, soglia dura, budget massimo (numero o vuoto = illimitato), iterazioni massime, stall limit — prompt numerici con retry su input non valido (`ask_int`/`ask_num_or_empty`).
6. Gate sì/no per i parametri avanzati: se sì, chiede anche remind-every, context-window e nome del log (`ask_text`).

Ogni risposta scrive subito la chiave corrispondente in `.cleanloop/config` con `set_cfg_var` (il file esiste già a questo punto, creato al passo 4 di `init`). `TASK_FILE`/`PROGRESS_FILE` **non** sono chiesti nel wizard: cambiarli dopo che `TASK.md` è già stato scritto disallineerebbe i nomi — restano configurabili solo da flag (`--task-file`/`--progress-file` su `init`) o a mano.

### `add ["testo"]`
Inserisce il blocco `- [ ] T<max+1>: prima riga` + continuazioni indentate alla fine della sezione `## Task` di `TASK.md` (awk: prima riga vuota dopo l'intestazione; il blocco è passato via file temporaneo). Senza argomento e con stdin terminale: `read_block` in loop — riga vuota chiude il task, `.` da sola o EOF chiude l'elenco. Non tocca `PROGRESS.md` (l'allineamento del Piano è compito del modello alla ripresa).

### `tasks`
Stampa le righe checkbox di `## Task` con ✔ se spuntate in `TASK.md` o se in `PROGRESS.md` esiste `- [x] … T<n>`.

### `config [CHIAVE=VALORE ...]`
Senza argomenti: stampa `.cleanloop/config` per intero. Con argomenti: per ciascuna coppia `CHIAVE=VALORE` (prefisso `CLEANLOOP_` opzionale, tolto se presente), valida con `validate_cfg` e scrive con `set_cfg_var`, poi esporta la variabile nel processo corrente. `die` alla prima coppia non valida (formato errato o chiave/valore fuori schema) senza aver toccato il file per quella coppia.

### `run [-n N] [opzioni di config]`
```
parsing: -n/--max-iter → max; ogni --xxx di CFG_KEYS → CLEANLOOP_xxx in processo, registrato in passed_keys
validate_cfg su ogni chiave in passed_keys (nessuna scrittura su disco: override solo per questa esecuzione)
start_iter = ITERATION(PROGRESS.md) + 1
stall = 0
for i in start_iter .. start_iter+max-1:
    STATUS == DONE    → exit 0
    STATUS == BLOCKED → exit 3
    before = checksum(PROGRESS.md)
    run_iteration(i)                       # vedi sotto
    after  = checksum(PROGRESS.md)
    before == after ? stall++ : stall = 0
    stall ≥ STALL_LIMIT → exit 2
STATUS == DONE ? exit 0 : exit 4
```
`ITERATION` viene letta da `PROGRESS.md` così una `run` interrotta riparte con la numerazione giusta. `once` è implementato come `cmd_run "$@" -n 1`: `-n 1` è sempre l'ultimo argomento passato, quindi vince su un eventuale `-n`/`--max-iter` che l'utente avesse anche passato a `once` (una sola iterazione è garantita indipendentemente dagli altri flag).

### `run_iteration i`
Argomenti passati a `claude`:
| Argomento | Valore | Perché |
|---|---|---|
| `-p --output-format stream-json --verbose` | | non interattivo; lo stream JSON viene salvato grezzo in `iter-NNN-….jsonl`, reso leggibile a video da `stream_pretty` (testo, `→ tool`, modello, riepilogo) e usato da `iteration_summary` per modello, token, costo, turni |
| `--plugin-dir` | radice del plugin | carica hook e skill anche se il plugin non è installato |
| `--permission-mode` | `CLEANLOOP_PERMISSION_MODE` | nessuno risponde ai prompt in `-p` |
| `--autocompact` | `window × (HARD+25)/100`, limitato a [100k, 1M] | rete di sicurezza ben oltre la soglia dura |
| `--append-system-prompt-file` | `prompts/iteration-system.md` | regole dell'iterazione garantite anche se la skill non viene invocata |
| `--forward-subagent-text` | sempre presente | inoltra nello stream gli eventi dei subagenti (Agent tool), taggati con `parent_tool_use_id`, così `stream_pretty` può renderli leggibili anche quando `USE_SUBAGENTS=0` ma il modello ne lancia comunque uno di sua iniziativa |
| `--name` | `cleanloop-<i>` | riconoscibile in `/resume` |
| `--model` | `CLEANLOOP_MODEL` | solo se impostato |
| `--effort` | `CLEANLOOP_EFFORT` | solo se impostato |
| `--max-budget-usd` | `CLEANLOOP_MAX_BUDGET_USD` | solo se impostato |
| prompt | "Iterazione i/N di cleanloop. Il task è in TASK.md, lo stato in PROGRESS.md (già iniettati). Riparti dall'handoff, completa e verifica UN sotto-task, aggiorna PROGRESS.md, termina." — se `CLEANLOOP_USE_SUBAGENTS=1`, in coda una frase che chiede di valutare il parallelismo per i task indipendenti con l'Agent tool (i subagenti riportano solo testo, mai file; il checkpoint su `PROGRESS.md` resta compito esclusivo del turno principale) | |

Ambiente esportato al processo: `CLEANLOOP_ACTIVE=1` (attiva Stop hook e messaggi "termina il turno"), `CLEANLOOP_ITER=i`, `CLEANLOOP_ROOT`.

Dopo ogni iterazione aggiunge a `LOOPLOG.md` la riga `| i | HH:MM:SS | modello | pct% (usati / finestra) | token iterazione | costo API eq. | motivo | STATUS |` (motivo: fine naturale / soglia / soglia dura, più `exit rc` se ≠ 0). Eventi: `iter_start` prima di lanciare `claude` (include `subagents=0|1`); `iter_end` dopo, con durata, exit code, ultima misura di contesto (`state/last.json`), token/costo/turni, `reason` derivato dal livello di soglia raggiunto nella sessione, e `progress`/`status`; `loop_start`/`loop_stop` intorno al ciclo. Tutto in `.cleanloop/logs/events.log`.

Output: stream grezzo in `.cleanloop/logs/iter-<NNN>-<ts>.jsonl`, versione leggibile (+ stderr) in `.cleanloop/logs/iter-<NNN>-<ts>.log`; a fine iterazione stampa `modello · token in/out · costo API eq. · turni`; il codice di uscita di `claude` è quello di `PIPESTATUS[0]` e viene solo segnalato (non interrompe il loop: la decisione è basata sul progresso di `PROGRESS.md`).

### `stream_pretty` e il tagging dei subagenti
Filtro `jq` che rende leggibile lo stream-json: testo dell'assistente, `→ NomeTool` per ogni tool_use, riepilogo finale. Distingue gli eventi del turno principale (`parent_tool_use_id` assente/null) da quelli di un subagente (`parent_tool_use_id` valorizzato, presente grazie a `--forward-subagent-text`):
- il tool_use che lancia un subagente (`.name=="Agent"`) stampa `→ subagente [tag] "description"`, dove `tag` sono le ultime 6 cifre del suo `id` (il `tool_use_id`, univoco per invocazione);
- ogni evento successivo con lo stesso `parent_tool_use_id` viene ristampato con lo stesso `[tag]` in testa (`[tag] → NomeTool`, `[tag] testo`), permettendo di seguire più subagenti paralleli distinguendoli riga per riga nel log.

Verificato empiricamente lanciando un subagente reale: i campi rilevanti sono `.parent_tool_use_id` (a livello dell'evento, non dentro `.message`) e, sul tool_use `Agent`, `.input.description`/`.input.prompt`.

### `status`, `reset`, `disable`
- `status`: attivo?, `STATUS`/`ITERATION` da `PROGRESS.md`, soglie e finestra, ultimo `state/last.json`, ultime righe di `LOOPLOG.md`, ultimi 5 eventi.
- `reset`: `rm -rf .cleanloop/state` — utile se un marker per sessione è rimasto sporco. Non tocca `PROGRESS.md` né i log.
- `disable`: rimuove `.cleanloop/enabled`; gli hook tornano inerti nel progetto (`init` li riattiva).

## Perché la sessione non è persistita con `--no-session-persistence`
Gli hook leggono il transcript per misurare il contesto: la persistenza serve. Le sessioni `cleanloop-<i>` restano nel picker di `/resume` e possono essere ispezionate a posteriori.
