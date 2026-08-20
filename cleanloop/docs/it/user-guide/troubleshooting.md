# Risoluzione problemi

### `/cleanloop` non compare nella sessione
- Il plugin è installato? `claude plugin details cleanloop`.
- La sessione è partita prima dell'installazione: apri una nuova sessione.
- Con `--plugin-dir` il percorso deve puntare alla cartella `cleanloop/` (quella con `.claude-plugin/`).

### Gli hook non fanno niente
Per design sono inerti finché il progetto non è attivato: serve `.cleanloop/enabled` (creato da `cleanloop init`) oppure `CLEANLOOP_ACTIVE=1`. Controlla con `cleanloop status` (riga `attivo:`).

### Ho incollato un elenco di task nel wizard e si è incasinato tutto
Il wizard legge riga per riga (`read` in un prompt TTY): testo incollato con righe vuote o punteggiatura può essere interpretato come separatore tra un task e l'altro. Evita del tutto l'incollaggio interattivo con la **modalità brief**: `pbpaste | cleanloop init` (o `cleanloop init --brief file.md`). Il testo va in `BRIEF.md` intatto, e la prima iterazione lo legge e organizza da sé la coda in `TASK.md` — nessun parsing riga-per-riga nel terminale. Dettagli in [Configurazione](configuration.md#input-dei-task-brief-invece-del-wizard).

### La percentuale di contesto sembra sbagliata
- La finestra è autodetect: 1M se il modello in `~/.claude/settings.json` contiene `[1m]`, altrimenti 200k. Se usi un modello diverso nel loop (`CLEANLOOP_MODEL`), imposta `CLEANLOOP_CONTEXT_WINDOW` esplicitamente.
- La misura è presa dall'`usage` dell'ultimo messaggio dell'assistente nel transcript (`input + cache_creation + cache_read`), aggiornata a ogni tool call: subito dopo `/clear` può risultare la misura vecchia finché non parte la prima tool call.
- `cleanloop status` mostra l'ultima misura (`.cleanloop/state/last.json`).

### Voglio vedere quando e perché le iterazioni sono terminate
Apri `LOOPLOG.md` nel progetto: una riga per iterazione con ora, contesto all'uscita, motivo e STATUS (e righe `↻` per i `/clear` interattivi). Per il dettaglio, `cleanloop log` (o `-n 20`): per ogni iterazione `iter_end` riporta durata, `ctx=` (percentuale di contesto all'uscita) e `reason=` (`natural_end`, `soft_threshold`, `hard_threshold`); ogni `session_start` riporta `prev_ctx=`, cioè la percentuale prima del riavvio. Vale anche per le sessioni interattive con `/clear`.

### Il loop si ferma per "stallo"
Tre iterazioni consecutive non hanno modificato `PROGRESS.md`. Cause tipiche:
- permessi negati in `-p` (guarda l'ultimo log in `.cleanloop/logs/`): aggiungi permessi nel `.claude/settings.json` del progetto;
- `claude` termina con errore (budget esaurito, autenticazione): il runner stampa il codice di uscita;
- l'handoff in `PROGRESS.md` è ambiguo e ogni iterazione ricomincia a esplorare: riscrivilo a mano più preciso.
Dopo aver risolto: `cleanloop run` riparte dall'iterazione successiva a `ITERATION`.

### Iterazione che non termina mai / molto lunga
- Abbassa `CLEANLOOP_THRESHOLD`/`CLEANLOOP_HARD` (specie con finestra 1M).
- Metti un tetto: `CLEANLOOP_MAX_BUDGET_USD=2 cleanloop run`.
- Il sotto-task nel *Piano* è troppo grande: spezzalo in `PROGRESS.md`.

### `STATUS: DONE` ma il lavoro non è completo
La condizione di stop è la *Definizione di fatto* in `TASK.md`: se è vaga, Claude la ritiene soddisfatta troppo presto. Rendila verificabile con comandi. Puoi rimettere `STATUS: IN_PROGRESS`, aggiungere il passo mancante all'handoff e rilanciare `run`.

### `Stop` hook: "Non puoi terminare l'iterazione senza aggiornare PROGRESS.md"
È voluto: in modalità loop l'iterazione non può chiudersi senza checkpoint. Blocca una sola volta (poi Claude Code passa `stop_hook_active` e l'hook lascia uscire) — quindi anche se il modello insiste, il loop non si incastra.

### In sessione interattiva Claude dice di fare `/clear` ma io preferisco continuare
Puoi ignorarlo; l'hook ripeterà il promemoria ogni `CLEANLOOP_REMIND_EVERY` tool call. Per silenziarlo nel progetto: `cleanloop disable`.

### macOS: `timeout: command not found`
Il runner non usa `timeout`; se lo usi tu per incapsulare `cleanloop run`, installa `coreutils` (`gtimeout`).

### Come si aggiorna il plugin
```
/plugin marketplace update peretti-plugins
/plugin update cleanloop
```
La copia in `~/.claude/plugins/marketplaces/peretti-plugins/cleanloop` viene rinfrescata dal repo; l'alias continua a funzionare.
