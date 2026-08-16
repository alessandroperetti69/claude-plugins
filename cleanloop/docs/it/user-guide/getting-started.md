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
cleanloop init --task "Aggiungere la paginazione all'endpoint GET /api/orders"
```
Vengono creati:
- `TASK.md` — descrizione del task (da completare)
- `PROGRESS.md` — stato di avanzamento (lo aggiorna Claude)
- `.cleanloop/` — configurazione (`config`), interruttore (`enabled`), stato e log

> Da questo momento gli hook di cleanloop sono attivi **in questa cartella**. Negli altri progetti restano inerti.

## 4. Scrivi bene `TASK.md`

Apri `TASK.md` e completa soprattutto la **Definizione di fatto**: condizioni verificabili con un comando. Esempio:
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
