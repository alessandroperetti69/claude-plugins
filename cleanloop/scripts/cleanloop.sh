#!/usr/bin/env bash
# cleanloop — runner del loop a sessioni fresche.
#
#   cleanloop.sh init  [--task "testo" | --brief PATH|-]   crea TASK.md, PROGRESS.md, .cleanloop/
#     senza --task/--brief: wizard interattivo, salvo che esista già BRIEF.md in radice o arrivi
#     testo da stdin non interattivo (es. `pbpaste | cleanloop.sh init`) — in quel caso è brief-mode:
#     il contenuto va in BRIEF.md, TASK.md ha un solo T1 che chiede alla prima iterazione di leggerlo
#     e derivarne Obiettivo + coda reale, senza eseguire lavoro applicativo in quel turno.
#     --brief -   legge il brief da stdin esplicitamente (invece che da file)
#     opzioni di configurazione (scritte in .cleanloop/config; rilanciabili su un progetto già inizializzato
#     per aggiornarle):
#       --threshold N            % contesto -> checkpoint (default 25)
#       --hard N                 % contesto -> chiusura forzata (default 40)
#       --max-iter N             iterazioni max del loop (default 20)
#       --stall-limit N          iterazioni senza progresso prima di fermarsi (default 3)
#       --remind-every N         tool call tra un promemoria e l'altro dopo la soglia (default 6)
#       --permission-mode MODE   auto|acceptEdits|bypassPermissions (default auto)
#       --model NOME             modello per le iterazioni -p (vuoto = default)
#       --effort LIVELLO         low|medium|high|xhigh|max (vuoto = default di sessione)
#       --max-budget-usd N       limite di spesa per iterazione (vuoto = nessuno)
#       --context-window N       token finestra di contesto (vuoto = autodetect)
#       --progress-file FILE     nome del file di avanzamento (default PROGRESS.md)
#       --task-file FILE         nome del file dei task (default TASK.md)
#       --log-file FILE          nome del log leggibile (default LOOPLOG.md)
#       --use-subagents 0|1      1 = l'iterazione valuta il parallelismo con l'Agent tool sui task indipendenti (default 0)
#   cleanloop.sh add   ["testo"]          accoda un task a TASK.md (senza argomento: uno per riga, invio vuoto per finire)
#   cleanloop.sh tasks                    elenca la coda dei task con lo stato
#   cleanloop.sh run   [-n MAX_ITER] [opzioni di config]  esegue il loop finché STATUS: DONE/BLOCKED, max iter o stallo.
#     Le stesse opzioni di config elencate per init (--threshold, --model, --effort, --use-subagents, ecc., più
#     --max-iter come alias di -n) valgono qui come override SOLO per questa esecuzione, senza toccare
#     .cleanloop/config.
#   cleanloop.sh once  [opzioni di config]  una sola iterazione (= run -n 1, con le stesse opzioni di override)
#   cleanloop.sh status                   stato corrente (STATUS, iterazione, ultimo % contesto, ultimi eventi)
#   cleanloop.sh config [CHIAVE=VALORE ...]  senza argomenti: mostra .cleanloop/config; con argomenti: aggiorna le chiavi indicate
#   cleanloop.sh log   [-n N]             log eventi dettagliato (.cleanloop/logs/events.log); il log leggibile è LOOPLOG.md
#   cleanloop.sh reset                    azzera stato hook (non tocca PROGRESS.md)
#   cleanloop.sh disable                  disattiva gli hook nel progetto (rimuove .cleanloop/enabled)
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CWD="$PWD"
cleanloop_load_config "$CWD"

usage() { sed -n '2,37p' "$0"; exit 1; }
say() { printf '\033[36m[cleanloop]\033[0m %s\n' "$*"; }
die() { printf '\033[31m[cleanloop]\033[0m %s\n' "$*" >&2; exit "${2:-1}"; }

need_claude() { command -v claude >/dev/null || die "claude CLI non trovato nel PATH"; }
need_jq() { command -v jq >/dev/null || die "jq non trovato (brew install jq)"; }

status_of() { grep -Em1 '^STATUS:' "$CWD/$CLEANLOOP_PROGRESS_FILE" 2>/dev/null | sed -E 's/^STATUS:[[:space:]]*//; s/[[:space:]]*#.*//' | tr -d '\r'; }
iter_of()   { grep -Em1 '^ITERATION:' "$CWD/$CLEANLOOP_PROGRESS_FILE" 2>/dev/null | sed -E 's/^ITERATION:[[:space:]]*//' | tr -d '\r'; }
checksum()  { cleanloop_checksum "$1"; }

# ---- config del progetto (.cleanloop/config), letta/scritta da CLI -------
CFG_KEYS="THRESHOLD HARD MAX_ITER STALL_LIMIT REMIND_EVERY PERMISSION_MODE MODEL EFFORT MAX_BUDGET_USD CONTEXT_WINDOW PROGRESS_FILE TASK_FILE LOG_FILE USE_SUBAGENTS"

validate_cfg() {  # $1=CHIAVE (senza prefisso CLEANLOOP_)  $2=VALORE — die se non valido
  local key="$1" val="$2"
  case "$key" in
    THRESHOLD|HARD|MAX_ITER|STALL_LIMIT|REMIND_EVERY)
      [[ "$val" =~ ^[0-9]+$ ]] || die "$key deve essere un numero intero (ricevuto: '$val')" ;;
    PERMISSION_MODE)
      case "$val" in auto|acceptEdits|bypassPermissions) ;; *) die "PERMISSION_MODE deve essere auto|acceptEdits|bypassPermissions" ;; esac ;;
    MAX_BUDGET_USD)
      [ -z "$val" ] || [[ "$val" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "MAX_BUDGET_USD deve essere un numero (o vuoto per nessun limite)" ;;
    CONTEXT_WINDOW)
      [ -z "$val" ] || [[ "$val" =~ ^[0-9]+$ ]] || die "CONTEXT_WINDOW deve essere un numero di token (o vuoto per autodetect)" ;;
    MODEL) ;;  # libero, vuoto = default
    EFFORT)
      case "$val" in ""|low|medium|high|xhigh|max) ;; *) die "EFFORT deve essere low|medium|high|xhigh|max (o vuoto per il default)" ;; esac ;;
    PROGRESS_FILE|TASK_FILE|LOG_FILE)
      [ -n "$val" ] || die "$key non può essere vuoto" ;;
    USE_SUBAGENTS)
      case "$val" in 0|1) ;; *) die "USE_SUBAGENTS deve essere 0 o 1" ;; esac ;;
    *) die "chiave di config sconosciuta: $key (valide: $CFG_KEYS)" ;;
  esac
}

# Aggiorna (o aggiunge) la riga "export CLEANLOOP_<key>=..." in .cleanloop/config esistente.
set_cfg_var() {  # $1=CHIAVE (senza prefisso)  $2=VALORE
  local key="$1" val="$2" var="CLEANLOOP_$1" f="$CWD/.cleanloop/config" val_esc
  [ -f "$f" ] || return 1
  val_esc=$(printf '%s' "$val" | sed 's/[&@\]/\\&/g')
  if grep -q "^export ${var}=" "$f"; then
    sed -E "s@^(export ${var}=\"\\\$\\{${var}:-)[^}]*(\\}\")@\\1${val_esc}\\2@" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  else
    printf 'export %s="${%s:-%s}"\n' "$var" "$var" "$val" >> "$f"
  fi
}


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

write_progress_file() {  # $1 = handoff opzionale (sovrascrive il default)
  local f="$CWD/$CLEANLOOP_PROGRESS_FILE" goal plan handoff
  goal=$(awk '/^## Obiettivo/{g=1;next} /^## /{g=0} g && NF{print; exit}' "$CWD/$CLEANLOOP_TASK_FILE" 2>/dev/null)
  plan=$(task_lines | sed 's/^/- [ ] /')
  handoff="${1:-Leggi TASK.md (i task possono avere dettagli su più righe); se il Piano qui sotto e la coda in TASK.md non coincidono, allineali. Poi inizia dal primo task non spuntato: esplora solo i file necessari, spezzalo se non sta in una iterazione.}"
  {
    printf '# PROGRESS\n\nSTATUS: IN_PROGRESS\nITERATION: 0\n\n## Obiettivo (1 riga)\n%s\n\n## Fatto\n- (vuoto)\n\n## In corso\n- (vuoto)\n\n## Prossimo passo (handoff)\n- %s\n\n## Piano (sotto-task, spuntare)\n%s\n\n## Decisioni\n- (vuoto)\n\n## Trappole / note\n- (vuoto)\n\n## Verifica (come si controlla che funziona)\n- comando: `...`\n' \
      "${goal:-<cosa deve essere vero alla fine>}" "$handoff" "${plan:-- [ ] ...}"
  } > "$f"
}

# Legge il brief da file o stdin ('-') in $2; ritorna 1 se manca/è vuoto.
read_brief_into() {  # $1=sorgente ('-' = stdin, altrimenti path)  $2=destinazione
  local src="$1" dst="$2"
  if [ "$src" = "-" ]; then cat > "$dst"; else [ -f "$src" ] && cp "$src" "$dst"; fi
  [ -s "$dst" ]
}

# TASK.md "di pianificazione": un solo T1 che chiede alla prima iterazione di derivare
# Obiettivo + coda reale da BRIEF.md (già scritto in radice) prima di eseguire qualsiasi lavoro.
write_brief_task_file() {
  local f="$CWD/$CLEANLOOP_TASK_FILE"
  {
    printf '# TASK\n\n## Obiettivo\nDa definire: leggi BRIEF.md e derivalo (vedi T1 sotto)\n\n## Task (coda: aggiungi con `cleanloop add`)\n'
    printf -- '- [ ] T1: Leggi BRIEF.md (il brief fornito in fase di init) e usalo per riscrivere qui sotto la coda reale dei task (uno o più Tn, in ordine di esecuzione) e, sopra, un Obiettivo in 1-2 righe. Poi riscrivi anche la sezione "Definizione di fatto" con condizioni verificabili dedotte dal brief. In questa iterazione pianifica soltanto: non iniziare lavoro applicativo, chiudi il turno dopo aver riscritto TASK.md.\n'
    printf '\n## Vincoli\n- (nessuno esplicito — dedurli da BRIEF.md o lasciare vuoto)\n'
    printf '\n## Definizione di fatto\n- [ ] La coda di task in "## Task" è stata derivata da BRIEF.md e sostituisce T1\n- [ ] Tutti i task della coda sono completati e verificati (comando/test indicato in PROGRESS.md)\n'
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
  wizard_config
}

# ---- wizard dei parametri di configurazione (invio = mantieni il default mostrato) --------
ask_int() {  # $1=prompt  $2=default  -> stdout=valore intero valido
  local prompt="$1" def="$2" val
  while true; do
    read -r -p "$prompt [invio=$def]: " val; val="${val:-$def}"
    [[ "$val" =~ ^[0-9]+$ ]] && { printf '%s' "$val"; return; }
    printf '  valore non valido: serve un numero intero.\n' >&2
  done
}
ask_num_or_empty() {  # $1=prompt  $2=default (può essere vuoto)  $3=etichetta per il vuoto
  local prompt="$1" def="$2" label="$3" val
  while true; do
    read -r -p "$prompt [invio=${def:-$label}]: " val; val="${val:-$def}"
    { [ -z "$val" ] || [[ "$val" =~ ^[0-9]+([.][0-9]+)?$ ]]; } && { printf '%s' "$val"; return; }
    printf '  valore non valido: numero o vuoto.\n' >&2
  done
}
ask_text() {  # $1=prompt  $2=default  -> stdout=valore
  local prompt="$1" def="$2" val
  read -r -p "$prompt [invio=$def]: " val
  printf '%s' "${val:-$def}"
}

# Chiede i parametri del loop uno per uno (default = valore corrente, che riflette eventuali
# flag già passati a init) e li scrive subito in .cleanloop/config (già presente su disco a
# questo punto). TASK_FILE/PROGRESS_FILE non sono qui: se cambiati dopo che wizard() ha già
# scritto TASK.md andrebbero disallineati — restano configurabili solo da flag/`config`.
wizard_config() {
  printf '\n\033[1mParametri del loop\033[0m  (invio = mantieni il default mostrato)\n\n'
  local val

  printf 'Modello:\n  1) sonnet   2) opus   3) fable   4) haiku   5) altro (id completo)\n'
  read -r -p "Scelta [invio=${CLEANLOOP_MODEL:-predefinito utente}]: " val
  case "$val" in
    "") : ;;
    1) CLEANLOOP_MODEL=sonnet ;; 2) CLEANLOOP_MODEL=opus ;; 3) CLEANLOOP_MODEL=fable ;; 4) CLEANLOOP_MODEL=haiku ;;
    5) read -r -p "  Id modello: " CLEANLOOP_MODEL ;;
    *) CLEANLOOP_MODEL="$val" ;;
  esac
  set_cfg_var MODEL "$CLEANLOOP_MODEL"

  printf '\nEffort:\n  1) low   2) medium   3) high   4) xhigh   5) max\n'
  read -r -p "Scelta [invio=${CLEANLOOP_EFFORT:-predefinito sessione}]: " val
  case "$val" in
    "") : ;;
    1) CLEANLOOP_EFFORT=low ;; 2) CLEANLOOP_EFFORT=medium ;; 3) CLEANLOOP_EFFORT=high ;;
    4) CLEANLOOP_EFFORT=xhigh ;; 5) CLEANLOOP_EFFORT=max ;;
    *) CLEANLOOP_EFFORT="$val" ;;
  esac
  set_cfg_var EFFORT "$CLEANLOOP_EFFORT"

  printf '\nPermission mode:\n  1) auto (consigliato)   2) acceptEdits   3) bypassPermissions (solo sandbox)\n'
  read -r -p "Scelta [invio=$CLEANLOOP_PERMISSION_MODE]: " val
  case "$val" in
    "") : ;;
    1) CLEANLOOP_PERMISSION_MODE=auto ;; 2) CLEANLOOP_PERMISSION_MODE=acceptEdits ;; 3) CLEANLOOP_PERMISSION_MODE=bypassPermissions ;;
    *) CLEANLOOP_PERMISSION_MODE="$val" ;;
  esac
  set_cfg_var PERMISSION_MODE "$CLEANLOOP_PERMISSION_MODE"

  read -r -p "$(printf '\nValutare il parallelismo con sub-agenti sui task indipendenti? [s/N, invio=%s]: ' "$([ "$CLEANLOOP_USE_SUBAGENTS" = 1 ] && echo sì || echo no)")" val
  case "$val" in "") : ;; s|S|si|Si|SI|y|Y) CLEANLOOP_USE_SUBAGENTS=1 ;; *) CLEANLOOP_USE_SUBAGENTS=0 ;; esac
  set_cfg_var USE_SUBAGENTS "$CLEANLOOP_USE_SUBAGENTS"

  printf '\n'
  CLEANLOOP_THRESHOLD=$(ask_int "Soglia checkpoint (% contesto)" "$CLEANLOOP_THRESHOLD"); set_cfg_var THRESHOLD "$CLEANLOOP_THRESHOLD"; printf '\n'
  CLEANLOOP_HARD=$(ask_int "Soglia dura (% contesto)" "$CLEANLOOP_HARD"); set_cfg_var HARD "$CLEANLOOP_HARD"; printf '\n'
  CLEANLOOP_MAX_BUDGET_USD=$(ask_num_or_empty "Budget max per iterazione (USD)" "$CLEANLOOP_MAX_BUDGET_USD" "illimitato"); set_cfg_var MAX_BUDGET_USD "$CLEANLOOP_MAX_BUDGET_USD"; printf '\n'
  CLEANLOOP_MAX_ITER=$(ask_int "Iterazioni massime del loop" "$CLEANLOOP_MAX_ITER"); set_cfg_var MAX_ITER "$CLEANLOOP_MAX_ITER"; printf '\n'
  CLEANLOOP_STALL_LIMIT=$(ask_int "Iterazioni senza progresso prima dello stallo" "$CLEANLOOP_STALL_LIMIT"); set_cfg_var STALL_LIMIT "$CLEANLOOP_STALL_LIMIT"

  read -r -p $'\nConfigurare anche i parametri avanzati (promemoria contesto, finestra token, nome log)? [s/N]: ' val
  case "$val" in
    s|S|si|Si|SI|y|Y)
      printf '\n'
      CLEANLOOP_REMIND_EVERY=$(ask_int "Tool call tra un promemoria e l'altro dopo la soglia" "$CLEANLOOP_REMIND_EVERY"); set_cfg_var REMIND_EVERY "$CLEANLOOP_REMIND_EVERY"; printf '\n'
      CLEANLOOP_CONTEXT_WINDOW=$(ask_num_or_empty "Token finestra di contesto" "$CLEANLOOP_CONTEXT_WINDOW" "autodetect"); set_cfg_var CONTEXT_WINDOW "$CLEANLOOP_CONTEXT_WINDOW"; printf '\n'
      CLEANLOOP_LOG_FILE=$(ask_text "Nome log leggibile" "$CLEANLOOP_LOG_FILE"); set_cfg_var LOG_FILE "$CLEANLOOP_LOG_FILE"
      say "(nomi di $CLEANLOOP_TASK_FILE/$CLEANLOOP_PROGRESS_FILE non modificabili qui: usa --task-file/--progress-file a init, o rinominali a mano)"
      ;;
    *) : ;;
  esac
  say "parametri salvati in .cleanloop/config"
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
  local task_text="" brief_src=""
  local -a passed_keys=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --task|--brief|--threshold|--hard|--max-iter|--stall-limit|--remind-every|--permission-mode|--model|--effort|--max-budget-usd|--context-window|--progress-file|--task-file|--log-file|--use-subagents)
        { [ $# -ge 2 ] && [[ "$2" != -?* ]]; } || die "manca un valore per '$1'" ;;
    esac
    case "$1" in
    --task) task_text="$2"; shift 2;;
    --brief) brief_src="$2"; shift 2;;
    --threshold) CLEANLOOP_THRESHOLD="$2"; passed_keys+=(THRESHOLD); shift 2;;
    --hard) CLEANLOOP_HARD="$2"; passed_keys+=(HARD); shift 2;;
    --max-iter) CLEANLOOP_MAX_ITER="$2"; passed_keys+=(MAX_ITER); shift 2;;
    --stall-limit) CLEANLOOP_STALL_LIMIT="$2"; passed_keys+=(STALL_LIMIT); shift 2;;
    --remind-every) CLEANLOOP_REMIND_EVERY="$2"; passed_keys+=(REMIND_EVERY); shift 2;;
    --permission-mode) CLEANLOOP_PERMISSION_MODE="$2"; passed_keys+=(PERMISSION_MODE); shift 2;;
    --model) CLEANLOOP_MODEL="$2"; passed_keys+=(MODEL); shift 2;;
    --effort) CLEANLOOP_EFFORT="$2"; passed_keys+=(EFFORT); shift 2;;
    --max-budget-usd) CLEANLOOP_MAX_BUDGET_USD="$2"; passed_keys+=(MAX_BUDGET_USD); shift 2;;
    --context-window) CLEANLOOP_CONTEXT_WINDOW="$2"; passed_keys+=(CONTEXT_WINDOW); shift 2;;
    --progress-file) CLEANLOOP_PROGRESS_FILE="$2"; passed_keys+=(PROGRESS_FILE); shift 2;;
    --task-file) CLEANLOOP_TASK_FILE="$2"; passed_keys+=(TASK_FILE); shift 2;;
    --log-file) CLEANLOOP_LOG_FILE="$2"; passed_keys+=(LOG_FILE); shift 2;;
    --use-subagents) CLEANLOOP_USE_SUBAGENTS="$2"; passed_keys+=(USE_SUBAGENTS); shift 2;;
    --) shift;;
    -*) die "opzione sconosciuta: $1 (vedi '$(basename "$0")' senza argomenti per l'elenco)" ;;
    *) shift;;
  esac; done

  local k var
  if [ ${#passed_keys[@]} -gt 0 ]; then
    for k in "${passed_keys[@]}"; do var="CLEANLOOP_$k"; validate_cfg "$k" "${!var}"; done
  fi

  mkdir -p "$CWD/.cleanloop/state" "$CWD/.cleanloop/logs"
  touch "$CWD/.cleanloop/enabled"
  if [ ! -f "$CWD/.cleanloop/config" ]; then
    cat > "$CWD/.cleanloop/config" <<CFG
# cleanloop — config del progetto (le variabili d'ambiente hanno la precedenza; modifica con
# '$(basename "$0") config CHIAVE=VALORE' o a mano)
export CLEANLOOP_THRESHOLD="\${CLEANLOOP_THRESHOLD:-$CLEANLOOP_THRESHOLD}"       # % contesto -> checkpoint
export CLEANLOOP_HARD="\${CLEANLOOP_HARD:-$CLEANLOOP_HARD}"                 # % contesto -> chiusura forzata
export CLEANLOOP_MAX_ITER="\${CLEANLOOP_MAX_ITER:-$CLEANLOOP_MAX_ITER}"
export CLEANLOOP_STALL_LIMIT="\${CLEANLOOP_STALL_LIMIT:-$CLEANLOOP_STALL_LIMIT}"
export CLEANLOOP_REMIND_EVERY="\${CLEANLOOP_REMIND_EVERY:-$CLEANLOOP_REMIND_EVERY}"  # tool call tra promemoria dopo la soglia
export CLEANLOOP_PERMISSION_MODE="\${CLEANLOOP_PERMISSION_MODE:-$CLEANLOOP_PERMISSION_MODE}"   # auto|acceptEdits|bypassPermissions
export CLEANLOOP_MODEL="\${CLEANLOOP_MODEL:-$CLEANLOOP_MODEL}"                 # vuoto = default
export CLEANLOOP_EFFORT="\${CLEANLOOP_EFFORT:-$CLEANLOOP_EFFORT}"               # low|medium|high|xhigh|max, vuoto = default
export CLEANLOOP_MAX_BUDGET_USD="\${CLEANLOOP_MAX_BUDGET_USD:-$CLEANLOOP_MAX_BUDGET_USD}" # per iterazione, vuoto = nessun limite
export CLEANLOOP_CONTEXT_WINDOW="\${CLEANLOOP_CONTEXT_WINDOW:-$CLEANLOOP_CONTEXT_WINDOW}" # vuoto = autodetect (200k, o 1M se il modello è [1m])
export CLEANLOOP_PROGRESS_FILE="\${CLEANLOOP_PROGRESS_FILE:-$CLEANLOOP_PROGRESS_FILE}"    # nome del file di avanzamento
export CLEANLOOP_TASK_FILE="\${CLEANLOOP_TASK_FILE:-$CLEANLOOP_TASK_FILE}"          # nome del file dei task
export CLEANLOOP_LOG_FILE="\${CLEANLOOP_LOG_FILE:-$CLEANLOOP_LOG_FILE}"      # log leggibile delle uscite/ripartenze
export CLEANLOOP_USE_SUBAGENTS="\${CLEANLOOP_USE_SUBAGENTS:-$CLEANLOOP_USE_SUBAGENTS}"  # 1 = valuta il parallelismo con l'Agent tool
CFG
    say "creato .cleanloop/config"
  elif [ ${#passed_keys[@]} -gt 0 ]; then
    for k in "${passed_keys[@]}"; do var="CLEANLOOP_$k"; set_cfg_var "$k" "${!var}"; done
    say "aggiornata .cleanloop/config: ${passed_keys[*]}"
  fi
  local brief_file="$CWD/BRIEF.md" used_brief=0
  if [ ! -f "$CWD/$CLEANLOOP_TASK_FILE" ]; then
    if [ -n "$task_text" ]; then
      WIZ_TASKS=("$task_text"); write_task_file "$task_text"; say "creato $CLEANLOOP_TASK_FILE (T1 = task indicato; aggiungi altri con '$(basename "$0") add')"
    elif [ -n "$brief_src" ]; then
      read_brief_into "$brief_src" "$brief_file" || die "impossibile leggere il brief da '$brief_src' (file mancante o vuoto)"
      write_brief_task_file; used_brief=1
      say "creato BRIEF.md (da '$brief_src') e $CLEANLOOP_TASK_FILE: T1 chiede alla prima iterazione di pianificare da BRIEF.md"
    elif [ -f "$brief_file" ]; then
      write_brief_task_file; used_brief=1
      say "trovato BRIEF.md in radice: creato $CLEANLOOP_TASK_FILE con T1 di pianificazione"
    elif [ -t 0 ]; then
      wizard
    else
      local stdin_content; stdin_content=$(cat)
      if [ -n "$stdin_content" ]; then
        printf '%s\n' "$stdin_content" > "$brief_file"
        write_brief_task_file; used_brief=1
        say "creato BRIEF.md (da stdin) e $CLEANLOOP_TASK_FILE: T1 chiede alla prima iterazione di pianificare da BRIEF.md"
      else
        cp "$CLEANLOOP_ROOT/templates/TASK.md" "$CWD/$CLEANLOOP_TASK_FILE"; say "creato $CLEANLOOP_TASK_FILE — compilalo prima di 'run'"
      fi
    fi
  fi
  if [ ! -f "$CWD/$CLEANLOOP_PROGRESS_FILE" ]; then
    if [ "$used_brief" = 1 ]; then
      write_progress_file "Leggi BRIEF.md (il brief di partenza) e TASK.md: il task T1 chiede di derivare Obiettivo e coda reale dal brief. Fallo per primo, riscrivi TASK.md di conseguenza, poi chiudi il turno SENZA iniziare lavoro applicativo — l'esecuzione parte dalla prossima iterazione."
    else
      write_progress_file
    fi
    say "creato $CLEANLOOP_PROGRESS_FILE"
  fi
  if [ ! -f "$CWD/$CLEANLOOP_LOG_FILE" ]; then
    cleanloop_looplog "$CWD" "" 0 0 0 "" ""; say "creato $CLEANLOOP_LOG_FILE"
  fi
  if [ -d "$CWD/.git" ] && ! grep -qs '^\.cleanloop/state' "$CWD/.gitignore" 2>/dev/null; then
    printf '.cleanloop/state/\n.cleanloop/logs/\n' >> "$CWD/.gitignore"; say "aggiunto .cleanloop/state|logs a .gitignore"
  fi
  if [ "$used_brief" = 1 ]; then
    say "pronto. La prima iterazione pianifica da BRIEF.md — consigliato: '$(basename "$0") once' e rivedi $CLEANLOOP_TASK_FILE prima di lanciare 'run'"
  else
    say "pronto. Prossimo: compila $CLEANLOOP_TASK_FILE, poi: $(basename "$0") run"
  fi
}

# Rende leggibile lo stream-json di claude -p: testo dell'assistente, tool usati, modello all'avvio.
# Le righe dei subagenti (Agent tool, con --forward-subagent-text) sono taggate con le ultime 6 cifre
# del tool_use id che li ha lanciati, per poterle seguire separatamente dal turno principale.
stream_pretty() {
  jq -r --unbuffered '
    def tag: if length>6 then .[-6:] else . end;
    . as $ev |
    if $ev.type=="system" and $ev.subtype=="init" then "· modello: \($ev.model // "?")"
    elif $ev.type=="assistant" then
      ($ev.parent_tool_use_id // "") as $pid |
      ($ev.message.content // [])[] as $c |
      if $pid == "" then
        if $c.type=="text" then $c.text
        elif $c.type=="tool_use" and $c.name=="Agent" then "  → subagente [\($c.id|tag)] \"\($c.input.description // "?")\""
        elif $c.type=="tool_use" then "  → \($c.name)"
        else empty end
      else
        if $c.type=="text" then "  [\($pid|tag)] \($c.text)"
        elif $c.type=="tool_use" then "  [\($pid|tag)] → \($c.name)"
        else empty end
      end
    elif $ev.type=="result" then
      "· fine: \($ev.subtype // "?") · turni: \($ev.num_turns // 0) · costo API eq.: $\(($ev.total_cost_usd // 0)*100|round/100)"
    else empty end' 2>/dev/null
}
# Dal raw stream-json: "modello token_in token_out costo turni"
iteration_summary() {
  local raw="$1" model r
  model=$(grep -m1 '"subtype":"init"' "$raw" 2>/dev/null | jq -r '.model // "?"' 2>/dev/null); model=${model:-?}
  r=$(grep '"type":"result"' "$raw" 2>/dev/null | tail -1 | jq -r '
      (.usage // {}) as $u |
      "\(($u.input_tokens // 0)+($u.cache_creation_input_tokens // 0)+($u.cache_read_input_tokens // 0)) \($u.output_tokens // 0) \(.total_cost_usd // 0) \(.num_turns // 0)"' 2>/dev/null)
  echo "$model ${r:-0 0 0 0}"
}

run_iteration() {  # $1 = numero iterazione
  local i="$1" log="$CWD/.cleanloop/logs/iter-$(printf '%03d' "$i")-$(date +%Y%m%d-%H%M%S).log"
  local window autocompact args=()
  window=$(cleanloop_context_window)
  # rete di sicurezza: auto-compact ben oltre la soglia dura, nel range accettato (100k-1M)
  autocompact=$(awk -v w="$window" -v h="$CLEANLOOP_HARD" 'BEGIN{ a=int(w*(h+25)/100); if(a<100000)a=100000; if(a>1000000)a=1000000; print a }')
  args=( -p --output-format stream-json --verbose --plugin-dir "$CLEANLOOP_ROOT"
         --permission-mode "$CLEANLOOP_PERMISSION_MODE"
         --autocompact "$autocompact"
         --append-system-prompt-file "$CLEANLOOP_ROOT/prompts/iteration-system.md"
         --forward-subagent-text
         --name "cleanloop-$i" )
  [ -n "$CLEANLOOP_MODEL" ] && args+=( --model "$CLEANLOOP_MODEL" )
  [ -n "$CLEANLOOP_EFFORT" ] && args+=( --effort "$CLEANLOOP_EFFORT" )
  [ -n "$CLEANLOOP_MAX_BUDGET_USD" ] && args+=( --max-budget-usd "$CLEANLOOP_MAX_BUDGET_USD" )
  local prompt="Iterazione $i/$CLEANLOOP_MAX_ITER di cleanloop. Il task è in $CLEANLOOP_TASK_FILE, lo stato in $CLEANLOOP_PROGRESS_FILE (entrambi già iniettati nel contesto). Riparti dal 'Prossimo passo (handoff)', completa e verifica UN sotto-task, aggiorna $CLEANLOOP_PROGRESS_FILE, termina."
  if [ "$CLEANLOOP_USE_SUBAGENTS" = "1" ]; then
    prompt+=" Se nella coda ci sono più task pendenti indipendenti tra loro (nessuna dipendenza, nessun file in comune), valuta di lanciarli in parallelo con l'Agent tool, uno per task, con description breve e prompt autosufficiente. Istruisci ogni subagente a restituire il risultato come TESTO, non a scrivere file (i subagenti possono avere la scrittura bloccata su alcuni pattern di nome file): applichi tu, il turno principale, le modifiche ai file una volta raccolti i risultati. Attendi tutti i risultati prima di aggiornare $CLEANLOOP_PROGRESS_FILE, che scrivi solo tu."
  fi
  say "iterazione $i/$CLEANLOOP_MAX_ITER — log: ${log#$CWD/}"
  cleanloop_log "$CWD" "event=iter_start iter=$i model=${CLEANLOOP_MODEL:-default} threshold=${CLEANLOOP_THRESHOLD}% hard=${CLEANLOOP_HARD}% subagents=${CLEANLOOP_USE_SUBAGENTS}"
  local t0=$SECONDS raw="${log%.log}.jsonl"
  CLEANLOOP_ACTIVE=1 CLEANLOOP_ITER="$i" CLEANLOOP_ROOT="$CLEANLOOP_ROOT" \
    claude "${args[@]}" "$prompt" 2>>"$log" | tee "$raw" | stream_pretty | tee -a "$log"
  local rc="${PIPESTATUS[0]}" pct used win sess lvl reason
  # riepilogo dall'evento result (token, costo, modello)
  local model tin tout cost turns
  read -r model tin tout cost turns <<< "$(iteration_summary "$raw")"
  say "modello: $model · token: $(cleanloop_short_num "$tin") in / $(cleanloop_short_num "$tout") out · costo API eq.: $(LC_ALL=C awk -v c="$cost" 'BEGIN{printf "$%.2f", c}') · turni: $turns"
  read -r pct used win sess <<< "$(cleanloop_last_ctx "$CWD")"
  lvl=$(cat "$CWD/.cleanloop/state/$sess.level" 2>/dev/null || echo 0)
  case "$lvl" in 2) reason=hard_threshold ;; 1) reason=soft_threshold ;; *) reason=natural_end ;; esac
  local reason_it; case "$reason" in hard_threshold) reason_it="soglia dura (${CLEANLOOP_HARD}%)";; soft_threshold) reason_it="soglia (${CLEANLOOP_THRESHOLD}%)";; *) reason_it="fine naturale";; esac
  [ "$rc" -ne 0 ] && reason_it="$reason_it, exit $rc"
  cleanloop_looplog "$CWD" "$i" "$pct" "$used" "$win" "$reason_it" "$(status_of)" "$model" "$tin" "$tout" "$cost"
  ITER_END_LINE="event=iter_end iter=$i exit=$rc dur=$((SECONDS-t0))s model=$model tokens_in=$tin tokens_out=$tout cost_usd=$cost turns=$turns ctx=${pct}% used=$used window=$win reason=$reason session=$sess"
  return "$rc"
}

cmd_run() {
  need_claude; need_jq
  local max="$CLEANLOOP_MAX_ITER"
  local -a passed_keys=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -n|--max-iter|--threshold|--hard|--stall-limit|--remind-every|--permission-mode|--model|--effort|--max-budget-usd|--context-window|--progress-file|--task-file|--log-file|--use-subagents)
        { [ $# -ge 2 ] && [[ "$2" != -?* ]]; } || die "manca un valore per '$1'" ;;
    esac
    case "$1" in
    -n|--max-iter) max="$2"; shift 2;;
    --threshold) CLEANLOOP_THRESHOLD="$2"; passed_keys+=(THRESHOLD); shift 2;;
    --hard) CLEANLOOP_HARD="$2"; passed_keys+=(HARD); shift 2;;
    --stall-limit) CLEANLOOP_STALL_LIMIT="$2"; passed_keys+=(STALL_LIMIT); shift 2;;
    --remind-every) CLEANLOOP_REMIND_EVERY="$2"; passed_keys+=(REMIND_EVERY); shift 2;;
    --permission-mode) CLEANLOOP_PERMISSION_MODE="$2"; passed_keys+=(PERMISSION_MODE); shift 2;;
    --model) CLEANLOOP_MODEL="$2"; passed_keys+=(MODEL); shift 2;;
    --effort) CLEANLOOP_EFFORT="$2"; passed_keys+=(EFFORT); shift 2;;
    --max-budget-usd) CLEANLOOP_MAX_BUDGET_USD="$2"; passed_keys+=(MAX_BUDGET_USD); shift 2;;
    --context-window) CLEANLOOP_CONTEXT_WINDOW="$2"; passed_keys+=(CONTEXT_WINDOW); shift 2;;
    --progress-file) CLEANLOOP_PROGRESS_FILE="$2"; passed_keys+=(PROGRESS_FILE); shift 2;;
    --task-file) CLEANLOOP_TASK_FILE="$2"; passed_keys+=(TASK_FILE); shift 2;;
    --log-file) CLEANLOOP_LOG_FILE="$2"; passed_keys+=(LOG_FILE); shift 2;;
    --use-subagents) CLEANLOOP_USE_SUBAGENTS="$2"; passed_keys+=(USE_SUBAGENTS); shift 2;;
    --) shift;;
    -*) die "opzione sconosciuta: $1 (vedi '$(basename "$0")' senza argomenti per l'elenco)" ;;
    *) shift;;
  esac; done
  [[ "$max" =~ ^[0-9]+$ ]] || die "numero di iterazioni non valido: '$max'"
  CLEANLOOP_MAX_ITER="$max"

  local k var
  if [ ${#passed_keys[@]} -gt 0 ]; then
    for k in "${passed_keys[@]}"; do var="CLEANLOOP_$k"; validate_cfg "$k" "${!var}"; done
    say "override per questa esecuzione (non salvati in .cleanloop/config): ${passed_keys[*]}"
  fi

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

cmd_config() {
  local f="$CWD/.cleanloop/config"
  [ -f "$f" ] || die "manca .cleanloop/config: esegui prima '$(basename "$0") init'"
  if [ $# -eq 0 ]; then cat "$f"; return; fi
  local kv key val var
  for kv in "$@"; do
    case "$kv" in
      *=*) key="${kv%%=*}"; val="${kv#*=}" ;;
      *) die "formato atteso CHIAVE=VALORE, ricevuto: '$kv' (chiavi valide: $CFG_KEYS)" ;;
    esac
    key="${key#CLEANLOOP_}"
    validate_cfg "$key" "$val"
    set_cfg_var "$key" "$val"
    var="CLEANLOOP_$key"; export "$var=$val"
    say "$key = ${val:-<vuoto>}"
  done
}

cmd_log() {
  local n=""; while [ $# -gt 0 ]; do case "$1" in -n) [ $# -ge 2 ] || die "manca un valore per '-n'"; n="$2"; shift 2;; *) shift;; esac; done
  local f="$CWD/.cleanloop/logs/events.log"
  [ -f "$f" ] || die "nessun log eventi in $f"
  if [ -n "$n" ]; then tail -n "$n" "$f"; else cat "$f"; fi
}

case "${1:-}" in
  init)    shift; cmd_init "$@" ;;
  add)     shift; cmd_add "$@" ;;
  tasks)   cmd_tasks ;;
  run)     shift; cmd_run "$@" ;;
  once)    shift; cmd_run "$@" -n 1 ;;
  status)  cmd_status ;;
  config)  shift; cmd_config "$@" ;;
  log)     shift; cmd_log "$@" ;;
  reset)   rm -rf "$CWD/.cleanloop/state"; say "stato azzerato" ;;
  disable) rm -f "$CWD/.cleanloop/enabled"; say "hook disattivati in questo progetto" ;;
  *) usage ;;
esac
