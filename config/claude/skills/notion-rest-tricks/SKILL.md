---
name: notion-rest-tricks
description: Use this skill when working with the token-based Notion MCP servers (e.g. `mcp__notion-wife__API-*`) that wrap the raw Notion REST API — distinct from the OAuth `mcp__notion__*` server covered by notion-tricks. Covers native API JSON property shapes, the two-step page-then-content creation flow, and using `curl` with the `NOTION_TOKEN_*` env var to bypass MCP entirely for bulk/precise operations.
---

# Notion REST MCP Tricks

For token-based MCP servers built on `@notionhq/notion-mcp-server` (e.g. `notion-wife`). These expose the raw Notion REST API: tools are named `API-post-page`, `API-query-data-source`, `API-patch-block-children`, etc.

If you're using the OAuth `mcp__notion__*` server (which speaks Notion-flavoured Markdown), see **notion-tricks** instead. The two skills overlap deliberately — pick the one that matches the server you're calling.

## Property shape: native Notion API JSON, not Markdown

The OAuth server lets you write properties as Markdown frontmatter. The REST server does not. You must pass the native Notion API shape:

```json
{
  "Name":   { "title": [{"type": "text", "text": {"content": "20th Century"}}] },
  "Tags":   { "multi_select": [{"name": "Cocktail"}, {"name": "shaken"}] },
  "Status": { "select": {"name": "Make Again"} },
  "Rating": { "number": 4 },
  "Link":   { "url": "https://example.com" }
}
```

For multi/single select, pass option **names** by string — the API resolves them to existing options. If the option doesn't exist, the call fails (see "Adding new select options" below).

## Two-step page creation: properties first, body second

`API-post-page`'s `children` field is declared as `array of strings` in the MCP wrapper, which is awkward to use. The reliable pattern is:

1. **Create the page** with `API-post-page` — set `parent`, `icon`, `properties`. Capture the returned `id`.
2. **Append content** with `API-patch-block-children` — pass `block_id` (the page id) and an array of block objects.

The `API-patch-block-children` wrapper schema currently only types `paragraph` and `bulleted_list_item` block types, but the underlying API accepts the full set (`heading_1/2/3`, `numbered_list_item`, `to_do`, `code`, etc.). If the wrapper rejects something, fall back to `curl` (see below).

### Known broken: `API-update-a-block` for block content

**Don't use this tool for editing block text — it's a confirmed bug in `@notionhq/notion-mcp-server`.** The OpenAPI spec names the body field `type`, and `http-client.ts` forwards the parameter as `body.type` instead of spreading it at body root. The Notion API expects the block-type key (`bulleted_list_item`, `paragraph`, …) at body root and rejects with: *"body.type should be not present"*.

No invocation form fixes this — passing `type: {"bulleted_list_item": {...}}` or `type: {"rich_text": [...]}` both fail. The only operation that works through the tool is the `archived: true|false` toggle (because `archived` maps to the correct body field directly).

**Workaround**: hit the API with `curl` instead.

```bash
curl -fsS -X PATCH "https://api.notion.com/v1/blocks/<block_id>" \
  -H "Authorization: Bearer $NOTION_TOKEN_WIFE" \
  -H "Notion-Version: 2025-09-03" \
  -H "Content-Type: application/json" \
  -d '{"bulleted_list_item":{"rich_text":[{"type":"text","text":{"content":"new text"}}]}}'
```

Source verified: see `parser.ts:420–428` (flattens `requestBody.type` into a tool param) and `http-client.ts:118–134` (passes the param object literally into the body) in https://github.com/makenotion/notion-mcp-server.

Tracked upstream as [makenotion/notion-mcp-server#271](https://github.com/makenotion/notion-mcp-server/issues/271) (open as of 2026-04-16, confirmed by another reporter 2026-04-20). No fix PR yet; check the issue before assuming the curl workaround is still needed.

## Parent: prefer `database_id` for single-source databases

`API-post-page`'s parent uses one of three forms. For databases:

```json
{ "type": "database_id", "database_id": "<uuid>" }
```

For multi-source databases (rare), the API can also accept `data_source_id`:

```json
{ "type": "data_source_id", "data_source_id": "<uuid>" }
```

You'll see both IDs in `API-post-search` results — the `data_source_id` is the inner collection, the `database_id` is the wrapping page. Both `parent.database_id` and `parent.data_source_id` work for single-source DBs; the wrapper's schema field is named `database_id` even when it represents a data source, which is confusing. When in doubt, try `database_id` first.

## Searching

- `API-post-search` does **title-only** matching across the workspace. Good for finding a page or database by name.
- `API-query-data-source` is the powerful one — supports filters, sorts, and pagination over a specific data source. Use this to look inside a database:

```json
{
  "data_source_id": "8ed55d29-7075-4df6-afcf-f49acd9f72a3",
  "filter": {"property": "Name", "title": {"contains": "20th"}},
  "page_size": 10
}
```

Filter syntax follows the Notion API — see https://developers.notion.com/reference/post-database-query-filter.

## Adding new select / multi_select options

Same trap as the OAuth server: passing an unknown option name to `API-post-page` fails. To add a new option, `API-update-data-source` requires the **full existing options list plus the new one** — otherwise existing options get wiped:

```json
{
  "data_source_id": "<uuid>",
  "properties": {
    "Tags": {
      "multi_select": {
        "options": [
          {"name": "Existing 1", "color": "red"},
          {"name": "Existing 2", "color": "blue"},
          {"name": "New Tag",    "color": "green"}
        ]
      }
    }
  }
}
```

The dataset of existing options can be huge (Cay's Recipes Tags has ~200). For workspaces where this matters, write a helper script that fetches current options, appends, and PATCHes — see **notion-recipes** for an example.

## Bypassing MCP with curl

For bulk reads, schema-only fetches, or block types the MCP wrapper doesn't expose, hit the API directly:

```bash
curl -fsS https://api.notion.com/v1/data_sources/<id> \
  -H "Authorization: Bearer $NOTION_TOKEN_WIFE" \
  -H "Notion-Version: 2025-09-03" \
  | jq '.properties.Tags.multi_select.options[].name'
```

This is much smaller than the corresponding MCP response (which embeds schema, sample rows, etc.) and is the right tool for "just give me the tag list".

The token env var is configured in `config/claude-mcp/servers.json` — currently `NOTION_TOKEN_WIFE`. Each token-based server maps to one workspace; the same workspace_id appears in `API-get-self`'s response.

## When the MCP server is misconfigured

`API-get-self` returning `401 unauthorized` usually means the token env var was empty or stale when Claude Code launched. MCP servers capture env at startup, so:

1. Save/source the env file with the new token.
2. Restart Claude Code (reconnecting `/mcp` alone won't pick up parent-process env changes).

The `${VAR}` substitution in `servers.json` is performed by the launcher described in the recent `claude-with` commits — verify the var is exported in the parent shell.

## General tips (mirrors notion-tricks)

- Prefer `API-post-search` first to find a page/database by name, then `API-retrieve-a-data-source` to read schema, then targeted `API-query-data-source` for actual data.
- When responses are huge, drop to `curl | jq` for surgical extraction.
- Always check `API-get-self` first when a server seems broken — it confirms auth and identifies the workspace.
