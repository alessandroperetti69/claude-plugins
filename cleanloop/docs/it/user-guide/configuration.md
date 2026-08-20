# Configurazione (riferimento)

## Dove si configura
Precedenza (dalla più alta): **variabile d'ambiente** → `.cleanloop/config` del progetto → default. `.cleanloop/config` è un file shell creato da `init`, con il pattern `export VAR="${VAR:-default}"`, per cui l'ambiente vince sempre.

## Variabili

| Variabile | Default | Effetto |
|---|---|---|
| `CLEANLOOP_THRESHOLD` | `25` | % della finestra oltre cui l'hook chiede il checkpoint (soglia morbida) |
| `CLEANLOOP_HARD` | `40` | % oltre cui chiede di fermarsi subito (soglia dura) |
| `CLEANLOOP_REMIND_EVERY` | `6` | dopo la soglia, ogni quante tool call ripetere il promemoria |
| `CLEANLOOP_MAX_ITER` | `20` | iterazioni massime per `run` (sovrascrivibile con `-n`) |
| `CLEANLOOP_STALL_LIMIT` | `3` | iterazioni consecutive senza modifiche a `PROGRESS.md` prima dello stop per stallo |
| `CLEANLOOP_PERMISSION_MODE` | `auto` | `--permission-mode` passato a `claude -p`: `auto`, `acceptEdits`, `bypassPermissions` (solo sandbox) |
| `CLEANLOOP_MODEL` | *(vuoto)* | modello per le iterazioni (`sonnet`, `opus`, id completo); vuoto = default dell'utente |
| `CLEANLOOP_EFFORT` | *(vuoto)* | `--effort` passato a `claude -p`: `low`, `medium`, `high`, `xhigh`, `max`; vuoto = default di sessione |
| `CLEANLOOP_MAX_BUDGET_USD` | *(vuoto)* | tetto di spesa **per iterazione** (`--max-budget-usd`) |
| `CLEANLOOP_CONTEXT_WINDOW` | *(autodetect)* | token della finestra; se vuoto: 1.000.000 se il modello in `~/.claude/settings.json` contiene `[1m]`, altrimenti 200.000 |
| `CLEANLOOP_PROGRESS_FILE` | `PROGRESS.md` | nome del file di avanzamento |
| `CLEANLOOP_TASK_FILE` | `TASK.md` | nome del file del task |
| `CLEANLOOP_LOG_FILE` | `LOOPLOG.md` | nome del log leggibile (tabella uscite/ripartenze) |
| `CLEANLOOP_USE_SUBAGENTS` | `0` | `1` = l'iterazione valuta il parallelismo: task indipendenti in coda vengono affidati a sub-agenti (Agent tool) invece di essere fatti in sequenza |
| `CLEANLOOP_ACTIVE` | *(impostata dal runner)* | `1` = modalità loop: attiva lo `Stop` hook e i messaggi "termina il turno" |

### Subagenti (`CLEANLOOP_USE_SUBAGENTS`)
Con `1`, il prompt dell'iterazione istruisce il turno principale a: valutare se i task pendenti in coda sono indipendenti (nessuna dipendenza, nessun file in comune) e, se sì, lanciarli in parallelo con l'Agent tool; far restituire ai subagenti il risultato come testo (non farli scrivere file — alcuni pattern di nome sono bloccati per i subagent) e applicare lui le modifiche; scrivere `PROGRESS.md` solo lui, a fine turno, dopo aver raccolto tutti i risultati.

Le iterazioni girano sempre con `--forward-subagent-text`: le righe generate dai subagenti compaiono nel log (`.cleanloop/logs/iter-NNN-*.log`, e nel terminale se lanci `run`/`once` in primo piano) taggate con le ultime 6 cifre dell'id del subagente, es.:
```
  → subagente [7SuPBn] "conta le righe di a.txt"
  [7SuPBn] → Bash
  [7SuPBn] Ho eseguito wc -l: 42 righe.
```
Per seguirli in diretta durante un `run` in background: `tail -f .cleanloop/logs/iter-NNN-*.log` (il nome esatto lo stampa `run`/`once` all'avvio dell'iterazione, o l'ultimo con `ls -t .cleanloop/logs/iter-*.log | head -1`).

### Scegliere le soglie
La soglia è una percentuale della finestra: con un modello a 1M token, 25% = 250k token, che è già molto lavoro per iterazione. Valori indicativi:
- finestra 200k: 25/40 (default) va bene;
- finestra 1M: prova 15/25 per iterazioni più corte e riprese più frequenti.

## Configurare da riga di comando

Tutte le variabili sopra (tranne `CLEANLOOP_ACTIVE`, gestita dal runner) si impostano da CLI, senza editare `.cleanloop/config` a mano:

- **al setup**, con `cleanloop init`: ogni variabile ha un flag corrispondente (`--threshold`, `--hard`, `--max-iter`, `--stall-limit`, `--remind-every`, `--permission-mode`, `--model`, `--effort`, `--max-budget-usd`, `--context-window`, `--progress-file`, `--task-file`, `--log-file`, `--use-subagents`). Es.:
  ```bash
  cleanloop init --task "Paginazione API" --threshold 15 --hard 25 --permission-mode acceptEdits
  ```
- **al setup, interattivamente**: il wizard (`cleanloop init` da terminale, senza `--task`/`--brief`) dopo obiettivo/task/vincoli chiede in sequenza modello (menu con alias + "altro" per un id completo), effort, permission mode, uso dei subagenti, soglie, budget e iterazioni massime — **invio mantiene il default mostrato** (che riflette eventuali flag già passati a `init`). Chiude con una domanda sì/no per i parametri avanzati (promemoria, finestra di contesto, nome log); i nomi di `TASK.md`/`PROGRESS.md` non sono modificabili lì (già scritti a quel punto) — solo da flag o a mano.
- **dopo il setup**, con `cleanloop config CHIAVE=VALORE` (nome della variabile senza prefisso `CLEANLOOP_`, anche più coppie insieme). Senza argomenti stampa la config corrente:
  ```bash
  cleanloop config                          # mostra .cleanloop/config
  cleanloop config THRESHOLD=15 HARD=25     # aggiorna due soglie
  cleanloop config MODEL=                   # svuota: torna al default dell'utente
  ```
- **rilanciando `init`** con nuovi flag su un progetto già inizializzato: aggiorna solo le chiavi passate, senza toccare `TASK.md`/`PROGRESS.md` già esistenti.
- **una tantum, su `run`/`once`**: le stesse opzioni valgono come override solo per quell'esecuzione, senza scrivere `.cleanloop/config` (utile per provare un modello/soglia diversi senza cambiare la configurazione salvata del progetto):
  ```bash
  cleanloop once --model opus --effort high        # una iterazione con parametri diversi, una tantum
  cleanloop run -n 5 --permission-mode acceptEdits  # 5 iterazioni con permessi diversi dal default
  ```

Ogni valore è validato (numeri interi per le soglie, uno dei tre modi per `--permission-mode`, ecc.) prima di essere scritto; in caso di errore il file di config non viene toccato.

## Input dei task: brief invece del wizard

Alternativa al wizard/`--task`: dare in pasto un prompt libero o un documento e lasciare che sia la **prima iterazione** a organizzarsi la coda (Obiettivo + `Tn`), invece di strutturarla a mano. Utile anche per evitare il problema del paste riga-per-riga nel wizard (testo con a capi/punti si incasina in un prompt TTY interattivo).

Si attiva in uno di questi modi, in ordine di priorità su `init`:
1. `cleanloop init --brief PATH` — legge il file indicato
2. `cleanloop init --brief -` — legge stdin esplicitamente
3. `BRIEF.md` già presente in radice al momento di `init` (nessun flag necessario)
4. stdin non interattivo con contenuto, senza flag: `pbpaste | cleanloop init` (se stdin è vuoto o non interattivo senza dati, si ricade sul comportamento normale)

In tutti i casi il contenuto finisce in `BRIEF.md` (radice del progetto, tracciato in git come `TASK.md`/`PROGRESS.md`), e `TASK.md` viene generato con un solo `T1` che chiede alla prima iterazione di leggere `BRIEF.md`, derivare Obiettivo e coda reale, riscrivere `TASK.md` di conseguenza — **senza** iniziare lavoro applicativo in quel turno (solo pianificazione). `PROGRESS.md` riceve un handoff dedicato che lo rende esplicito. Dopo `init` in modalità brief conviene eseguire `cleanloop once` e rivedere `TASK.md` prima di lanciare `run` senza supervisione.

`--task` ha sempre priorità su `--brief` se entrambi sono passati.

## Comandi del runner

```
cleanloop init [--task "testo" | --brief PATH|-] [opzioni di config]  crea TASK.md, PROGRESS.md,
                                  .cleanloop/{config,enabled,state,logs}; aggiorna .gitignore. Da terminale senza
                                  flag: wizard, salvo rilevamento automatico di un brief (vedi sopra). Le opzioni
                                  di config (vedi sopra) sono applicabili anche rilanciando init su un progetto
                                  già inizializzato.
cleanloop add  ["testo"]          accoda un task (T<n>) a TASK.md; senza argomento: interattivo (task anche multiriga:
                                  riga vuota = successivo, "." da sola = fine)
cleanloop tasks                   elenca la coda con ✔ sui task spuntati nel Piano e "(+n righe)" per i task multiriga
cleanloop run  [-n N] [opzioni di config]  loop fino a DONE/BLOCKED/stallo/max iterazioni. Le opzioni di config
                                  (vedi sopra) valgono qui come override solo per questa esecuzione, senza
                                  scrivere .cleanloop/config.
cleanloop once [opzioni di config]  una sola iterazione (= run -n 1, stessi override di run)
cleanloop status                  stato: attivo, STATUS, ITERATION, soglie, finestra, ultimo % contesto, ultime righe di LOOPLOG.md e ultimi 5 eventi
cleanloop config [CHIAVE=VALORE ...]  senza argomenti: mostra .cleanloop/config; con argomenti: valida e aggiorna le chiavi indicate
cleanloop log [-n N]              log eventi (avvii/uscite iterazioni, soglie, ripartenze) con % contesto; -n = ultime N righe
cleanloop reset                   cancella .cleanloop/state (non tocca PROGRESS.md né i log)
cleanloop disable                 rimuove .cleanloop/enabled: hook inerti nel progetto
```
`init` e `run` verificano la presenza di `jq` (e `run` di `claude`).

## Codici di uscita del runner
| Codice | Significato |
|---|---|
| `0` | `STATUS: DONE` |
| `1` | errore d'uso o prerequisito mancante (`jq`, `claude`, file mancanti, progetto non inizializzato) |
| `2` | stallo: `CLEANLOOP_STALL_LIMIT` iterazioni senza modifiche a `PROGRESS.md` |
| `3` | `STATUS: BLOCKED` |
| `4` | raggiunto il massimo di iterazioni senza `DONE` |

## File e cartelle nel progetto
```
TASK.md                 task e definizione di fatto (tuo)
BRIEF.md                (solo modalità brief) prompt/documento di partenza da cui la prima iterazione deriva TASK.md
PROGRESS.md             stato di avanzamento (Claude)
LOOPLOG.md              log leggibile: una riga per uscita di iterazione / ripartenza, con % contesto
.cleanloop/config       configurazione del progetto
.cleanloop/enabled      interruttore: se esiste, gli hook sono attivi qui
.cleanloop/state/       last.json (ultima misura del contesto), marker per sessione (livello, contatore, checksum iniziale)
.cleanloop/logs/        iter-NNN-<ts>.log (output leggibile), iter-NNN-<ts>.jsonl (stream grezzo), events.log (log eventi)
```
`state/` e `logs/` sono aggiunti a `.gitignore` da `init` (se il progetto è un repo git).
