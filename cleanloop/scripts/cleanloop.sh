#!/usr/bin/env bash
# cleanloop — runner del loop a sessioni fresche.
#
#   cleanloop.sh init  [--task "testo"]   crea TASK.md, PROGRESS.md, .cleanloop/ (senza --task: wizard interattivo)
#   cleanloop.sh add   ["testo"]          accoda un task a TASK.md (senza argomento: uno per riga, invio vuoto per finire)
#   cleanloop.sh tasks                    elenca la coda dei task con lo stato
#   cleanloop.sh run   [-n MAX_ITER]      esegue il loop finché STATUS: DONE/BLOCKED, max iter o stallo
#   cleanloop.sh once                     una sola iterazione
#   cleanloop.sh status                   stato corrente (STATUS, iterazione, ultimo % contesto)
#   cleanloop.sh reset                    azzera stato hook (non tocca PROGRESS.md)
#   cleanloop.sh disable                  disattiva gli hook nel progetto (rimuove .cleanloop/enabled)
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CWD="$PWD"
cleanloop_load_config "$CWD"

usage() { sed -n '2,12p' "$0"; exit 1; }
say() { printf '\033[36m[cleanloop]\033[0m %s\n' "$*"; }
die() { printf '\033[31m[cleanloop]\033[0m %s\n' "$*" >&2; exit "${2:-1}"; }

need_claude() { command -v claude >/dev/null || die "claude CLI non trovato nel PATH"; }
need_jq() { command -v jq >/dev/null || die "jq non trovato (brew install jq)"; }

status_of() { grep -Em1 '^STATUS:' "$CWD/$CLEANLOOP_PROGRESS_FILE" 2>/dev/null | sed -E 's/^STATUS:[[:space:]]*//; s/[[:space:]]*#.*//' | tr -d '\r'; }
iter_of()   { grep -Em1 '^ITERATION:' "$CWD/$CLEANLOOP_PROGRESS_FILE" 2>/dev/null | sed -E 's/^ITERATION:[[:space:]]*//' | tr -d '\r'; }
checksum()  { cleanloop_checksum "$1"; }


# ---- creazione file -------------------------------------------------------
# write_task_file "obiettivo" "task1\ntask2..." "vincolo1\n..."
write_task_file() {
  local goal="$1" tasks="$2" constraints="$3" f="$CWD/$CLEANLOOP_TASK_FILE"
  {
    printf '# TASK\n\n## Obiettivo\n%s\n\n## Task (coda: aggiungi con `cleanloop add`)\n' "$goal"
    if [ -n "$tasks" ]; then local n=0; while IFS= read -r t; do [ -z "$t" ] && continue; n=$((n+1)); printf -- '- [ ] T%d: %s\n' "$n" "$t"; done <<< "$tasks"
    else printf -- '- [ ] T1: ...\n'; fi
    printf '\n## Vincoli\n'
    if [ -n "$constraints" ]; then while IFS= read -r c; do [ -z "$c" ] && continue; printf -- '- %s\n' "$c"; done <<< "$constraints"; else printf -- '- (nessuno)\n'; fi
    printf '\n## Definizione di fatto\n- [ ] Tutti i task della coda sono completati e verificati (comando/test indicato in PROGRESS.md)\n'
  } > "$f"
}

write_progress_file() {
  local f="$CWD/$CLEANLOOP_PROGRESS_FILE" goal plan
  goal=$(awk '/^## Obiettivo/{g=1;next} /^## /{g=0} g && NF{print; exit}' "$CWD/$CLEANLOOP_TASK_FILE" 2>/dev/null)
  plan=$(task_lines | sed 's/^/- [ ] /')
  {
    printf '# PROGRESS\n\nSTATUS: IN_PROGRESS\nITERATION: 0\n\n## Obiettivo (1 riga)\n%s\n\n## Fatto\n- (vuoto)\n\n## In corso\n- (vuoto)\n\n## Prossimo passo (handoff)\n- Leggi TASK.md; se il Piano qui sotto e la coda in TASK.md non coincidono, allineali. Poi inizia dal primo task non spuntato: esplora solo i file necessari, spezzalo se non sta in una iterazione.\n\n## Piano (sotto-task, spuntare)\n%s\n\n## Decisioni\n- (vuoto)\n\n## Trappole / note\n- (vuoto)\n\n## Verifica (come si controlla che funziona)\n- comando: `...`\n' \
      "${goal:-<cosa deve essere vero alla fine>}" "${plan:-- [ ] ...}"
  } > "$f"
}

# righe "Tn: testo" dei task in TASK.md (spuntati o no)
task_lines() { awk '/^## Definizione/{exit} /^- \[[ xX]\] /{print}' "$CWD/$CLEANLOOP_TASK_FILE" 2>/dev/null | sed -E 's/^- \[[ xX]\] //'; }
next_task_id() { local n; n=$(grep -Eo '^- \[[ xX]\] T[0-9]+:' "$CWD/$CLEANLOOP_TASK_FILE" 2>/dev/null | grep -Eo '[0-9]+' | sort -n | tail -1); echo $(( ${n:-0} + 1 )); }

wizard() {
  local goal tasks="" constraints="" line
  printf '\n\033[1mcleanloop — nuovo task\033[0m  (Ctrl-C per annullare)\n\n'
  read -r -p "Obiettivo (1 riga): " goal
  printf '\nTask da eseguire in ordine, uno per riga. Invio su riga vuota per finire.\n'
  local n=1
  while true; do
    read -r -p "  T$n> " line || break
    [ -z "$line" ] && break
    tasks+="$line"$'\n'; n=$((n+1))
  done
  printf '\nVincoli (cosa non toccare, stile, ...), uno per riga. Invio su riga vuota per finire.\n'
  while true; do
    read -r -p "  - " line || break
    [ -z "$line" ] && break
    constraints+="$line"$'\n'
  done
  write_task_file "$goal" "$tasks" "$constraints"
  say "creato $CLEANLOOP_TASK_FILE con $((n-1)) task"
}

cmd_add() {
  [ -f "$CWD/$CLEANLOOP_TASK_FILE" ] || die "manca $CLEANLOOP_TASK_FILE: esegui prima '$(basename "$0") init'"
  add_one() {
    local id; id=$(next_task_id)
    # inserisce prima della prima riga vuota che segue la sezione "## Task"
    awk -v line="- [ ] T$id: $1" '
      /^## Task/ {intask=1}
      intask && /^## / && !/^## Task/ {intask=0}
      intask && done==0 && /^$/ {print line; done=1}
      {print}
      END {if(!done) print line}' "$CWD/$CLEANLOOP_TASK_FILE" > "$CWD/$CLEANLOOP_TASK_FILE.tmp" && mv "$CWD/$CLEANLOOP_TASK_FILE.tmp" "$CWD/$CLEANLOOP_TASK_FILE"
    say "accodato T$id: $1"
  }
  if [ $# -gt 0 ]; then add_one "$*"; return; fi
  [ -t 0 ] || die "nessun task passato e stdin non è un terminale"
  printf 'Accoda task, uno per riga. Invio su riga vuota per finire.\n'
  local line
  while true; do
    read -r -p "  T$(next_task_id)> " line || break
    [ -z "$line" ] && break
    add_one "$line"
  done
}

cmd_tasks() {
  [ -f "$CWD/$CLEANLOOP_TASK_FILE" ] || die "manca $CLEANLOOP_TASK_FILE"
  echo "coda in $CLEANLOOP_TASK_FILE  (STATUS: $(status_of || echo '?'), ITERATION: $(iter_of || echo '?'))"
  awk '/^## Definizione/{exit} /^- \[[ xX]\] /{print}' "$CWD/$CLEANLOOP_TASK_FILE" | while IFS= read -r l; do
    id=$(printf '%s' "$l" | grep -Eo 'T[0-9]+' | head -1)
    if printf '%s' "$l" | grep -Eq '^- \[[xX]\]'; then mark="✔"
    elif [ -n "$id" ] && grep -Eq "^- \[[xX]\] .*${id}([^0-9]|$)" "$CWD/$CLEANLOOP_PROGRESS_FILE" 2>/dev/null; then mark="✔"
    else mark=" "; fi
    printf '  %s %s\n' "$mark" "$(printf '%s' "$l" | sed -E 's/^- \[[ xX]\] //')"
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
CFG
    say "creato .cleanloop/config"
  fi
  if [ ! -f "$CWD/$CLEANLOOP_TASK_FILE" ]; then
    if [ -n "$task_text" ]; then
      write_task_file "$task_text" "$task_text" ""; say "creato $CLEANLOOP_TASK_FILE (T1 = task indicato; aggiungi altri con '$(basename "$0") add')"
    elif [ -t 0 ]; then
      wizard
    else
      cp "$CLEANLOOP_ROOT/templates/TASK.md" "$CWD/$CLEANLOOP_TASK_FILE"; say "creato $CLEANLOOP_TASK_FILE — compilalo prima di 'run'"
    fi
  fi
  if [ ! -f "$CWD/$CLEANLOOP_PROGRESS_FILE" ]; then
    write_progress_file; say "creato $CLEANLOOP_PROGRESS_FILE"
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
  CLEANLOOP_ACTIVE=1 CLEANLOOP_ITER="$i" CLEANLOOP_ROOT="$CLEANLOOP_ROOT" \
    claude "${args[@]}" "$prompt" 2>&1 | tee "$log"
  return "${PIPESTATUS[0]}"
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
  for (( i=start_iter; i<start_iter+max; i++ )); do
    case "$(status_of)" in
      DONE)    say "STATUS: DONE — task completato in $((i-1)) iterazioni"; return 0 ;;
      BLOCKED) say "STATUS: BLOCKED — serve intervento umano (vedi $CLEANLOOP_PROGRESS_FILE)"; return 3 ;;
    esac
    local before after
    before=$(checksum "$CWD/$CLEANLOOP_PROGRESS_FILE")
    run_iteration "$i"; local rc=$?
    after=$(checksum "$CWD/$CLEANLOOP_PROGRESS_FILE")
    [ $rc -ne 0 ] && say "claude è uscito con codice $rc"
    if [ "$before" = "$after" ]; then
      stall=$((stall+1)); say "nessuna modifica a $CLEANLOOP_PROGRESS_FILE ($stall/$CLEANLOOP_STALL_LIMIT)"
      [ $stall -ge "$CLEANLOOP_STALL_LIMIT" ] && die "stallo: $CLEANLOOP_STALL_LIMIT iterazioni senza progresso" 2
    else stall=0; fi
  done
  case "$(status_of)" in
    DONE) say "STATUS: DONE"; return 0 ;;
    *) say "raggiunto il massimo di $max iterazioni — STATUS: $(status_of)"; return 4 ;;
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
  ls "$CWD/.cleanloop/logs" 2>/dev/null | tail -3 | sed 's/^/log:        /'
}

case "${1:-}" in
  init)    shift; cmd_init "$@" ;;
  add)     shift; cmd_add "$@" ;;
  tasks)   cmd_tasks ;;
  run)     shift; cmd_run "$@" ;;
  once)    shift; cmd_run -n 1 ;;
  status)  cmd_status ;;
  reset)   rm -rf "$CWD/.cleanloop/state"; say "stato azzerato" ;;
  disable) rm -f "$CWD/.cleanloop/enabled"; say "hook disattivati in questo progetto" ;;
  *) usage ;;
esac
