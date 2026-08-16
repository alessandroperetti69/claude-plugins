# Development and release

## Repo layout
The repo `alessandroperetti69/claude-plugins` is a Claude Code **marketplace**: `.claude-plugin/marketplace.json` at the root lists the plugins, each in a top-level folder. cleanloop lives in `cleanloop/`:
```
cleanloop/
├── .claude-plugin/plugin.json     manifest (name, version, description)
├── skills/cleanloop/SKILL.md      the skill (auto-discovered)
├── hooks/hooks.json               hook registration (auto-discovered)
├── scripts/                       lib.sh, 4 hooks, cleanloop.sh
├── prompts/iteration-system.md    system prompt appended in -p
├── templates/                     TASK.md, PROGRESS.md
├── docs/{it,en}/                  this documentation
└── README.md
```

## Try it locally without installing
```bash
claude --plugin-dir /path/to/claude-plugins/cleanloop
```
The runner passes `--plugin-dir` itself, so `bash scripts/cleanloop.sh run` always uses the code of the folder it is launched from — convenient for development.

## Manual hook tests
Hooks are plain scripts: test them with a JSON on stdin. Example (threshold exceeded with a 1M window):
```bash
T=$(mktemp -d); cd "$T"
printf '{"type":"assistant","message":{"usage":{"input_tokens":1000,"cache_creation_input_tokens":9000,"cache_read_input_tokens":250000}}}\n' > tr.jsonl
bash /path/to/cleanloop/scripts/cleanloop.sh init --task test
echo "{\"cwd\":\"$T\",\"session_id\":\"s1\",\"transcript_path\":\"$T/tr.jsonl\"}" \
  | bash /path/to/cleanloop/scripts/context-guard.sh | jq .
```
Cases to cover when touching the logic: hook inert without `.cleanloop/enabled`; first warning at threshold; silence on the next call; reminder every N; hard threshold; Stop hook blocking once then letting go (with `stop_hook_active: true`); SessionStart with `source: clear`.

End-to-end test: `cleanloop init --task "create hello.txt containing 'hi'"`, `CLEANLOOP_MODEL=sonnet CLEANLOOP_MAX_BUDGET_USD=1 cleanloop once`, then check `PROGRESS.md` (`STATUS: DONE`) and `.cleanloop/state/last.json`.

Syntax: `bash -n scripts/*.sh`.

## Conventions
- No dependencies beyond `bash`, `jq`, `md5|md5sum`, `claude`. No `timeout`, nothing GNU-only.
- Hooks must never fail loudly: exit 0 and no output when there is nothing to say.
- Texts addressed to the model are in Italian (the user's language); identifiers and keys in English.
- Any change to thresholds/formats must be reflected in `docs/it` **and** `docs/en`.

## Release
1. Bump `version` in `cleanloop/.claude-plugin/plugin.json` and in the `.claude-plugin/marketplace.json` entry; add an entry to `CHANGELOG.md`.
2. Commit and push to `main`.
3. On users' machines: `/plugin marketplace update peretti-plugins` then `/plugin update cleanloop`.

Semantic versioning: patch = fixes in scripts/texts; minor = new options or hooks; major = non-backward-compatible change to the `PROGRESS.md`/config format.
