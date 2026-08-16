#!/usr/bin/env bash
# cleanloop - funzioni condivise. Sourced dagli hook e dal runner.

CLEANLOOP_ROOT="${CLEANLOOP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Carica config: default -> .cleanloop/config del progetto -> env (env vince perché
# il file di config usa il pattern ${VAR:-default}).
cleanloop_load_config() {
  local cwd="${1:-$PWD}"
  [ -f "$cwd/.cleanloop/config" ] && . "$cwd/.cleanloop/config"
  : "${CLEANLOOP_THRESHOLD:=25}"        # % contesto: chiedi checkpoint
  : "${CLEANLOOP_HARD:=40}"             # % contesto: chiudi subito
  : "${CLEANLOOP_REMIND_EVERY:=6}"      # tool call tra un promemoria e l'altro dopo la soglia
  : "${CLEANLOOP_MAX_ITER:=20}"         # iterazioni max del loop
  : "${CLEANLOOP_STALL_LIMIT:=3}"       # iterazioni senza modifiche a PROGRESS.md prima di fermarsi
  : "${CLEANLOOP_PERMISSION_MODE:=auto}"
  : "${CLEANLOOP_MODEL:=}"
  : "${CLEANLOOP_MAX_BUDGET_USD:=}"
  : "${CLEANLOOP_CONTEXT_WINDOW:=}"     # vuoto = autodetect
  : "${CLEANLOOP_PROGRESS_FILE:=PROGRESS.md}"
  : "${CLEANLOOP_TASK_FILE:=TASK.md}"
  export CLEANLOOP_THRESHOLD CLEANLOOP_HARD CLEANLOOP_REMIND_EVERY CLEANLOOP_MAX_ITER \
         CLEANLOOP_STALL_LIMIT CLEANLOOP_PERMISSION_MODE CLEANLOOP_MODEL CLEANLOOP_MAX_BUDGET_USD \
         CLEANLOOP_CONTEXT_WINDOW CLEANLOOP_PROGRESS_FILE CLEANLOOP_TASK_FILE
}

# cleanloop è attivo in questo progetto? (loop in corso, oppure init eseguito)
cleanloop_is_active() {
  local cwd="${1:-$PWD}"
  [ "${CLEANLOOP_ACTIVE:-0}" = "1" ] || [ -f "$cwd/.cleanloop/enabled" ]
}

# Dimensione della finestra di contesto in token.
cleanloop_context_window() {
  if [ -n "$CLEANLOOP_CONTEXT_WINDOW" ]; then echo "$CLEANLOOP_CONTEXT_WINDOW"; return; fi
  local model=""
  [ -f "$HOME/.claude/settings.json" ] && model=$(jq -r '.model // ""' "$HOME/.claude/settings.json" 2>/dev/null)
  case "$model" in
    *"[1m]"*|*1m*) echo 1000000 ;;
    *) echo 200000 ;;
  esac
}

# Token attualmente in contesto = usage dell'ultimo messaggio assistant nel transcript
# (input + cache_creation + cache_read). 0 se non determinabile.
cleanloop_used_tokens() {
  local transcript="$1"
  [ -f "$transcript" ] || { echo 0; return; }
  grep '"type":"assistant"' "$transcript" 2>/dev/null | tail -1 | jq -r '
    (.message.usage // {}) as $u |
    (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0))
  ' 2>/dev/null || echo 0
}

cleanloop_pct() {  # used window -> intero
  awk -v u="$1" -v w="$2" 'BEGIN{ if (w<=0) print 0; else printf "%d", (u*100/w)+0.5 }'
}

# Escape di una stringa per inserirla in JSON (usa jq).
cleanloop_json_str() { jq -Rs . ; }

cleanloop_state_dir() { local d="${1:-$PWD}/.cleanloop/state"; mkdir -p "$d"; echo "$d"; }

# Log eventi: una riga per evento in .cleanloop/logs/events.log
cleanloop_log() {  # $1=cwd  $2...=testo
  local cwd="$1"; shift
  mkdir -p "$cwd/.cleanloop/logs"
  printf '%s %s\n' "$(date +%FT%T)" "$*" >> "$cwd/.cleanloop/logs/events.log"
}
# Ultima misura del contesto: stampa "pct used window session" (o "0 0 0 -")
cleanloop_last_ctx() {
  local f="$1/.cleanloop/state/last.json"
  [ -f "$f" ] && jq -r '"\(.pct) \(.used) \(.window) \(.session)"' "$f" 2>/dev/null || echo "0 0 0 -"
}

cleanloop_checksum() { [ -f "$1" ] && (md5 -q "$1" 2>/dev/null || md5sum "$1" | cut -d' ' -f1) || echo none; }
