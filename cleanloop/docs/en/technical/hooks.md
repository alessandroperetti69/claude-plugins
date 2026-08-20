# Hooks (reference)

Registered in `hooks/hooks.json`; each command is `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh"` with a 10 s timeout. All read the event JSON from stdin, share `scripts/lib.sh`, and **exit silently (exit 0, no output) when cleanloop is not active** in `cwd` (no `.cleanloop/enabled` and `CLEANLOOP_ACTIVE≠1`).

## Shared functions (`lib.sh`)
| Function | What it does |
|---|---|
| `cleanloop_load_config cwd` | sources `.cleanloop/config` then applies defaults; exports the `CLEANLOOP_*` variables |
| `cleanloop_is_active cwd` | `CLEANLOOP_ACTIVE=1` or `cwd/.cleanloop/enabled` exists |
| `cleanloop_context_window` | override → `haiku` in the model (`CLEANLOOP_MODEL`, or the global one) → 200000 → otherwise 1000000 |
| `cleanloop_used_tokens transcript` | sums `input + cache_creation + cache_read` of the last `assistant` message |
| `cleanloop_pct used window` | rounded integer percentage |
| `cleanloop_checksum file` | `md5 -q` (macOS) or `md5sum` (Linux); `none` if the file is missing |
| `cleanloop_state_dir cwd` | creates and returns `cwd/.cleanloop/state` |
| `cleanloop_json_str` | stdin → escaped JSON string (via `jq -Rs`) |
| `cleanloop_log cwd text…` | appends `<timestamp> text` to `cwd/.cleanloop/logs/events.log` |
| `cleanloop_last_ctx cwd` | prints `pct used window session` from `state/last.json` (or `0 0 0 -`) |
| `cleanloop_looplog cwd n pct used window reason status` | appends a row to `LOOPLOG.md` (creates the header if missing; with empty `n` creates the header only) |
| `cleanloop_fmt_num n` | thousands separator with a space (`290 877`) |
| `cleanloop_status_of cwd` | value of `STATUS:` in `PROGRESS.md` |

## SessionStart — `session-start.sh`
- **Matcher**: `startup|resume|clear|compact`
- **Input used**: `cwd`, `session_id`, `source`
- **Effects**: if `source` is `clear`/`compact` and not in loop mode, appends the `↻` row to `LOOPLOG.md` with the context before the restart; records `event=session_start` in `events.log` with `prev_ctx` (last context measurement before the restart, from `state/last.json`); writes the initial checksum of `PROGRESS.md` to `state/<session>.start`; resets `<session>.level` and `<session>.count`.
- **Output**: `hookSpecificOutput.additionalContext` with: mode (interactive / loop with iteration number), thresholds, one-line rules; if `source` is `clear`/`compact` it adds "do not reconstruct history, resume from the handoff"; then `TASK.md` (max 6000 bytes) and `PROGRESS.md` (max 8000 bytes). If `PROGRESS.md` is missing, it asks to create it from the template.

## PostToolUse — `context-guard.sh`
- **Matcher**: all tools
- **Input used**: `cwd`, `session_id`, `transcript_path`
- **Per-session state**: `state/<session>.level` (0 = no warning, 1 = soft threshold, 2 = hard), `state/<session>.count` (tool calls since the warning), `state/last.json` (`{session, used, window, pct, ts}` — read by `cleanloop status`).
- **Logic**:
  1. `pct ≥ HARD` and `level < 2` → forced-close message, `level=2`, `event=threshold level=hard` in the log.
  2. else `pct ≥ THRESHOLD` and `level < 1` → checkpoint message, `level=1`, `event=threshold level=soft` in the log.
  3. else if `level ≥ 1` → `count++`; every `CLEANLOOP_REMIND_EVERY` sends a short reminder.
- **Text**: depends on the mode. Loop (`CLEANLOOP_ACTIVE=1`): "…run the checkpoint protocol and END THE TURN". Interactive: "…then ask the user to run /clear and resume with /cleanloop". Both append the 4-point checkpoint protocol.
- **Output**: `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":…},"systemMessage":…}` — `additionalContext` goes to the model, `systemMessage` is the short line shown to the user.

## PreCompact — `pre-compact.sh`
- **Matcher**: `auto|manual`
- **Output**: `additionalContext` asking the summary to preserve goal, sub-task in progress, next step, decisions, verification commands, and to update `PROGRESS.md` right after.

## Stop — `stop-guard.sh`
- **Active only with** `CLEANLOOP_ACTIVE=1` (loop mode).
- **Input used**: `cwd`, `session_id`, `stop_hook_active`
- **Logic**: if `stop_hook_active` is `true` → exit (already blocked once). If the current checksum of `PROGRESS.md` equals the one in `state/<session>.start` → `{"decision":"block","reason":"…update PROGRESS.md…"}`; otherwise no output.
- **Guarantee**: blocks at most once per session, hence can never wedge the loop.

## Contract with Claude Code
- Input fields read: `cwd`, `session_id`, `transcript_path`, `source`, `stop_hook_active`.
- Output fields emitted: `hookSpecificOutput.additionalContext` (SessionStart, PostToolUse, PreCompact), `systemMessage` (PostToolUse), `decision`/`reason` (Stop).
- No hook uses a non-zero exit code: internal errors are silent so as not to disturb the session (check with `cleanloop status` and `.cleanloop/state/last.json`).
