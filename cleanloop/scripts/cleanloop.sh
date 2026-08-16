#!/usr/bin/env bash
# cleanloop — runner del loop a sessioni fresche.
#
#   cleanloop.sh init  [--task "testo"]   crea TASK.md, PROGRESS.md, .cleanloop/ (senza --task: wizard interattivo)
#   cleanloop.sh add   ["testo"]          accoda un task a TASK.md (senza argomento: uno per riga, invio vuoto per finire)
#   cleanloop.sh tasks                    elenca la coda dei task con lo stato
#   cleanloop.sh run   [-n MAX_ITER]      esegue il loop finché STATUS: DONE/BLOCKED, max iter o stallo
#   cleanloop.sh once                     una sola iterazione
#   cleanloop.sh status                   stato corrente (STATUS, iterazione, ultimo % contesto, ultimi eventi)
#   cleanloop.sh log   [-n N]             log eventi dettagliato (.cleanloop/logs/events.log); il log leggibile è LOOPLOG.md
#   cleanloop.sh reset                    azzera stato hook (non tocca PROGRESS.md)
#   cleanloop.sh disable                  disattiva gli hook nel progetto (rimuove .cleanloop/enabled)
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CWD="$PWD"
cleanloop_load_config "$CWD"

usage() { sed -n '2,13p' "$0"; exit 1; }
say() { printf '\033[36m[cleanloop]\033[0m %s\n' "$*"; }
die() { printf '\033[31m[cleanloop]\033[0m %s\n' "$*" >&2; exit "${2:-1}"; }

need_claude() { command -v claude >/dev/null || die "claude CLI non trovato nel PATH"; }
need_jq() { command -v jq >/dev/null || die "jq non trovato (brew install jq)"; }

status_of() { grep -Em1 '^STATUS:' "$CWD/$CLEANLOOP_PROGRESS_FILE" 2>/dev/null | sed -E 's/^STATUS:[[:space:]]*//; s/[[:space:]]*#.*//' | tr -d '\r'; }
iter_of()   { grep -Em1 '^ITERATION:' "$CWD/$CLEANLOOP_PROGRESS_FILE" 2>/dev/null | sed -E 's/^ITERATION:[[:space:]]*//' | tr -d '\r'; }
checksum()  { cleanloop_checksum "$1"; }


# ---- creazione file -------------------------------------------------------
# Un task può essere multiriga: prima riga dopo "- [ ] Tn: ", righe successive indentate di 6 spazi.
format_task() {  # $1=id  $2=testo (anche con \n)
  local id="$1" text="$2" first rest
  first=${text%%$'\n'*}; rest=${text#*$'\n'}
  printf -- '- [ ] T%s: %s\n' "$id" "$first"
  [ "$rest" != "$text" ] && printf '%s\n' "$rest" | sed '/^[[:space:]]*$/d; s/^/      /'
  return 0
}

# Legge un blocco multiriga da stdin: riga vuota chiude il blocco; "." da sola o EOF chiude l'elenco.
# Ritorna 0 con il blocco in $BLOCK, 1 se l'elenco è finito. $1 = prompt della prima riga.
read_block() {
  BLOCK=""; local line first=1
  while true; do
    if [ $first = 1 ]; then read -r -p "$1" line || { [ -n "$BLOCK" ] && return 0 || return 1; }
    else read -r -p "      " line || return 0; fi
    if [ $first = 1 ] && [ "$line" = "." ]; then return 1; fi
    if [ -z "$line" ]; then [ $first = 1 ] && continue || return 0; fi
    BLOCK+="${BLOCK:+$'\n'}$line"; first=0
  done
}

# write_task_file "obiettivo"  — usa gli array WIZ_TASKS e WIZ_CONSTRAINTS
write_task_file() {
  local goal="$1" f="$CWD/$CLEANLOOP_TASK_FILE" n=0 t c
  {
    printf '# TASK\n\n## Obiettivo\n%s\n\n## Task (coda: aggiungi con `cleanloop add`)\n' "$goal"
    if [ ${#WIZ_TASKS[@]} -gt 0 ]; then for t in "${WIZ_TASKS[@]}"; do n=$((n+1)); format_task "$n" "$t"; done
    else printf -- '- [ ] T1: ...\n'; fi
    printf '\n## Vincoli\n'
    if [ ${#WIZ_CONSTRAINTS[@]} -gt 0 ]; then for c in "${WIZ_CONSTRAINTS[@]}"; do printf -- '- %s\n' "${c//$'\n'/ }"; done; else printf -- '- (nessuno)\n'; fi
    printf '\n## Definizione di fatto\n- [ ] Tutti i task della coda sono completati e verificati (comando/test indicato in PROGRESS.md)\n'
  } > "$f"
}

write_progress_file() {
  local f="$CWD/$CLEANLOOP_PROGRESS_FILE" goal plan
  goal=$(awk '/^## Obiettivo/{g=1;next} /^## /{g=0} g && NF{print; exit}' "$CWD/$CLEANLOOP_TASK_FILE" 2>/dev/null)
  plan=$(task_lines | sed 's/^/- [ ] /')
  {
    printf '# PROGRESS\n\nSTATUS: IN_PROGRESS\nITERATION: 0\n\n## Obiettivo (1 riga)\n%s\n\n## Fatto\n- (vuoto)\n\n## In corso\n- (vuoto)\n\n## Prossimo passo (handoff)\n- Leggi TASK.md (i task possono avere dettagli su più righe); se il Piano qui sotto e la coda in TASK.md non coincidono, allineali. Poi inizia dal primo task non spuntato: esplora solo i file necessari, spezzalo se non sta in una iterazione.\n\n## Piano (sotto-task, spuntare)\n%s\n\n## Decisioni\n- (vuoto)\n\n## Trappole / note\n- (vuoto)\n\n## Verifica (come si controlla che funziona)\n- comando: `...`\n' \
      "${goal:-<cosa deve essere vero alla fine>}" "${plan:-- [ ] ...}"
  } > "$f"
}

# prime righe "Tn: testo" dei task in TASK.md (le continuazioni indentate sono escluse)
task_lines() { awk '/^## Definizione/{exit} /^- \[[ xX]\] /{print}' "$CWD/$CLEANLOOP_TASK_FILE" 2>/dev/null | sed -E 's/^- \[[ xX]\] //'; }
next_task_id() { local n; n=$(grep -Eo '^- \[[ xX]\] T[0-9]+:' "$CWD/$CLEANLOOP_TASK_FILE" 2>/dev/null | grep -Eo '[0-9]+' | sort -n | tail -1); echo $(( ${n:-0} + 1 )); }

WIZ_TASKS=(); WIZ_CONSTRAINTS=()
wizard() {
  local goal
  printf '\n\033[1mcleanloop — nuovo task\033[0m  (Ctrl-C per annullare)\n\n'
  read -r -p "Obiettivo (1 riga): " goal
  printf '\nTask in ordine di esecuzione. Ogni task può occupare più righe (incolla pure):\n  riga vuota = task successivo · "." da sola = fine elenco\n'
  while read_block "  T$(( ${#WIZ_TASKS[@]} + 1 ))> "; do WIZ_TASKS+=("$BLOCK"); done
  printf '\nVincoli (cosa non toccare, stile, ...): riga vuota = prossimo · "." = fine\n'
  while read_block "  - "; do WIZ_CONSTRAINTS+=("$BLOCK"); done
  write_task_file "$goal"
  say "creato $CLEANLOOP_TASK_FILE con ${#WIZ_TASKS[@]} task"
}

cmd_add() {
  [ -f "$CWD/$CLEANLOOP_TASK_FILE" ] || die "manca $CLEANLOOP_TASK_FILE: esegui prima '$(basename "$0") init'"
  add_one() {
    local id blockfile; id=$(next_task_id); blockfile=$(mktemp)
    format_task "$id" "$1" > "$blockfile"
    # inserisce prima della prima riga vuota che segue la sezione "## Task"
    awk -v bf="$blockfile" '
      function dump(  l){ while ((getline l < bf) > 0) print l; close(bf) }
      /^## Task/ {intask=1}
      intask && /^## / && !/^## Task/ {intask=0}
      intask && done==0 && /^$/ {dump(); done=1}
      {print}
      END {if(!done) dump()}' "$CWD/$CLEANLOOP_TASK_FILE" > "$CWD/$CLEANLOOP_TASK_FILE.tmp" && mv "$CWD/$CLEANLOOP_TASK_FILE.tmp" "$CWD/$CLEANLOOP_TASK_FILE"
    rm -f "$blockfile"
    say "accodato T$id: ${1%%$'\n'*}"
  }
  if [ $# -gt 0 ]; then add_one "$*"; return; fi
  [ -t 0 ] || die "nessun task passato e stdin non è un terminale"
  printf 'Accoda task. Ogni task può occupare più righe: riga vuota = task successivo · "." da sola = fine\n'
  while read_block "  T$(next_task_id)> "; do add_one "$BLOCK"; done
}

cmd_tasks() {
  [ -f "$CWD/$CLEANLOOP_TASK_FILE" ] || die "manca $CLEANLOOP_TASK_FILE"
  echo "coda in $CLEANLOOP_TASK_FILE  (STATUS: $(status_of || echo '?'), ITERATION: $(iter_of || echo '?'))"
  awk '/^## Definizione/{exit}
       /^- \[[ xX]\] /{ if (cur!="") print cur "\t" extra; cur=$0; extra=0; next }
       cur!="" && /^      /{ extra++ }
       END{ if (cur!="") print cur "\t" extra }' "$CWD/$CLEANLOOP_TASK_FILE" | while IFS=$'\t' read -r l extra; do
    id=$(printf '%s' "$l" | grep -Eo 'T[0-9]+' | head -1)
    if printf '%s' "$l" | grep -Eq '^- \[[xX]\]'; then mark="✔"
    elif [ -n "$id" ] && grep -Eq "^- \[[xX]\] .*${id}([^0-9]|$)" "$CWD/$CLEANLOOP_PROGRESS_FILE" 2>/dev/null; then mark="✔"
    else mark=" "; fi
    suffix=""; [ "${extra:-0}" -gt 0 ] && suffix="  (+$extra righe)"
    printf '  %s %s%s\n' "$mark" "$(printf '%s' "$l" | sed -E 's/^- \[[ xX]\] //')" "$suffix"
  done
}

cmd_init() {
  need_jq
  local task_text=""
  while [ $# -gt 0 ]; do case "$1" in --task) task_text="$2"; shift 2;; *) shift;; esac; done
  mkdir -p "$CWD/.cleanloop/state" "$CWD/.cleanloop/logs"
  touch "$CWD/.cleanloop/enabled"
  if [ ! -f "$CWD/.cleanloop/config" ]; then
    cat > "$CWD/.cleanloop/config" <<CFG
# cleanloop — config del progetto (le variabili d'ambiente hanno la precedenza)
export CLEANLOOP_THRESHOLD="\${CLEANLOOP_THRESHOLD:-25}"       # % contesto -> checkpoint
export CLEANLOOP_HARD="\${CLEANLOOP_HARD:-40}"                 # % contesto -> chiusura forzata
export CLEANLOOP_MAX_ITER="\${CLEANLOOP_MAX_ITER:-20}"
export CLEANLOOP_STALL_LIMIT="\${CLEANLOOP_STALL_LIMIT:-3}"
export CLEANLOOP_PERMISSION_MODE="\${CLEANLOOP_PERMISSION_MODE:-auto}"   # auto|acceptEdits|bypassPermissions
export CLEANLOOP_MODEL="\${CLEANLOOP_MODEL:-}"                 # vuoto = default
export CLEANLOOP_MAX_BUDGET_USD="\${CLEANLOOP_MAX_BUDGET_USD:-}" # per iterazione, vuoto = nessun limite
export CLEANLOOP_CONTEXT_WINDOW="\${CLEANLOOP_CONTEXT_WINDOW:-}" # vuoto = autodetect (200k, o 1M se il modello è [1m])
export CLEANLOOP_LOG_FILE="\${CLEANLOOP_LOG_FILE:-LOOPLOG.md}"      # log leggibile delle uscite/ripartenze
CFG
    say "creato .cleanloop/config"
  fi
  if [ ! -f "$CWD/$CLEANLOOP_TASK_FILE" ]; then
    if [ -n "$task_text" ]; then
      WIZ_TASKS=("$task_text"); write_task_file "$task_text"; say "creato $CLEANLOOP_TASK_FILE (T1 = task indicato; aggiungi altri con '$(basename "$0") add')"
    elif [ -t 0 ]; then
      wizard
    else
      cp "$CLEANLOOP_ROOT/templates/TASK.md" "$CWD/$CLEANLOOP_TASK_FILE"; say "creato $CLEANLOOP_TASK_FILE — compilalo prima di 'run'"
    fi
  fi
  if [ ! -f "$CWD/$CLEANLOOP_PROGRESS_FILE" ]; then
    write_progress_file; say "creato $CLEANLOOP_PROGRESS_FILE"
  fi
  if [ ! -f "$CWD/$CLEANLOOP_LOG_FILE" ]; then
    cleanloop_looplog "$CWD" "" 0 0 0 "" ""; say "creato $CLEANLOOP_LOG_FILE"
  fi
  if [ -d "$CWD/.git" ] && ! grep -qs '^\.cleanloop/state' "$CWD/.gitignore" 2>/dev/null; then
    printf '.cleanloop/state/\n.cleanloop/logs/\n' >> "$CWD/.gitignore"; say "aggiunto .cleanloop/state|logs a .gitignore"
  fi
  say "pronto. Prossimo: compila $CLEANLOOP_TASK_FILE, poi: $(basename "$0") run"
}

run_iteration() {  # $1 = numero iterazione
  local i="$1" log="$CWD/.cleanloop/logs/iter-$(printf '%03d' "$i")-$(date +%Y%m%d-%H%M%S).log"
  local window autocompact args=()
  window=$(cleanloop_context_window)
  # rete di sicurezza: auto-compact ben oltre la soglia dura, nel range accettato (100k-1M)
  autocompact=$(awk -v w="$window" -v h="$CLEANLOOP_HARD" 'BEGIN{ a=int(w*(h+25)/100); if(a<100000)a=100000; if(a>1000000)a=1000000; print a }')
  args=( -p --plugin-dir "$CLEANLOOP_ROOT"
         --permission-mode "$CLEANLOOP_PERMISSION_MODE"
         --autocompact "$autocompact"
         --append-system-prompt-file "$CLEANLOOP_ROOT/prompts/iteration-system.md"
         --name "cleanloop-$i" )
  [ -n "$CLEANLOOP_MODEL" ] && args+=( --model "$CLEANLOOP_MODEL" )
  [ -n "$CLEANLOOP_MAX_BUDGET_USD" ] && args+=( --max-budget-usd "$CLEANLOOP_MAX_BUDGET_USD" )
  local prompt="Iterazione $i/$CLEANLOOP_MAX_ITER di cleanloop. Il task è in $CLEANLOOP_TASK_FILE, lo stato in $CLEANLOOP_PROGRESS_FILE (entrambi già iniettati nel contesto). Riparti dal 'Prossimo passo (handoff)', completa e verifica UN sotto-task, aggiorna $CLEANLOOP_PROGRESS_FILE, termina."
  say "iterazione $i/$CLEANLOOP_MAX_ITER — log: ${log#$CWD/}"
  cleanloop_log "$CWD" "event=iter_start iter=$i model=${CLEANLOOP_MODEL:-default} threshold=${CLEANLOOP_THRESHOLD}% hard=${CLEANLOOP_HARD}%"
  local t0=$SECONDS
  CLEANLOOP_ACTIVE=1 CLEANLOOP_ITER="$i" CLEANLOOP_ROOT="$CLEANLOOP_ROOT" \
    claude "${args[@]}" "$prompt" 2>&1 | tee "$log"
  local rc="${PIPESTATUS[0]}" pct used win sess lvl reason
  read -r pct used win sess <<< "$(cleanloop_last_ctx "$CWD")"
  lvl=$(cat "$CWD/.cleanloop/state/$sess.level" 2>/dev/null || echo 0)
  case "$lvl" in 2) reason=hard_threshold ;; 1) reason=soft_threshold ;; *) reason=natural_end ;; esac
  local reason_it; case "$reason" in hard_threshold) reason_it="soglia dura (${CLEANLOOP_HARD}%)";; soft_threshold) reason_it="soglia (${CLEANLOOP_THRESHOLD}%)";; *) reason_it="fine naturale";; esac
  [ "$rc" -ne 0 ] && reason_it="$reason_it, exit $rc"
  cleanloop_looplog "$CWD" "$i" "$pct" "$used" "$win" "$reason_it" "$(status_of)"
  ITER_END_LINE="event=iter_end iter=$i exit=$rc dur=$((SECONDS-t0))s ctx=${pct}% used=$used window=$win reason=$reason session=$sess"
  return "$rc"
}

cmd_run() {
  need_claude; need_jq
  local max="$CLEANLOOP_MAX_ITER"
  while [ $# -gt 0 ]; do case "$1" in -n) max="$2"; shift 2;; *) shift;; esac; done
  CLEANLOOP_MAX_ITER="$max"
  [ -f "$CWD/.cleanloop/enabled" ] || die "progetto non inizializzato: esegui '$(basename "$0") init'"
  [ -f "$CWD/$CLEANLOOP_TASK_FILE" ] || die "manca $CLEANLOOP_TASK_FILE"
  [ -f "$CWD/$CLEANLOOP_PROGRESS_FILE" ] || die "manca $CLEANLOOP_PROGRESS_FILE"
  [ "$CLEANLOOP_PERMISSION_MODE" = "bypassPermissions" ] && say "ATTENZIONE: bypassPermissions attivo — usalo solo in sandbox"

  local stall=0 i start_iter
  start_iter=$(( $(iter_of 2>/dev/null | grep -E '^[0-9]+$' || echo 0) + 1 ))
  cleanloop_log "$CWD" "event=loop_start start_iter=$start_iter max_iter=$max window=$(cleanloop_context_window)"
  for (( i=start_iter; i<start_iter+max; i++ )); do
    case "$(status_of)" in
      DONE)    cleanloop_log "$CWD" "event=loop_stop reason=done iters=$((i-start_iter))"; say "STATUS: DONE — task completato in $((i-1)) iterazioni"; return 0 ;;
      BLOCKED) cleanloop_log "$CWD" "event=loop_stop reason=blocked iters=$((i-start_iter))"; say "STATUS: BLOCKED — serve intervento umano (vedi $CLEANLOOP_PROGRESS_FILE)"; return 3 ;;
    esac
    local before after
    before=$(checksum "$CWD/$CLEANLOOP_PROGRESS_FILE")
    run_iteration "$i"; local rc=$?
    after=$(checksum "$CWD/$CLEANLOOP_PROGRESS_FILE")
    [ $rc -ne 0 ] && say "claude è uscito con codice $rc"
    if [ "$before" = "$after" ]; then
      stall=$((stall+1)); cleanloop_log "$CWD" "$ITER_END_LINE progress=unchanged status=$(status_of) stall=$stall"
      say "nessuna modifica a $CLEANLOOP_PROGRESS_FILE ($stall/$CLEANLOOP_STALL_LIMIT)"
      [ $stall -ge "$CLEANLOOP_STALL_LIMIT" ] && { cleanloop_log "$CWD" "event=loop_stop reason=stall iters=$((i-start_iter+1))"; die "stallo: $CLEANLOOP_STALL_LIMIT iterazioni senza progresso" 2; }
    else stall=0; cleanloop_log "$CWD" "$ITER_END_LINE progress=changed status=$(status_of)"; fi
  done
  case "$(status_of)" in
    DONE) cleanloop_log "$CWD" "event=loop_stop reason=done iters=$max"; say "STATUS: DONE"; return 0 ;;
    *) cleanloop_log "$CWD" "event=loop_stop reason=max_iter iters=$max"; say "raggiunto il massimo di $max iterazioni — STATUS: $(status_of)"; return 4 ;;
  esac
}

cmd_status() {
  echo "progetto:   $CWD"
  echo "attivo:     $([ -f "$CWD/.cleanloop/enabled" ] && echo sì || echo no)"
  echo "STATUS:     $(status_of || echo '?')    ITERATION: $(iter_of || echo '?')"
  echo "soglie:     ${CLEANLOOP_THRESHOLD}% / ${CLEANLOOP_HARD}%   finestra: $(cleanloop_context_window) token"
  if [ -f "$CWD/.cleanloop/state/last.json" ]; then
    echo "ultimo ctx: $(jq -r '"\(.pct)% (\(.used)/\(.window)) alle \(.ts)"' "$CWD/.cleanloop/state/last.json")"
  fi
  ls "$CWD/.cleanloop/logs" 2>/dev/null | grep '^iter-' | tail -3 | sed 's/^/log:        /'
  if [ -f "$CWD/$CLEANLOOP_LOG_FILE" ]; then echo "$CLEANLOOP_LOG_FILE (ultime 3 righe):"; grep '^|' "$CWD/$CLEANLOOP_LOG_FILE" | tail -3 | sed 's/^/  /'; fi
  if [ -f "$CWD/.cleanloop/logs/events.log" ]; then echo "eventi (ultimi 5, 'cleanloop log' per tutti):"; tail -5 "$CWD/.cleanloop/logs/events.log" | sed 's/^/  /'; fi
}

cmd_log() {
  local n=""; while [ $# -gt 0 ]; do case "$1" in -n) n="$2"; shift 2;; *) shift;; esac; done
  local f="$CWD/.cleanloop/logs/events.log"
  [ -f "$f" ] || die "nessun log eventi in $f"
  if [ -n "$n" ]; then tail -n "$n" "$f"; else cat "$f"; fi
}

case "${1:-}" in
  init)    shift; cmd_init "$@" ;;
  add)     shift; cmd_add "$@" ;;
  tasks)   cmd_tasks ;;
  run)     shift; cmd_run "$@" ;;
  once)    shift; cmd_run -n 1 ;;
  status)  cmd_status ;;
  log)     shift; cmd_log "$@" ;;
  reset)   rm -rf "$CWD/.cleanloop/state"; say "stato azzerato" ;;
  disable) rm -f "$CWD/.cleanloop/enabled"; say "hook disattivati in questo progetto" ;;
  *) usage ;;
esac
