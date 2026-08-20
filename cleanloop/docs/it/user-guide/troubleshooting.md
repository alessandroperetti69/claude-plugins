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
- `used` (i token consumati) è affidabile: è la stessa formula e lo stesso transcript che alimentano la statusline di Claude Code — verificato confrontando i due valori dal vivo, differivano solo per i secondi passati tra una misura e l'altra.
- La finestra invece è una **stima**, non una lettura: l'hook `PostToolUse` di Claude Code non riceve mai il campo `context_window` reale (solo la statusline lo riceve, e i plugin non ci accedono). cleanloop deduce la finestra dal nome del modello: 200k se contiene "haiku", altrimenti 1M (tutti i modelli Claude attuali hanno 1M di contesto standard tranne Haiku). Se il tuo account/piano ha una finestra diversa dal default del modello, imposta `CLEANLOOP_CONTEXT_WINDOW` esplicitamente — è l'unico modo per essere sicuri, confronta con quanto mostra la tua statusline.
- Subito dopo `/clear` la misura di `used` può risultare quella vecchia finché non parte la prima tool call della sessione nuova.
- `cleanloop status` mostra l'ultima misura (`.cleanloop/state/last.json`); è **un file per progetto, non per sessione** — con due sessioni Claude Code aperte in parallelo sulla stessa cartella, l'ultima a scrivere vince e il numero mostrato può riferirsi all'altra sessione (cosmetico: non causa falsi avvisi, perché la soglia dell'hook usa sempre il transcript della sessione corrente, non questo file).

### La soglia scatta quasi subito dopo ogni checkpoint, anche con la finestra corretta
Non è un bug di misura: è il "pavimento" fisso di ogni sessione. Il primissimo turno assistant di una sessione — prima di qualunque lavoro — include già system prompt + schemi dei tool + catalogo delle skill installate, tutto ricreato a ogni `/clear`. Con molti plugin/skill abilitati (specialmente il plugin Vercel, che da solo porta ~30 skill) questo pavimento può valere alcune migliaia di token; il resto — di solito la parte più grossa, spesso il 90%+ del pavimento — è il system prompt e gli schemi dei tool nativi di Claude Code, non qualcosa che i plugin o cleanloop controllano. Se lavori interattivamente (non nel loop a sessioni fresche) e il checkpoint richiesto ricompare quasi subito dopo ogni `/clear`, la soglia (default 25%/40%) è probabilmente troppo stretta per il tuo pavimento fisso: alza `CLEANLOOP_THRESHOLD`/`CLEANLOOP_HARD` (`cleanloop config THRESHOLD=... HARD=...`) invece di cercare un bug — cleanloop non ha modo di sottrarre il pavimento dal calcolo (le percentuali sono assolute sulla finestra, non relative all'inizio sessione).

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
