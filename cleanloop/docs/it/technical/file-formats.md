# Formati dei file

## `TASK.md` (scritto dall'utente, generato da `init`)
```markdown
# TASK

## Obiettivo
<1-2 righe>

## Task (coda: aggiungi con `cleanloop add`)
- [ ] T1: ...
- [ ] T2: ...

## Vincoli
- ...

## Definizione di fatto
- [ ] Tutti i task della coda sono completati e verificati (comando/test indicato in PROGRESS.md)
```
- `## Obiettivo`: la prima riga non vuota è copiata nell'Obiettivo di `PROGRESS.md` da `init`.
- `## Task`: **coda ordinata**; ogni task inizia con `- [ ] T<n>: prima riga`; le righe successive del task sono indentate di 6 spazi (continuazione Markdown del punto elenco). Il runner (`add`) inserisce in coda con ID = max+1; `tasks` legge le righe checkbox fino a `## Definizione`. Il modello non modifica questa sezione (al più spunta), l'utente sì, in ogni momento.
- `## Definizione di fatto`: checkbox che il modello deve verificare prima di scrivere `STATUS: DONE`.

Iniettato dal `SessionStart` hook (primi 6000 byte).

## `PROGRESS.md` (riscritto da Claude a ogni checkpoint)
Le prime due righe dopo il titolo sono **lette dal runner** con `grep`:
```
STATUS: IN_PROGRESS      # IN_PROGRESS | DONE | BLOCKED   (a inizio riga, maiuscolo)
ITERATION: 3             # intero
```
Sezioni attese (template in `templates/PROGRESS.md`):
| Sezione | Contenuto |
|---|---|
| Obiettivo (1 riga) | cosa deve essere vero alla fine |
| Fatto | bullet sintetici, con il "come verificato" |
| In corso | cosa è a metà e dove esattamente (di norma vuoto al checkpoint) |
| Prossimo passo (handoff) | file, comando, cosa verificare: sufficiente per ripartire a contesto vuoto |
| Piano (sotto-task, spuntare) | checklist che rispecchia la coda di `TASK.md` (stessi ID `Tn`), eventualmente spezzata in sotto-task; pre-popolata da `init` |
| Decisioni | scelta + motivo, 1 riga ciascuna |
| Trappole / note | cose che fanno perdere tempo |
| Verifica | comando/i per controllare che funziona |

Vincoli: ~40 righe massime, **sostituire** non accumulare (il file è reiniettato integralmente a ogni iterazione, primi 8000 byte). Il progresso di un'iterazione è rilevato tramite checksum del file: un'iterazione che non lo modifica conta come stallo.

## `CLAUDE.md`
Non ha un formato imposto da cleanloop. Regola: solo fatti durevoli (comandi, convenzioni, vincoli, gotcha dell'ambiente), 1-3 righe per checkpoint, mai stato di avanzamento.

## `.cleanloop/config`
File shell sorgente da `lib.sh`; ogni riga è `export CLEANLOOP_X="${CLEANLOOP_X:-default}"` così l'ambiente ha la precedenza. Elenco variabili in [Configurazione](../user-guide/configuration.md).

## `.cleanloop/enabled`
File vuoto; la sua esistenza attiva gli hook nel progetto.

## `.cleanloop/state/`
| File | Contenuto |
|---|---|
| `last.json` | `{"session","used","window","pct","ts"}` — ultima misura del contesto (qualsiasi sessione) |
| `<session_id>.start` | checksum di `PROGRESS.md` all'avvio della sessione (usato dallo Stop hook) |
| `<session_id>.level` | `0`/`1`/`2`: livello di avviso già emesso |
| `<session_id>.count` | tool call dall'ultimo avviso (per i promemoria) |

## `.cleanloop/logs/`
`iter-<NNN>-<YYYYmmdd-HHMMSS>.log`: output completo di `claude -p` per l'iterazione `NNN`.

## `.cleanloop/logs/events.log`
Una riga per evento, `<ISO-8601> event=<tipo> chiave=valore …`, scritta dal runner e dagli hook (quindi anche in sessione interattiva). Leggibile con `cleanloop log [-n N]`; gli ultimi 5 in `cleanloop status`.

| Evento | Chi | Campi | Significato |
|---|---|---|---|
| `loop_start` | runner | `start_iter max_iter window` | avvio di `run` |
| `iter_start` | runner | `iter model threshold hard` | avvio di un'iterazione |
| `session_start` | hook SessionStart | `source mode session prev_ctx prev_used prev_session` | avvio/ripartenza di una sessione; **`prev_ctx`** è la percentuale di contesto dell'ultima misura prima del riavvio (la sessione precedente, o quella appena ripulita con `/clear`) |
| `threshold` | hook PostToolUse | `level=soft\|hard ctx used window mode session` | prima volta che si supera una soglia in una sessione |
| `iter_end` | runner | `iter exit dur ctx used window reason progress status [stall]` | fine iterazione: `ctx` = ultima misura della sessione, `reason` = `natural_end` / `soft_threshold` / `hard_threshold`, `progress` = `changed`/`unchanged` |
| `loop_stop` | runner | `reason=done\|blocked\|stall\|max_iter iters` | fine di `run` |

Esempio:
```
2026-08-16T11:31:18 event=iter_start iter=3 model=default threshold=25% hard=40%
2026-08-16T11:31:18 event=session_start source=startup mode=loop iter=3 session=3a25… prev_ctx=27% prev_used=271204 prev_session=9f1c…
2026-08-16T11:33:02 event=threshold level=soft ctx=26% used=262110 window=1000000 mode=loop iter=3 session=3a25…
2026-08-16T11:34:10 event=iter_end iter=3 exit=0 dur=172s ctx=29% used=290877 window=1000000 reason=soft_threshold session=3a25… progress=changed status=IN_PROGRESS
```
