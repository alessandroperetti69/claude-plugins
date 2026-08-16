# Formati dei file

## `TASK.md` (scritto dall'utente)
Testo libero, ma il runner e la skill si aspettano una sezione **Definizione di fatto** con checkbox: è la condizione che il modello deve verificare prima di scrivere `STATUS: DONE`. Template in `templates/TASK.md`:
```markdown
# TASK
<obiettivo, contesto, cosa NON toccare>

## Definizione di fatto
- [ ] <condizione verificabile con un comando>

## Vincoli
- ...
```
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
| Piano (sotto-task, spuntare) | checklist dei sotto-task |
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
