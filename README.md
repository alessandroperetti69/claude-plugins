# peretti-plugins — marketplace Claude Code

Catalogo di plugin per Claude Code. Ogni cartella di primo livello è un plugin; l'indice è `.claude-plugin/marketplace.json`.

| Plugin | Cosa fa |
|---|---|
| [`go-no-go`](./go-no-go) | Valuta idee di business/startup con ricerca web, stress-test dei numeri e pre-mortem → verdetto GO / CONDITIONAL-GO / NO-GO. |
| [`cleanloop`](./cleanloop) | Tiene il contesto sotto soglia (25%), fa checkpoint su `PROGRESS.md`/`CLAUDE.md` e itera a sessioni fresche fino a `DONE`. Docs: [it](./cleanloop/docs/it/README.md) · [en](./cleanloop/docs/en/README.md) |

## Installazione (collaboratori)

Prerequisiti: accesso a questo repo (git autenticato verso GitHub: `gh auth login` o chiave SSH), `jq` (`brew install jq`).

Dentro Claude Code:
```
/plugin marketplace add alessandroperetti69/claude-plugins
/plugin install cleanloop@peretti-plugins
/plugin install go-no-go@peretti-plugins
```
oppure da terminale:
```bash
claude plugin marketplace add alessandroperetti69/claude-plugins
claude plugin install cleanloop@peretti-plugins
```

Aggiornare: `/plugin marketplace update peretti-plugins` poi `/plugin update cleanloop`.

## Attivarlo automaticamente in un progetto di team

Nel repo del progetto, `.claude/settings.json` (versionato):
```json
{
  "extraKnownMarketplaces": {
    "peretti-plugins": { "source": { "source": "github", "repo": "alessandroperetti69/claude-plugins" } }
  },
  "enabledPlugins": { "cleanloop@peretti-plugins": true }
}
```
Chi apre il progetto con Claude Code riceve la proposta di installare marketplace e plugin.

## Aggiungere un plugin

1. Crea la cartella `nome-plugin/` con `.claude-plugin/plugin.json` (e `skills/`, `hooks/`, `commands/`, `agents/` secondo necessità).
2. Aggiungi la voce in `.claude-plugin/marketplace.json` con `"source": "./nome-plugin"`.
3. Prova in locale: `claude --plugin-dir ./nome-plugin`, poi commit e push.
