# cleanloop — regole dell'iterazione

Stai lavorando dentro un loop a sessioni fresche: ogni iterazione parte con contesto vuoto e riceve TASK.md e PROGRESS.md. Lo STATO VIVE NEI FILE, non nella tua memoria di conversazione.

Regole non negoziabili:
1. Prima di agire leggi PROGRESS.md (già iniettato) e riparti ESATTAMENTE dal "Prossimo passo (handoff)". Non rifare lavoro già in "Fatto". Non ri-esplorare il progetto se le info servono sono già in PROGRESS.md/CLAUDE.md.
2. Un'iterazione = UN sotto-task chiuso e verificato (test/build/comando di verifica). Meglio piccolo e verificato che grande e a metà.
3. Quando l'hook cleanloop ti dice che il contesto ha superato la soglia: chiudi il sotto-task corrente, esegui il checkpoint e termina il turno. Non iniziare niente di nuovo.
4. Checkpoint = aggiornare PROGRESS.md (Fatto / In corso / Prossimo passo preciso / Piano spuntato / Decisioni / Trappole / ITERATION) in modo SINTETICO (~40 righe max, sostituisci, non accumulare). Se hai scoperto fatti durevoli sul progetto (comandi, convenzioni, vincoli), 1-3 righe in CLAUDE.md. Niente log di sessione in CLAUDE.md.
5. STATUS: DONE solo quando la "Definizione di fatto" di TASK.md è tutta verificata. STATUS: BLOCKED (con motivo e cosa serve dall'umano) se non puoi procedere. Altrimenti IN_PROGRESS.
6. Termina SEMPRE il turno con PROGRESS.md aggiornato e con una risposta finale di 2-4 righe: cosa hai fatto, cosa resta, STATUS.
7. `TASK.md` sezione "## Task" è la coda dell'utente e può cambiare tra un'iterazione e l'altra: all'inizio confronta coda e Piano; aggiungi al Piano le voci nuove (stesso ID Tn), non rimuovere mai voci non fatte. Esegui i task in ordine salvo dipendenze evidenti (annotale in Decisioni).
8. Non chiedere conferme all'utente: non c'è nessuno a rispondere. Prendi decisioni ragionevoli e annotale in "Decisioni".
9. Se usi sub-agenti (Agent tool): falli riportare il risultato come testo, non fargli scrivere file (alcuni pattern di nome file sono bloccati per i subagent) — applica tu le modifiche. Solo tu, il turno principale, scrivi PROGRESS.md.
