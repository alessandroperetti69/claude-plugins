#!/usr/bin/env bash
# Hook Stop: in modalità loop, impedisce di terminare l'iterazione senza aver
# aggiornato PROGRESS.md (una sola volta: stop_hook_active evita cicli).
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
input=$(cat)
[ "${CLEANLOOP_ACTIVE:-0}" = "1" ] || exit 0
active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false')
[ "$active" = "true" ] && exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty'); cwd="${cwd:-$PWD}"
cleanloop_load_config "$cwd"
session=$(printf '%s' "$input" | jq -r '.session_id // "nosession"')
state=$(cleanloop_state_dir "$cwd")
marker="$state/$session.start"
progress="$cwd/$CLEANLOOP_PROGRESS_FILE"
[ -f "$marker" ] || exit 0
[ "$(cat "$marker")" != "$(cleanloop_checksum "$progress")" ] && exit 0
reason="[cleanloop] Non puoi terminare l'iterazione senza aggiornare $CLEANLOOP_PROGRESS_FILE. Aggiorna ora Fatto / In corso / Prossimo passo (handoff) / Decisioni / Trappole, imposta STATUS (IN_PROGRESS, DONE o BLOCKED) e ITERATION, poi termina."
printf '{"decision":"block","reason":%s}\n' "$(printf '%s' "$reason" | cleanloop_json_str)"
