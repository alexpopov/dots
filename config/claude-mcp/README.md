# claude-mcp

Server definitions for `claude-with` (`bin/scripts/claude-with`), which launches
`claude --strict-mcp-config` with an interactively-picked subset of MCP servers.

```
servers.json      global servers — offered in every directory
fragments/        opt-in servers — offered only where a project links them in
```

## servers.json

A bare `name -> config` map (the value side of `mcpServers`). Anything here is
available everywhere, so keep it to servers that are genuinely global (Notion,
Anki, Things…). Symlinked to `~/.config/claude-mcp/servers.json` by
`bootstrap.sh`.

`${VAR}` references are substituted at launch from
`~/.config/bash/private/mcp_tokens.sh`.

## fragments/

Same shape as `servers.json`, one file per server (or per bundle). Nothing here
is offered until a project opts in — that's the point: `xcodebuild` shows up in
the iOS repos and nowhere else.

Opt a project in:

```bash
cd ~/Development/some-ios-app
claude-with --link xcodebuild     # or bare --link to pick from a list
```

That symlinks `~/.config/claude-mcp/fragments/xcodebuild.json` into the repo's
`.claude-mcp/`, so edits to the fragment in dots reach every project at once.
Copy the file instead of linking if a project needs its own tweaks, or just
hand-write `.claude-mcp/whatever.json` for a one-off server.

`claude-with` picks up project servers from, in order:

1. `./.claude-mcp.json` and `./.claude-mcp/*.json`
2. the same two at the git root

They appear in the picker individually, tagged `(project)`, and shadow a global
server of the same name. Either the bare map or a `{"mcpServers": {...}}`
wrapper is accepted.

`.claude-mcp/` is usually gitignored (personal tooling); commit it when the
whole repo should get the server.

## Not the same as `.mcp.json`

A stock `.mcp.json` — the file Claude Code reads natively — is still offered,
but as a single bundled choice, since it's typically checked in and shared.
`--strict-mcp-config` would otherwise drop it entirely.

## Other commands

```bash
claude-with --list    # every server this directory could offer
claude-with --yolo    # adds --dangerously-skip-permissions
```
