---
name: gortex
description: Use when querying the gortex code-graph MCP (mcp__gortex__*) — "who calls this", "what breaks if I change this", finding a symbol. Covers the parameters that keep responses readable, the filters that do not work, and when to just use grep instead. Keywords - gortex, code graph, find_usages, search_symbols, blast radius, who calls this, index stale, GORTEX_TOOLS.
---

# gortex

A code-intelligence graph served over MCP. Worth reaching for on **one** question:
**"who touches this symbol, before I change it"** — the blast radius of a rename or a deletion.

Everything else (a literal string, a filename, runtime behaviour) is faster with grep or by
running the thing.

## Keep the responses readable, or you will abandon it

The defaults are wide enough to drown a turn, which is how it ends up unused in favour of grep.

- `search_symbols` — always pass **`compact: true`**. One line per symbol, immediately readable.
- `find_usages` — pass **`fields: "from_name,from_path,from_line"`** and optionally
  `group_by: "file"`. Raw, it returns ~16 columns per row, and most rows are `typed_as /
  parameter_type` noise from every signature that merely mentions the type. `flavor` / `context`
  filter those out.
- Anything still huge: `max_bytes`, or `limit` + `cursor`.

## Caveats found the hard way

- **`exclude_tests: true` does not reliably drop test hits.** It has reported `n_test_refs=0`
  while test files were plainly in the results. Read the paths; do not trust the flag to scope a
  blast radius.
- **Untracked repo = empty result, not an error.** A bare symbol name returns a
  `possible_extraction_gap` caveat with zero rows, which reads like "no usages" but means "this
  repo was never indexed". Check `gortex repos` first.
- **Symbol IDs are `<repo>/<path>::<Symbol>`**, not bare names. Get one from `search_symbols`
  rather than constructing it.
- **`index_health` and `gortex repos` can disagree.** After a large merge, `index_health` said
  `stale=0` while `repos` showed `stale` against a hours-old HEAD. Believe `index_health`.

## Daemon and index housekeeping

Your global CLAUDE.md already covers the common case: the SessionStart hook injects daemon
status, and "daemon is not running" means `gortex daemon start --detach`. The gaps it does not
cover:

- **Repo not tracked** — "cwd is not covered by any tracked repo" means the graph tools return
  empty results, not errors. Fix with `gortex track . --wait` (indexing a large repo takes a
  minute or two). Nothing in the repo changes; the index lives in `~/.gortex/cache`.
- **Stale index** — there is no `reindex` command; the daemon watches and re-indexes on its own.
  If `gortex repos` still says stale and results look wrong, `gortex daemon reload` (re-reads
  config, picks up repos) then `gortex daemon restart`. Check with `index_health`, not the
  freshness column — see the caveat above.
- **Daemon dies on reboot** — it is currently a bare process, not a service
  (`gortex daemon service-status` → "launchd: not installed"). `gortex daemon install-service`
  installs a launchd/systemd unit if the start-it-manually step gets annoying.

## Trimming the tool surface

It publishes **54 tools** by default, seven of which can write (`edit_file`, `edit_symbol`,
`batch_edit`, `write_file`, `rename_symbol`, `save_note`/`store_memory`, `overlay_*`). Normal
edits should go through the usual Edit/Write path, so the MCP fragment restricts it:

```json
"args": ["mcp", "--tools-mode", "defer"],
"env": { "GORTEX_TOOLS": "nav,+search_symbols,+get_symbol_source,+index_health" }
```

That yields 21 read-only tools. `--tools-mode defer` keeps the rest reachable through
`tools_search` instead of deleting them. `GORTEX_TOOLS` overrides the `--tools` flag.

Do not infer preset contents from `gortex tools list`'s PRESETS column — it suggested "core is
~10 tools" when the server actually publishes 54. Ask the server (`tools/list`).

## Setup

A `claude-with` fragment at `config/claude-mcp/fragments/gortex.json`, linked into a repo with
`claude-with --link gortex`. Command is bare **`gortex`** (PATH-resolved) — never an absolute
Homebrew path, since these repos are also worked on from Fedora.

`gortex install` writes a global `~/.claude.json` stanza and `gortex init` writes a per-repo
`.mcp.json`; both are ignored under `--strict-mcp-config`, so the fragment is what actually
makes it reachable. Avoid `gortex init` in a repo that already has a checked-in `.mcp.json`.

To check what a stanza actually publishes without launching a session, speak MCP at it:

```bash
{ printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"p","version":"0"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  sleep 6; } | GORTEX_TOOLS=... timeout 20 gortex mcp --tools-mode defer 2>/dev/null \
| python3 -c "import sys,json
[print(len(d['result']['tools']),'tools') for d in map(json.loads,sys.stdin) if d.get('id')==2]"
```

Hold stdin open with the trailing `sleep` or the server exits before replying, and do not pipe
through `head` — it SIGPIPEs mid-answer. Both look like "the server is broken".

`gortex install` also drops ~21 `gortex-*` skills into `~/.claude/skills/`. They are redundant
with the tool descriptions and cost context in every session — delete them; they come back on
each upgrade.
