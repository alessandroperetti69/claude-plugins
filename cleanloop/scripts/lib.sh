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
  : "${CLEANLOOP_LOG_FILE:=LOOPLOG.md}"      # log leggibile: una riga per uscita/ripartenza
  export CLEANLOOP_THRESHOLD CLEANLOOP_HARD CLEANLOOP_REMIND_EVERY CLEANLOOP_MAX_ITER \
         CLEANLOOP_STALL_LIMIT CLEANLOOP_PERMISSION_MODE CLEANLOOP_MODEL CLEANLOOP_MAX_BUDGET_USD \
         CLEANLOOP_CONTEXT_WINDOW CLEANLOOP_PROGRESS_FILE CLEANLOOP_TASK_FILE CLEANLOOP_LOG_FILE
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

# LOOPLOG.md: tabella leggibile.
# cleanloop_looplog cwd "n" "pct" "used" "window" "motivo" "status" ["modello" "token_in" "token_out" "costo_usd"]
cleanloop_looplog() {
  local cwd="$1" n="$2" pct="$3" used="$4" window="$5" reason="$6" status="$7" model="${8:--}" tin="${9:-}" tout="${10:-}" cost="${11:-}" f tok
  f="$cwd/$CLEANLOOP_LOG_FILE"
  [ -f "$f" ] || printf '# LOOPLOG\n\nUna riga per ogni uscita di iterazione o ripartenza di sessione: modello, occupazione della finestra di contesto all%suscita, token consumati nell%siterazione (in = input+cache, out = output) e costo API equivalente (con abbonamento non è addebitato).\n\n| # | Ora | Modello | Contesto all%suscita | Token iterazione | Costo API eq. | Motivo | STATUS |\n|---|---|---|---|---|---|---|---|\n' "'" "'" "'" > "$f"
  [ -z "$n" ] && return 0   # solo intestazione
  if [ -n "$tin" ]; then tok="$(cleanloop_short_num "$tin") in / $(cleanloop_short_num "$tout") out"; else tok="-"; fi
  [ -n "$cost" ] && cost=$(LC_ALL=C awk -v c="$cost" 'BEGIN{printf "$%.2f", c}') || cost="-"
  printf '| %s | %s | %s | %s%% (%s / %s) | %s | %s | %s | %s |\n' "$n" "$(date +%H:%M:%S)" "$model" "$pct" "$(cleanloop_fmt_num "$used")" "$(cleanloop_fmt_num "$window")" "$tok" "$cost" "$reason" "$status" >> "$f"
}
cleanloop_short_num() { awk -v n="${1:-0}" 'BEGIN{ if (n>=1000000) printf "%.1fM", n/1000000; else if (n>=1000) printf "%.0fk", n/1000; else printf "%d", n }'; }
cleanloop_fmt_num() { awk -v n="$1" 'BEGIN{ s=n; out=""; while (length(s)>3) { out=" " substr(s,length(s)-2) out; s=substr(s,1,length(s)-3) } print s out }'; }
cleanloop_status_of() { grep -Em1 '^STATUS:' "$1/$CLEANLOOP_PROGRESS_FILE" 2>/dev/null | sed -E 's/^STATUS:[[:space:]]*//; s/[[:space:]]*#.*//' | tr -d '\r'; }

cleanloop_checksum() { [ -f "$1" ] && (md5 -q "$1" 2>/dev/null || md5sum "$1" | cut -d' ' -f1) || echo none; }
