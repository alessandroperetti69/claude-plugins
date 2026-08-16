# Sviluppo e rilascio

## Struttura del repo
Il repo `alessandroperetti69/claude-plugins` è un **marketplace** Claude Code: `.claude-plugin/marketplace.json` alla radice elenca i plugin, ognuno in una cartella di primo livello. cleanloop è in `cleanloop/`:
```
cleanloop/
├── .claude-plugin/plugin.json     manifest (nome, versione, descrizione)
├── skills/cleanloop/SKILL.md      la skill (auto-scoperta)
├── hooks/hooks.json               registrazione hook (auto-scoperta)
├── scripts/                       lib.sh, 4 hook, cleanloop.sh
├── prompts/iteration-system.md    system prompt aggiunto in -p
├── templates/                     TASK.md, PROGRESS.md
├── docs/{it,en}/                  questa documentazione
└── README.md
```

## Provare in locale senza installare
```bash
claude --plugin-dir /percorso/claude-plugins/cleanloop
```
Il runner passa `--plugin-dir` da solo, quindi `bash scripts/cleanloop.sh run` usa sempre il codice della cartella da cui è lanciato — comodo per sviluppare.

## Test manuali degli hook
Gli hook sono script puri: si testano con un JSON su stdin. Esempio (soglia superata con una finestra da 1M):
```bash
T=$(mktemp -d); cd "$T"
printf '{"type":"assistant","message":{"usage":{"input_tokens":1000,"cache_creation_input_tokens":9000,"cache_read_input_tokens":250000}}}\n' > tr.jsonl
bash /percorso/cleanloop/scripts/cleanloop.sh init --task prova
echo "{\"cwd\":\"$T\",\"session_id\":\"s1\",\"transcript_path\":\"$T/tr.jsonl\"}" \
  | bash /percorso/cleanloop/scripts/context-guard.sh | jq .
```
Casi da coprire quando si tocca la logica: hook inerte senza `.cleanloop/enabled`; primo avviso a soglia; silenzio alla chiamata successiva; promemoria ogni N; soglia dura; Stop hook che blocca una volta e poi lascia (con `stop_hook_active: true`); SessionStart con `source: clear`.

Test end-to-end: `cleanloop init --task "crea hello.txt con 'ciao'"`, `CLEANLOOP_MODEL=sonnet CLEANLOOP_MAX_BUDGET_USD=1 cleanloop once`, poi controllare `PROGRESS.md` (`STATUS: DONE`) e `.cleanloop/state/last.json`.

Sintassi: `bash -n scripts/*.sh`.

## Convenzioni
- Nessuna dipendenza oltre `bash`, `jq`, `md5|md5sum`, `claude`. Niente `timeout`, niente GNU-only.
- Gli hook non devono mai fallire rumorosamente: exit 0 e nessun output se non c'è nulla da dire.
- Testi per il modello in italiano (lingua dell'utente); identificatori e chiavi in inglese.
- Ogni modifica a soglie/formati va riportata in `docs/it` **e** `docs/en`.

## Rilascio
1. Aggiorna `version` in `cleanloop/.claude-plugin/plugin.json` e nella voce di `.claude-plugin/marketplace.json`; aggiungi la voce a `CHANGELOG.md`.
2. Commit e push su `main`.
3. Sulle macchine degli utenti: `/plugin marketplace update peretti-plugins` poi `/plugin update cleanloop`.

Versionamento semantico: patch = fix negli script/testi; minor = nuove opzioni o hook; major = cambio di formato di `PROGRESS.md`/config non retrocompatibile.
