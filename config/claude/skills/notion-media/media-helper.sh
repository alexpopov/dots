#!/usr/bin/env bash
# Notion Media List helper — bypasses MCP for lightweight field/option operations.
# Requires: NOTION_TOKEN env var (personal Notion integration token)

set -euo pipefail

DB_ID="ec9650e3-40fe-4cac-977b-a37e7b34d22e"
ARTISTS_DB_ID="e40a874d-0d69-4fac-b6b6-abfa2bae0703"
NOTION_VERSION="2022-06-28"
BASE="https://api.notion.com/v1"

: "${NOTION_TOKEN:?NOTION_TOKEN is not set. See SKILL.md for setup instructions.}"

_api() {
  local method="$1" path="$2"; shift 2
  curl -fsS -X "$method" "$BASE$path" \
    -H "Authorization: Bearer $NOTION_TOKEN" \
    -H "Notion-Version: $NOTION_VERSION" \
    -H "Content-Type: application/json" \
    "$@"
}

_db_schema() {
  _api GET "/databases/$DB_ID"
}

cmd_list_options() {
  local field="${1:?Usage: list-options <field>}"
  local schema
  schema=$(_db_schema)

  local type
  type=$(echo "$schema" | jq -r --arg f "$field" '.properties[$f].type // empty')
  if [[ -z "$type" ]]; then
    echo "Field '$field' not found. Available fields:" >&2
    echo "$schema" | jq -r '.properties | keys[]' >&2
    exit 1
  fi

  if [[ "$type" == "select" || "$type" == "multi_select" ]]; then
    local filter="${2:-}"
    if [[ -n "$filter" ]]; then
      echo "$schema" | jq -r --arg f "$field" --arg t "$type" --arg q "$filter" \
        '.properties[$f][$t].options[].name | select(ascii_downcase | contains($q | ascii_downcase))'
    else
      echo "$schema" | jq -r --arg f "$field" --arg t "$type" \
        '.properties[$f][$t].options[].name'
    fi
  else
    echo "Field '$field' is type '$type', not select/multi_select." >&2
    exit 1
  fi
}

cmd_find_entry() {
  local query="${1:?Usage: find-entry <name>}"
  local body
  body=$(jq -n --arg q "$query" '{
    "filter": {"property": "Name", "title": {"contains": $q}},
    "page_size": 10
  }')
  _api POST "/databases/$DB_ID/query" -d "$body" \
    | jq -r '.results[] | "\(.id)  \(.properties.Name.title[0].text.content // "(untitled)")"'
}

cmd_add_option() {
  local field="${1:?Usage: add-option <field> <name> [color]}"
  local name="${2:?Usage: add-option <field> <name> [color]}"
  local color="${3:-default}"

  local valid_colors="default gray brown orange yellow green blue purple pink red"
  if ! echo "$valid_colors" | grep -qw "$color"; then
    echo "Invalid color '$color'. Choose from: $valid_colors" >&2
    exit 1
  fi

  local schema
  schema=$(_db_schema)

  local type
  type=$(echo "$schema" | jq -r --arg f "$field" '.properties[$f].type // empty')
  if [[ -z "$type" ]]; then
    echo "Field '$field' not found." >&2
    exit 1
  fi
  if [[ "$type" != "select" && "$type" != "multi_select" ]]; then
    echo "Field '$field' is type '$type', not select/multi_select." >&2
    exit 1
  fi

  # Check if it already exists
  if echo "$schema" | jq -e --arg f "$field" --arg t "$type" --arg n "$name" \
      '.properties[$f][$t].options[] | select(.name == $n)' > /dev/null 2>&1; then
    echo "Option '$name' already exists in $field."
    exit 0
  fi

  # Read existing options, append new one
  local existing_options new_options patch_body
  existing_options=$(echo "$schema" | jq --arg f "$field" --arg t "$type" \
    '[.properties[$f][$t].options[] | {name: .name, color: .color}]')

  new_options=$(echo "$existing_options" | jq --arg n "$name" --arg c "$color" \
    '. + [{"name": $n, "color": $c}]')

  patch_body=$(jq -n --arg f "$field" --arg t "$type" --argjson opts "$new_options" \
    '{"properties": {($f): {($t): {"options": $opts}}}}')

  _api PATCH "/databases/$DB_ID" -d "$patch_body" \
    | jq -r '"Added \(.properties[$field][$type].options[-1].name) to \($field)"' \
      --arg field "$field" --arg type "$type" 2>/dev/null \
    || echo "Done — option '$name' added to $field."
}

cmd_link() {
  local id_a="${1:?Usage: link <page-id-a> <page-id-b>}"
  local id_b="${2:?Usage: link <page-id-a> <page-id-b>}"
  # Add each page to the other's Related field (read-modify-write to preserve existing)
  for pair in "$id_a:$id_b" "$id_b:$id_a"; do
    local src="${pair%%:*}" tgt="${pair##*:}"
    local current existing body
    current=$(_api GET "/pages/$src")
    existing=$(echo "$current" | jq '[.properties.Related.relation[].id]')
    # skip if already linked
    if echo "$existing" | jq -e --arg t "$tgt" 'any(. == $t)' > /dev/null 2>&1; then
      echo "Already linked: $src → $tgt"
      continue
    fi
    body=$(jq -n --argjson ex "$existing" --arg t "$tgt" \
      '{"properties": {"Related": {"relation": ($ex + [$t] | map({id: .}))}}}')
    _api PATCH "/pages/$src" -d "$body" | jq -r '"Linked: \(.id)"'
  done
}

cmd_rename() {
  local id="${1:?Usage: rename <page-id> <new-name>}"
  local name="${2:?Usage: rename <page-id> <new-name>}"
  _api PATCH "/pages/$id" -d "$(jq -n --arg n "$name" \
    '{"properties": {"Name": {"title": [{"text": {"content": $n}}]}}}')" \
    | jq -r '"Renamed to: \(.properties.Name.title[0].text.content)"'
}

cmd_find_by_artist() {
  local query="${1:?Usage: find-by-artist <name>}"
  # First find matching artist page IDs
  local body results
  body=$(jq -n --arg q "$query" '{
    "filter": {"property": "Name", "title": {"contains": $q}},
    "page_size": 10
  }')
  results=$(_api POST "/databases/$ARTISTS_DB_ID/query" -d "$body")
  local count
  count=$(echo "$results" | jq '.results | length')
  if [[ "$count" -eq 0 ]]; then
    echo "No artist matching '$query' found." >&2
    exit 0
  fi
  # For each artist, query Media List entries linked to them
  echo "$results" | jq -r '.results[] | "\(.id)\t\(.properties.Name.title[0].text.content)"' | \
  while IFS=$'\t' read -r artist_id artist_name; do
    local entries_body
    entries_body=$(jq -n --arg id "$artist_id" '{
      "filter": {"property": "👨‍🎨 Artists", "relation": {"contains": $id}},
      "page_size": 20
    }')
    _api POST "/databases/$DB_ID/query" -d "$entries_body" \
      | jq -r --arg a "$artist_name" \
        '.results[] | "[\($a)]  \(.properties.Name.title[0].text.content // "(untitled)")  [\(.properties.Type.select.name // "?")]  \(.properties.Status.select.name // "?")"'
  done
}

cmd_find_artist() {
  local query="${1:?Usage: find-artist <name>}"
  local body
  body=$(jq -n --arg q "$query" '{
    "filter": {"property": "Name", "title": {"contains": $q}},
    "page_size": 10
  }')
  _api POST "/databases/$ARTISTS_DB_ID/query" -d "$body" \
    | jq -r '.results[] | "\(.id)  \(.properties.Name.title[0].text.content // "(untitled)")"'
}

cmd_create_artist() {
  local name="${1:?Usage: create-artist <name>}"
  local body
  body=$(jq -n --arg n "$name" --arg db "$ARTISTS_DB_ID" '{
    "parent": {"database_id": $db},
    "properties": {"Name": {"title": [{"text": {"content": $n}}]}}
  }')
  _api POST "/pages" -d "$body" | jq -r '.id'
}

cmd_inspect() {
  local id="${1:?Usage: inspect <page-id>}"
  _api GET "/pages/$id" | jq '{
    id: .id,
    archived: .archived,
    name: .properties.Name.title[0].text.content,
    type: .properties.Type.select.name,
    status: .properties.Status.select.name,
    tags: [.properties.Tags.multi_select[].name],
    info: .properties.Info.url,
    priority: .properties.Priority.number,
    artists: [.properties["👨‍🎨 Artists"].relation[].id]
  }'
}

cmd_unarchive() {
  local id="${1:?Usage: unarchive <page-id>}"
  _api PATCH "/pages/$id" -d '{"archived": false}' \
    | jq -r '"Unarchived: \(.id)  \(.properties.Name.title[0].text.content // "(untitled)")"'
}

cmd_archive() {
  local id="${1:?Usage: archive <page-id>}"
  _api PATCH "/pages/$id" -d '{"archived": true}' \
    | jq -r '"Archived: \(.id)  \(.properties.Name.title[0].text.content // "(untitled)")"'
}

cmd_set_info() {
  local id="${1:?Usage: set-info <page-id> <url|null>}"
  local url="${2:?Usage: set-info <page-id> <url|null>}"
  local body
  if [[ "$url" == "null" ]]; then
    body='{"properties": {"Info": {"url": null}}}'
  else
    body=$(jq -n --arg u "$url" '{"properties": {"Info": {"url": $u}}}')
  fi
  _api PATCH "/pages/$id" -d "$body" \
    | jq -r '"Info set: \(.properties.Info.url)"'
}

# Usage: set-tags <page-id> tag1 [tag2 ...]  — replaces all tags
cmd_set_tags() {
  local id="${1:?Usage: set-tags <page-id> tag1 [tag2 ...]}"
  shift
  local tags_json
  tags_json=$(printf '%s\n' "$@" | jq -Rc '{"name": .}' | jq -sc '.')
  _api PATCH "/pages/$id" \
    -d "$(jq -n --argjson t "$tags_json" '{"properties": {"Tags": {"multi_select": $t}}}')" \
    | jq -r '"Tags: \([.properties.Tags.multi_select[].name] | join(", "))"'
}

# Usage: add-tags <page-id> tag1 [tag2 ...]  — appends without removing existing
cmd_add_tags() {
  local id="${1:?Usage: add-tags <page-id> tag1 [tag2 ...]}"
  shift
  local current existing new_tags body
  current=$(_api GET "/pages/$id")
  existing=$(echo "$current" | jq '[.properties.Tags.multi_select[].name]')
  new_tags=$(printf '%s\n' "$@" | jq -Rc '.' | jq -sc --argjson ex "$existing" \
    '$ex + . | unique | map({name: .})')
  body=$(jq -n --argjson t "$new_tags" '{"properties": {"Tags": {"multi_select": $t}}}')
  _api PATCH "/pages/$id" -d "$body" \
    | jq -r '"Tags: \([.properties.Tags.multi_select[].name] | join(", "))"'
}

# Usage: link-artist <entry-id> <artist-id>  — adds artist without removing existing
cmd_link_artist() {
  local entry_id="${1:?Usage: link-artist <entry-id> <artist-id>}"
  local artist_id="${2:?Usage: link-artist <entry-id> <artist-id>}"
  local current existing body
  current=$(_api GET "/pages/$entry_id")
  existing=$(echo "$current" | jq '[.properties["👨‍🎨 Artists"].relation[].id]')
  if echo "$existing" | jq -e --arg a "$artist_id" 'any(. == $a)' > /dev/null 2>&1; then
    echo "Already linked."
    return 0
  fi
  body=$(jq -n --argjson ex "$existing" --arg a "$artist_id" \
    '{"properties": {"👨‍🎨 Artists": {"relation": ($ex + [$a] | map({id: .}))}}}')
  _api PATCH "/pages/$entry_id" -d "$body" \
    | jq -r '"Artists: \([.properties["👨‍🎨 Artists"].relation[].id] | join(", "))"'
}

STATE_PATH="${HOME}/.local/share/notion-media-sort/state.json"

# Scan sort state for archived entries; prints any found
cmd_state_scan() {
  [[ -f "$STATE_PATH" ]] || { echo "State file not found: $STATE_PATH" >&2; exit 1; }
  local ids
  ids=$(python3 - <<'PY'
import json, sys
with open(__import__('os').path.expanduser("~/.local/share/notion-media-sort/state.json")) as f:
    s = json.load(f)
ids = set()
for pid in s.get("unsorted", []): ids.add(pid)
for lst in s.get("sorted_by_type", {}).values():
    for pid in lst: ids.add(pid)
c = s.get("current")
if c and c.get("item"): ids.add(c["item"])
print("\n".join(ids))
PY
)
  local total
  total=$(echo "$ids" | wc -l | tr -d ' ')
  echo "Scanning $total entries…"
  local found=0
  while IFS= read -r pid; do
    local result archived name
    result=$(_api GET "/pages/$pid" 2>/dev/null) || { echo "  API ERROR: $pid"; continue; }
    archived=$(echo "$result" | jq -r '.archived')
    name=$(echo "$result" | jq -r '.properties.Name.title[0].text.content // "(untitled)"')
    if [[ "$archived" == "true" ]]; then
      echo "  ARCHIVED: $pid  $name"
      found=$((found + 1))
    fi
  done <<< "$ids"
  [[ "$found" -eq 0 ]] && echo "All clean." || echo "$found archived entry/entries found."
}

# Remove a page ID from all locations in the sort state
cmd_state_remove() {
  local id="${1:?Usage: state-remove <page-id>}"
  [[ -f "$STATE_PATH" ]] || { echo "State file not found: $STATE_PATH" >&2; exit 1; }
  python3 - "$id" <<'PY'
import json, sys, os
pid = sys.argv[1]
path = os.path.expanduser("~/.local/share/notion-media-sort/state.json")
with open(path) as f: state = json.load(f)
removed = []
before = len(state.get("unsorted", []))
state["unsorted"] = [p for p in state.get("unsorted", []) if p != pid]
if len(state["unsorted"]) < before: removed.append("unsorted")
for t, lst in state.get("sorted_by_type", {}).items():
    before2 = len(lst)
    state["sorted_by_type"][t] = [p for p in lst if p != pid]
    if len(state["sorted_by_type"][t]) < before2: removed.append(f"sorted_by_type[{t}]")
c = state.get("current")
if c and c.get("item") == pid:
    state["current"] = None
    removed.append("current")
with open(path, "w") as f: json.dump(state, f, indent=2)
print(f"Removed from: {', '.join(removed) if removed else 'nowhere (not found)'}")
PY
}

usage() {
  cat >&2 <<'EOF'
Usage: media-helper.sh <command> [args]

Lookup
  find-entry <name>                  Search Media List entries by title
  find-by-artist <name>              Search Media List entries by artist/author name
  find-artist <name>                 Search Artists database by name
  inspect <page-id>                  Show key properties of a Media List entry
  list-options <field> [substr]      List select/multi_select options (Tags, From, Type, Status, Rating)

Edit entries
  rename <page-id> <new-name>        Rename an entry
  set-info <page-id> <url|null>      Set the Info URL
  set-tags <page-id> tag1 [tag2...]  Replace all tags
  add-tags <page-id> tag1 [tag2...]  Append tags (read-modify-write)
  link <page-id-a> <page-id-b>       Bidirectional Related relation
  link-artist <entry-id> <artist-id> Add an artist relation (read-modify-write)
  unarchive <page-id>                Unarchive a page
  archive <page-id>                  Archive a page
  add-option <field> <name> [color]  Add a new multi_select option (USER PERMISSION REQUIRED)

Artists
  create-artist <name>               Create a new artist page, prints its ID

Sort state (~/.local/share/notion-media-sort/state.json)
  state-scan                         Check all state entries for archived status
  state-remove <page-id>             Remove a page ID from all state locations

Requires NOTION_TOKEN env var. See SKILL.md for setup.
EOF
  exit 1
}

case "${1:-}" in
  list-options)   shift; cmd_list_options "$@" ;;
  find-entry)      shift; cmd_find_entry "$@" ;;
  find-by-artist)  shift; cmd_find_by_artist "$@" ;;
  inspect)         shift; cmd_inspect "$@" ;;
  rename)          shift; cmd_rename "$@" ;;
  set-info)        shift; cmd_set_info "$@" ;;
  set-tags)        shift; cmd_set_tags "$@" ;;
  add-tags)        shift; cmd_add_tags "$@" ;;
  link)            shift; cmd_link "$@" ;;
  link-artist)     shift; cmd_link_artist "$@" ;;
  unarchive)       shift; cmd_unarchive "$@" ;;
  archive)         shift; cmd_archive "$@" ;;
  find-artist)     shift; cmd_find_artist "$@" ;;
  create-artist)  shift; cmd_create_artist "$@" ;;
  add-option)     shift; cmd_add_option "$@" ;;
  state-scan)      shift; cmd_state_scan "$@" ;;
  state-remove)    shift; cmd_state_remove "$@" ;;
  *)              usage ;;
esac
