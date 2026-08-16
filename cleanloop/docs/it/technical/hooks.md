# Hook (riferimento)

Registrati in `hooks/hooks.json`; ogni comando è `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<nome>.sh"` con timeout 10 s. Tutti leggono il JSON dell'evento da stdin, condividono `scripts/lib.sh` e **escono silenziosamente (exit 0, nessun output) se cleanloop non è attivo** nel `cwd` (`.cleanloop/enabled` assente e `CLEANLOOP_ACTIVE≠1`).

## Funzioni comuni (`lib.sh`)
| Funzione | Cosa fa |
|---|---|
| `cleanloop_load_config cwd` | sorgente `.cleanloop/config` poi applica i default; esporta le `CLEANLOOP_*` |
| `cleanloop_is_active cwd` | `CLEANLOOP_ACTIVE=1` oppure esiste `cwd/.cleanloop/enabled` |
| `cleanloop_context_window` | override → `[1m]` in settings → 1000000 → altrimenti 200000 |
| `cleanloop_used_tokens transcript` | somma `input + cache_creation + cache_read` dell'ultimo messaggio `assistant` |
| `cleanloop_pct used window` | percentuale intera arrotondata |
| `cleanloop_checksum file` | `md5 -q` (macOS) o `md5sum` (Linux); `none` se il file manca |
| `cleanloop_state_dir cwd` | crea e restituisce `cwd/.cleanloop/state` |
| `cleanloop_json_str` | stdin → stringa JSON escapata (via `jq -Rs`) |
| `cleanloop_log cwd testo…` | appende `<timestamp> testo` a `cwd/.cleanloop/logs/events.log` |
| `cleanloop_last_ctx cwd` | stampa `pct used window session` da `state/last.json` (o `0 0 0 -`) |
| `cleanloop_looplog cwd n pct used window motivo status` | appende una riga a `LOOPLOG.md` (crea l'intestazione se manca; con `n` vuoto crea solo l'intestazione) |
| `cleanloop_fmt_num n` | separatore delle migliaia con spazio (`290 877`) |
| `cleanloop_status_of cwd` | valore di `STATUS:` in `PROGRESS.md` |

## SessionStart — `session-start.sh`
- **Matcher**: `startup|resume|clear|compact`
- **Input usato**: `cwd`, `session_id`, `source`
- **Effetti**: se `source` è `clear`/`compact` e non si è in modalità loop, aggiunge la riga `↻` a `LOOPLOG.md` con il contesto prima del riavvio; registra `event=session_start` in `events.log` con `prev_ctx` (ultima misura del contesto prima del riavvio, da `state/last.json`); scrive il checksum iniziale di `PROGRESS.md` in `state/<session>.start`; azzera `<session>.level` e `<session>.count`.
- **Output**: `hookSpecificOutput.additionalContext` con: modalità (interattiva / loop con numero iterazione), soglie, regole in una riga; se `source` è `clear`/`compact` aggiunge "non ricostruire la storia, riparti dall'handoff"; poi `TASK.md` (max 6000 byte) e `PROGRESS.md` (max 8000 byte). Se `PROGRESS.md` manca, chiede di crearlo dal template.

## PostToolUse — `context-guard.sh`
- **Matcher**: tutti i tool
- **Input usato**: `cwd`, `session_id`, `transcript_path`
- **Stato per sessione**: `state/<session>.level` (0 = nessun avviso, 1 = soglia morbida, 2 = dura), `state/<session>.count` (tool call dopo l'avviso), `state/last.json` (`{session, used, window, pct, ts}` — letto da `cleanloop status`).
- **Logica**:
  1. `pct ≥ HARD` e `level < 2` → messaggio di chiusura forzata, `level=2`, `event=threshold level=hard` nel log.
  2. altrimenti `pct ≥ THRESHOLD` e `level < 1` → messaggio di checkpoint, `level=1`, `event=threshold level=soft` nel log.
  3. altrimenti se `level ≥ 1` → `count++`; ogni `CLEANLOOP_REMIND_EVERY` invia un promemoria breve.
- **Testo**: varia con la modalità. Loop (`CLEANLOOP_ACTIVE=1`): "…esegui il protocollo checkpoint e TERMINA IL TURNO". Interattiva: "…poi chiedi all'utente di eseguire /clear e riprendere con /cleanloop". In entrambi è accodato il protocollo di checkpoint in 4 punti.
- **Output**: `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":…},"systemMessage":…}` — `additionalContext` va al modello, `systemMessage` è la riga breve mostrata all'utente.

## PreCompact — `pre-compact.sh`
- **Matcher**: `auto|manual`
- **Output**: `additionalContext` che chiede al riassunto di conservare obiettivo, sotto-task in corso, prossimo passo, decisioni, comandi di verifica, e di aggiornare `PROGRESS.md` subito dopo.

## Stop — `stop-guard.sh`
- **Attivo solo con** `CLEANLOOP_ACTIVE=1` (modalità loop).
- **Input usato**: `cwd`, `session_id`, `stop_hook_active`
- **Logica**: se `stop_hook_active` è `true` → esci (già bloccato una volta). Se il checksum corrente di `PROGRESS.md` è uguale a quello in `state/<session>.start` → `{"decision":"block","reason":"…aggiorna PROGRESS.md…"}`; altrimenti nessun output.
- **Garanzia**: blocca al massimo una volta per sessione, quindi non può incastrare il loop.

## Contratto con Claude Code
- Campi letti dall'input: `cwd`, `session_id`, `transcript_path`, `source`, `stop_hook_active`.
- Campi emessi: `hookSpecificOutput.additionalContext` (SessionStart, PostToolUse, PreCompact), `systemMessage` (PostToolUse), `decision`/`reason` (Stop).
- Nessun hook usa exit code ≠ 0: gli errori interni sono silenziosi per non disturbare la sessione (verificare con `cleanloop status` e `.cleanloop/state/last.json`).
