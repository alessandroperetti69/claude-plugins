#!/usr/bin/env bash
# Hook PostToolUse: misura il contesto dal transcript e, oltre soglia, inietta
# l'istruzione di checkpoint. Silenzioso finché cleanloop non è attivo nel progetto.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty'); cwd="${cwd:-$PWD}"
cleanloop_is_active "$cwd" || exit 0
cleanloop_load_config "$cwd"

session=$(printf '%s' "$input" | jq -r '.session_id // "nosession"')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')

used=$(cleanloop_used_tokens "$transcript")
window=$(cleanloop_context_window)
pct=$(cleanloop_pct "$used" "$window")

state=$(cleanloop_state_dir "$cwd")
printf '{"session":"%s","used":%s,"window":%s,"pct":%s,"ts":"%s"}\n' \
  "$session" "$used" "$window" "$pct" "$(date +%FT%T)" > "$state/last.json"

level_file="$state/$session.level"; count_file="$state/$session.count"
level=$(cat "$level_file" 2>/dev/null || echo 0)
count=$(cat "$count_file" 2>/dev/null || echo 0)

loop_mode=0; [ "${CLEANLOOP_ACTIVE:-0}" = "1" ] && loop_mode=1
progress="$CLEANLOOP_PROGRESS_FILE"

emit() {  # $1 = testo per il modello, $2 = messaggio breve per l'utente
  local ctx sys
  ctx=$(printf '%s' "$1" | cleanloop_json_str)
  sys=$(printf '%s' "$2" | cleanloop_json_str)
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s},"systemMessage":%s}\n' "$ctx" "$sys"
}

checkpoint_steps="PROTOCOLLO CHECKPOINT (skill cleanloop):
1. Porta il lavoro a uno stato consistente (non lasciare file a metà; se hai un test/build veloce, eseguilo).
2. Aggiorna $progress: Fatto / In corso / Prossimo passo (handoff preciso: file, comando, cosa verificare) / Decisioni / Trappole. Aggiorna ITERATION. Massimo ~40 righe totali.
3. Se hai scoperto fatti DUREVOLI sul progetto (convenzioni, comandi, vincoli) aggiungili a CLAUDE.md in 1-3 righe. Niente log di sessione in CLAUDE.md.
4. Se il task è completo scrivi STATUS: DONE; se sei bloccato STATUS: BLOCKED con il motivo."

mode_label=interactive; [ $loop_mode = 1 ] && mode_label="loop iter=${CLEANLOOP_ITER:-?}"

if [ "$pct" -ge "$CLEANLOOP_HARD" ] && [ "$level" -lt 2 ]; then
  echo 2 > "$level_file"; echo 0 > "$count_file"
  cleanloop_log "$cwd" "event=threshold level=hard ctx=${pct}% used=$used window=$window mode=$mode_label session=$session"
  if [ $loop_mode = 1 ]; then
    emit "[cleanloop] CONTESTO AL ${pct}% (soglia dura ${CLEANLOOP_HARD}%). FERMATI ORA: nessun nuovo sotto-task. Esegui il protocollo checkpoint e TERMINA IL TURNO (rispondi con un riepilogo di 3 righe). Il loop riparte con contesto pulito da $progress.
$checkpoint_steps" "cleanloop: contesto ${pct}% ≥ ${CLEANLOOP_HARD}% — chiusura iterazione forzata"
  else
    emit "[cleanloop] CONTESTO AL ${pct}% (soglia dura ${CLEANLOOP_HARD}%). Interrompi il sotto-task corrente appena è a stato consistente, esegui il protocollo checkpoint, poi chiedi all'utente di eseguire /clear (o /compact) e riprendere con /cleanloop.
$checkpoint_steps" "cleanloop: contesto ${pct}% ≥ ${CLEANLOOP_HARD}% — serve checkpoint + /clear"
  fi
  exit 0
fi

if [ "$pct" -ge "$CLEANLOOP_THRESHOLD" ]; then
  if [ "$level" -lt 1 ]; then
    echo 1 > "$level_file"; echo 0 > "$count_file"
    cleanloop_log "$cwd" "event=threshold level=soft ctx=${pct}% used=$used window=$window mode=$mode_label session=$session"
    if [ $loop_mode = 1 ]; then
      emit "[cleanloop] CONTESTO AL ${pct}% (soglia ${CLEANLOOP_THRESHOLD}%). Concludi SOLO il sotto-task corrente (niente di nuovo), poi esegui il protocollo checkpoint e TERMINA IL TURNO. Il loop riparte con contesto pulito da $progress.
$checkpoint_steps" "cleanloop: contesto ${pct}% ≥ ${CLEANLOOP_THRESHOLD}% — checkpoint richiesto"
    else
      emit "[cleanloop] CONTESTO AL ${pct}% (soglia ${CLEANLOOP_THRESHOLD}%). Concludi SOLO il sotto-task corrente, esegui il protocollo checkpoint, poi chiedi all'utente di eseguire /clear e riprendere con /cleanloop (lo stato verrà reiniettato automaticamente).
$checkpoint_steps" "cleanloop: contesto ${pct}% ≥ ${CLEANLOOP_THRESHOLD}% — checkpoint richiesto"
    fi
    exit 0
  fi
  # già avvisato: promemoria periodico
  count=$((count+1)); echo "$count" > "$count_file"
  if [ $((count % CLEANLOOP_REMIND_EVERY)) -eq 0 ]; then
    emit "[cleanloop] Promemoria: contesto al ${pct}%, checkpoint ancora pendente. Chiudi il sotto-task, aggiorna $progress e termina." \
         "cleanloop: contesto ${pct}% — checkpoint pendente"
  fi
fi
exit 0
