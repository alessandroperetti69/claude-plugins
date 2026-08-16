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
| `CLEANLOOP_MAX_BUDGET_USD` | *(vuoto)* | tetto di spesa **per iterazione** (`--max-budget-usd`) |
| `CLEANLOOP_CONTEXT_WINDOW` | *(autodetect)* | token della finestra; se vuoto: 1.000.000 se il modello in `~/.claude/settings.json` contiene `[1m]`, altrimenti 200.000 |
| `CLEANLOOP_PROGRESS_FILE` | `PROGRESS.md` | nome del file di avanzamento |
| `CLEANLOOP_TASK_FILE` | `TASK.md` | nome del file del task |
| `CLEANLOOP_ACTIVE` | *(impostata dal runner)* | `1` = modalità loop: attiva lo `Stop` hook e i messaggi "termina il turno" |

### Scegliere le soglie
La soglia è una percentuale della finestra: con un modello a 1M token, 25% = 250k token, che è già molto lavoro per iterazione. Valori indicativi:
- finestra 200k: 25/40 (default) va bene;
- finestra 1M: prova 15/25 per iterazioni più corte e riprese più frequenti.

## Comandi del runner

```
cleanloop init [--task "testo"]   crea TASK.md, PROGRESS.md, .cleanloop/{config,enabled,state,logs}; aggiorna .gitignore.
                                  Da terminale senza --task: wizard (obiettivo, task uno per riga, vincoli)
cleanloop add  ["testo"]          accoda un task (T<n>) a TASK.md; senza argomento: interattivo (task anche multiriga:
                                  riga vuota = successivo, "." da sola = fine)
cleanloop tasks                   elenca la coda con ✔ sui task spuntati nel Piano e "(+n righe)" per i task multiriga
cleanloop run  [-n N]             loop fino a DONE/BLOCKED/stallo/max iterazioni
cleanloop once                    una sola iterazione (= run -n 1)
cleanloop status                  stato: attivo, STATUS, ITERATION, soglie, finestra, ultimo % contesto, ultimi log e ultimi 5 eventi
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
PROGRESS.md             stato di avanzamento (Claude)
.cleanloop/config       configurazione del progetto
.cleanloop/enabled      interruttore: se esiste, gli hook sono attivi qui
.cleanloop/state/       last.json (ultima misura del contesto), marker per sessione (livello, contatore, checksum iniziale)
.cleanloop/logs/        iter-NNN-<timestamp>.log (output di ogni iterazione) e events.log (log eventi)
```
`state/` e `logs/` sono aggiunti a `.gitignore` da `init` (se il progetto è un repo git).
