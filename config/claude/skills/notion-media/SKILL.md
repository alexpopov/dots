---
name: notion-media
description: Use this skill when adding, querying, or updating entries in Alp's Notion Media List database. Covers the schema, tag/creator conventions, the `media-helper.sh` script for fast field operations via curl, and rules about creating new options.
---

# Notion Media List

Alp's personal Notion workspace. Use `curl + NOTION_TOKEN` for everything — no OAuth MCP needed.

## Database identifiers

| Key | Value |
|-----|-------|
| Media List DB ID | `ec9650e3-40fe-4cac-977b-a37e7b34d22e` |
| Artists DB ID | `e40a874d-0d69-4fac-b6b6-abfa2bae0703` |

## Schema

| Field | Type | Notes |
|---|---|---|
| Name | title | Title of the work |
| Type | select | Movie, TV Show, Book, Audiobook, Podcast, Video Game, Theatre, Documentary, Drawing, Ink |
| Status | select | To Do, In Progress, Done, Do Again, Nope, Unfinished. **Default: To Do** |
| Rating | select | ★☆☆☆☆ ★★☆☆☆ ★★★☆☆ ★★★★☆ ★★★★★ |
| Tags | multi_select | Genres, themes, etc. — many options |
| From | multi_select | Who recommended it (Max, Haydn, Director, Reddit, …) |
| Info | url | Link to IMDB, Goodreads, Steam, etc. |
| Length (hours) | number | |
| Priority | number | |
| Related | relation | Other Media List entries |
| 👨‍🎨 Artists | relation | **Primary creator field.** Links to bespoke artist/author pages in the Artists DB. |
| _Creators | multi_select | **Deprecated** — do not use. |

## `media-helper.sh`

Lives at `~/.claude/skills/notion-media/media-helper.sh`.
Requires `NOTION_TOKEN` in env (personal Notion integration token, connected to both Media List and Artists databases).

```bash
# Lookup
media-helper.sh find-entry <name>              # search Media List by title
media-helper.sh find-by-artist <name>          # search Media List entries by artist/author name
media-helper.sh find-artist <name>             # search Artists DB by name
media-helper.sh inspect <page-id>              # show type/tags/info/artists/archived for an entry
media-helper.sh list-options <field>           # list select/multi_select options (Tags, From, Type, Status, Rating)

# Edit entries
media-helper.sh rename <page-id> <new-name>    # rename an entry
media-helper.sh set-info <page-id> <url|null>  # set Info URL
media-helper.sh set-tags <page-id> t1 [t2...]  # replace all tags
media-helper.sh add-tags <page-id> t1 [t2...]  # append tags (read-modify-write)
media-helper.sh link <page-id-a> <page-id-b>   # bidirectional Related relation
media-helper.sh link-artist <entry-id> <artist-id>  # add artist relation (read-modify-write)
media-helper.sh unarchive <page-id>            # unarchive a page
media-helper.sh archive <page-id>             # archive a page
media-helper.sh add-option <field> <name>      # add new multi_select option (USER PERMISSION REQUIRED)

# Artists
media-helper.sh create-artist <name>           # create a new artist page and print its ID

# Sort state
media-helper.sh state-scan                     # check all sort-state entries for archived status
media-helper.sh state-remove <page-id>         # remove a page ID from all locations in state
```

## Adding a new entry: workflow

1. **Check for duplicates** — `media-helper.sh find-entry "<name>"`
2. **Remind about sorting** — new entries have no priority and will appear in the unsorted queue next time the user runs `notion-media-sort`.
3. **Resolve creator** — `media-helper.sh find-artist "<name>"`. If not found, `create-artist "<name>"` (no permission needed — artist pages are not a shared ontology).
4. **Pick Tags** — `media-helper.sh list-options Tags`. Prefer existing. Do NOT create new ones without asking.
5. **Resolve From** — check `media-helper.sh list-options From`. If the person is new, ask user before adding.
6. **Create the entry** via `curl POST /v1/pages` with `parent.database_id`, all properties, and `👨‍🎨 Artists` relation set to the artist page ID.
7. **Return the page URL** so the user can review.

## RULE: new Tags/From options require user permission

Do not create new Tags or From values without asking first. Artist pages are fine to create without asking.

## RULE: Fiction / Non-fiction is required on every Book entry

Every Book entry **must** have either `Fiction` or `Non-fiction` in its Tags. Apply this when creating a new book or editing an existing one. Both options already exist as tag options in the DB. This is critical for the `notion-media-sort` tool, which lets the user filter by Fiction vs Non-fiction.

## curl patterns

All calls use `Authorization: Bearer $NOTION_TOKEN` and `Notion-Version: 2022-06-28`.

### Create a Media List entry
```bash
curl -fsS -X POST "https://api.notion.com/v1/pages" \
  -H "Authorization: Bearer $NOTION_TOKEN" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d '{
    "parent": {"database_id": "ec9650e3-40fe-4cac-977b-a37e7b34d22e"},
    "properties": {
      "Name":           {"title": [{"text": {"content": "A Fine Balance"}}]},
      "Type":           {"select": {"name": "Book"}},
      "Status":         {"select": {"name": "To Do"}},
      "Tags":           {"multi_select": [{"name": "Literature"}, {"name": "Fiction"}]},
      "From":           {"multi_select": [{"name": "Cheryl"}]},
      "Info":           {"url": "https://en.wikipedia.org/wiki/A_Fine_Balance"},
      "👨‍🎨 Artists":  {"relation": [{"id": "<artist-page-id>"}]}
    }
  }'
```
