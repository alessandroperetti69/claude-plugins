#!/usr/bin/env bash
# Hook PreCompact: se la compattazione parte prima del checkpoint, chiede al riassunto
# di preservare lo stato e ricorda al modello di aggiornare PROGRESS.md.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty'); cwd="${cwd:-$PWD}"
cleanloop_is_active "$cwd" || exit 0
cleanloop_load_config "$cwd"
msg="[cleanloop] Compattazione in corso. Nel riassunto conserva: obiettivo, sotto-task in corso, prossimo passo esatto, decisioni prese, comandi di verifica. Subito dopo la compattazione aggiorna $CLEANLOOP_PROGRESS_FILE con le stesse informazioni."
printf '{"hookSpecificOutput":{"hookEventName":"PreCompact","additionalContext":%s}}\n' "$(printf '%s' "$msg" | cleanloop_json_str)"
