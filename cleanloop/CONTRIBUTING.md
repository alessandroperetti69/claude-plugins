# Contributing

Thanks for helping improve cleanloop. Short version:

1. **Try locally** with `claude --plugin-dir ./cleanloop` (no install needed); the runner picks up the folder it is launched from.
2. **Keep the constraints**: only `bash`, `jq`, `md5|md5sum`, `claude`; hooks exit 0 silently when there is nothing to say; no `timeout`, no GNU-only flags (macOS + Linux).
3. **Test** the hooks with JSON on stdin (see [docs/en/technical/development.md](docs/en/technical/development.md)) and run `bash -n scripts/*.sh`. For behaviour changes, run one real `cleanloop once` on a trivial task.
4. **Document both languages**: any change to thresholds, formats, commands or hooks must land in `docs/en` **and** `docs/it`.
5. **Version**: bump `.claude-plugin/plugin.json` and the marketplace entry, add a `CHANGELOG.md` line (patch = fixes, minor = new options/hooks, major = incompatible `PROGRESS.md`/config format).
6. Open a PR against `main` with a description of what changed and how you tested it.

Texts addressed to the model (hook messages, `SKILL.md`, `prompts/`) are in Italian on purpose — the primary users work in Italian. Identifiers, keys and file names stay in English.
