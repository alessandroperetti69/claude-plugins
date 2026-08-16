# Primi passi

In questa guida installi cleanloop e completi un primo task in loop autonomo. Tempo: circa 10 minuti.

## Prerequisiti
- **Claude Code** ≥ 2.1 (`claude --version`)
- **jq** (`brew install jq` su macOS; `apt install jq` su Debian/Ubuntu)
- `bash` (presente su macOS e Linux)
- Accesso al repo del marketplace `alessandroperetti69/claude-plugins` con `git` autenticato (`gh auth login` o chiave SSH)

## 1. Installazione

Dentro una sessione di Claude Code:
```
/plugin marketplace add alessandroperetti69/claude-plugins
/plugin install cleanloop@peretti-plugins
```
oppure da terminale:
```bash
claude plugin marketplace add alessandroperetti69/claude-plugins
claude plugin install cleanloop@peretti-plugins
```

Verifica: `claude plugin details cleanloop` deve mostrare 1 skill e 4 hook.

## 2. Alias per il runner (consigliato)

Il runner del loop è uno script bash dentro il plugin installato. Aggiungi a `~/.zshrc` (o `~/.bashrc`):
```bash
alias cleanloop='bash ~/.claude/plugins/marketplaces/peretti-plugins/cleanloop/scripts/cleanloop.sh'
```
Ricarica la shell (`source ~/.zshrc`) e verifica con `cleanloop` (stampa l'uso).

## 3. Attiva cleanloop nel progetto

Nella radice del progetto su cui vuoi lavorare:
```bash
cleanloop init
```
Si apre un breve wizard: **obiettivo** (1 riga), poi i **task**, poi eventuali **vincoli**. Ogni task può occupare più righe (puoi incollare un prompt intero): **riga vuota** = passa al task successivo, **`.` da sola** = fine dell'elenco. Esempio:
```
Obiettivo (1 riga): Paginazione dell'endpoint GET /api/orders
Task in ordine di esecuzione. Ogni task può occupare più righe (incolla pure):
  riga vuota = task successivo · "." da sola = fine elenco
  T1> Aggiungere i parametri page/size a GET /api/orders.
      La risposta deve includere i metadati total, page, size.
                                          ← riga vuota: chiude T1
  T2> Test in tests/api/test_orders.py

  T3> .                                   ← fine elenco
Vincoli (cosa non toccare, stile, ...): riga vuota = prossimo · "." = fine
  - Non toccare l'autenticazione

  - .
```
Nota: una riga vuota *dentro* un testo incollato viene interpretata come separatore di task; se il prompt ha paragrafi, incollali uno alla volta o togli le righe vuote.
(In alternativa `cleanloop init --task "…"` crea tutto senza domande, con un solo task.)

Vengono creati:
- `TASK.md` — descrizione del task (da completare)
- `PROGRESS.md` — stato di avanzamento (lo aggiorna Claude)
- `.cleanloop/` — configurazione (`config`), interruttore (`enabled`), stato e log

> Da questo momento gli hook di cleanloop sono attivi **in questa cartella**. Negli altri progetti restano inerti.

## 4. Rifinisci `TASK.md`

La sezione `## Task` è la tua **coda**: puoi aggiungere voci in ogni momento, anche a loop avviato, con `cleanloop add "…"` (o `cleanloop add` per inserirne più d'una). `cleanloop tasks` la mostra con lo stato.

Apri `TASK.md` e completa la **Definizione di fatto** con condizioni verificabili da un comando. Esempio:
```markdown
## Definizione di fatto
- [ ] `GET /api/orders?page=2&size=20` restituisce 20 elementi e i metadati `total`, `page`, `size`
- [ ] `pytest tests/api/test_orders.py` passa
- [ ] nessuna modifica allo schema del database

## Vincoli
- Non toccare l'autenticazione
- Stile: seguire `docs/api-conventions.md`
```
Più la definizione è precisa, più il loop sa **quando fermarsi**.

## 5. Lancia il loop

```bash
cleanloop run
```
Ogni iterazione è una sessione `claude -p` **nuova** (contesto vuoto) che:
1. riceve `TASK.md` e `PROGRESS.md`,
2. riparte dal "Prossimo passo (handoff)",
3. completa e verifica **un** sotto-task,
4. aggiorna `PROGRESS.md` e termina.

Il loop si ferma quando `PROGRESS.md` riporta `STATUS: DONE` (o `BLOCKED`, o dopo il numero massimo di iterazioni). Da un altro terminale:
```bash
cleanloop status
```

## 6. Revisione

A fine loop leggi `PROGRESS.md` (sezioni *Fatto*, *Decisioni*, *Verifica*) e rivedi il diff come faresti con una pull request. I log di ogni iterazione sono in `.cleanloop/logs/`.

## Prossimi passi
- [Guida all'uso](usage.md): modalità interattiva, uso in team, buone pratiche
- [Configurazione](configuration.md): soglie, modello, budget, permessi
