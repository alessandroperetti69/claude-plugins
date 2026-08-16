#!/usr/bin/env bash
# Hook SessionStart (startup|resume|clear|compact): segna l'inizio sessione e
# reinietta lo stato (PROGRESS.md) così la sessione riparte dall'handoff.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty'); cwd="${cwd:-$PWD}"
cleanloop_is_active "$cwd" || exit 0
cleanloop_load_config "$cwd"
session=$(printf '%s' "$input" | jq -r '.session_id // "nosession"')
source=$(printf '%s' "$input" | jq -r '.source // "startup"')
state=$(cleanloop_state_dir "$cwd")
read -r prev_pct prev_used prev_window prev_session <<< "$(cleanloop_last_ctx "$cwd")"
mode_label=interactive; [ "${CLEANLOOP_ACTIVE:-0}" = "1" ] && mode_label="loop iter=${CLEANLOOP_ITER:-?}"
cleanloop_log "$cwd" "event=session_start source=$source mode=$mode_label session=$session prev_ctx=${prev_pct}% prev_used=$prev_used prev_session=$prev_session"
cleanloop_checksum "$cwd/$CLEANLOOP_PROGRESS_FILE" > "$state/$session.start"
rm -f "$state/$session.level" "$state/$session.count"

progress="$cwd/$CLEANLOOP_PROGRESS_FILE"
task="$cwd/$CLEANLOOP_TASK_FILE"
mode="interattiva"; [ "${CLEANLOOP_ACTIVE:-0}" = "1" ] && mode="loop (iterazione ${CLEANLOOP_ITER:-?}/${CLEANLOOP_MAX_ITER})"

body="[cleanloop] attivo — modalità $mode. Soglia contesto: ${CLEANLOOP_THRESHOLD}% (dura ${CLEANLOOP_HARD}%). Regole: un sotto-task per volta, verifica prima di dichiarare fatto, aggiorna $CLEANLOOP_PROGRESS_FILE al checkpoint, in CLAUDE.md solo fatti durevoli. La sezione '## Task' di $CLEANLOOP_TASK_FILE è la CODA dell'utente (può crescere tra un'iterazione e l'altra): ogni voce che manca nel Piano di $CLEANLOOP_PROGRESS_FILE va aggiunta al Piano; i task si eseguono in ordine."
case "$source" in
  clear|compact) body="$body
Sessione ripulita ($source): NON ricostruire la storia, riparti dall'handoff in $CLEANLOOP_PROGRESS_FILE." ;;
esac
if [ -f "$task" ]; then
  body="$body

=== $CLEANLOOP_TASK_FILE ===
$(head -c 6000 "$task")"
fi
if [ -f "$progress" ]; then
  body="$body

=== $CLEANLOOP_PROGRESS_FILE ===
$(head -c 8000 "$progress")"
else
  body="$body
Nessun $CLEANLOOP_PROGRESS_FILE trovato: crealo dal template della skill cleanloop prima di iniziare."
fi
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$(printf '%s' "$body" | cleanloop_json_str)"
