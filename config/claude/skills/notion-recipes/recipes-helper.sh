#!/usr/bin/env bash
# Helpers for Cay's Notion Recipes database.
# Hits the Notion REST API directly using NOTION_TOKEN_WIFE — much smaller
# responses than the MCP wrapper for common tag / recipe lookups.
#
# Commands:
#   list-tags [substring]          # all multi-select Tag options, optionally filtered
#   find-recipe <substring>        # search Recipes by Name (case-insensitive contains)
#   show-recipe <page-id>          # dump page body as plain text
#   add-tag <name> [color]         # add a new Tag option (USER PERMISSION REQUIRED FIRST)
#
# Env:
#   NOTION_TOKEN_WIFE              # required — bot token for Cay's workspace
#   RECIPES_DATA_SOURCE_ID         # optional override (default: hardcoded)
#   RECIPES_DATABASE_ID            # optional override

set -euo pipefail

DATA_SOURCE_ID="${RECIPES_DATA_SOURCE_ID:-8ed55d29-7075-4df6-afcf-f49acd9f72a3}"
DATABASE_ID="${RECIPES_DATABASE_ID:-9730ecb7-e605-4da8-989c-5e95edd423fa}"
NOTION_VERSION="2025-09-03"

if [[ -z "${NOTION_TOKEN_WIFE:-}" ]]; then
  echo "error: NOTION_TOKEN_WIFE not set" >&2
  exit 1
fi

api() {
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -fsS -X "$method" "https://api.notion.com/v1$path" \
      -H "Authorization: Bearer $NOTION_TOKEN_WIFE" \
      -H "Notion-Version: $NOTION_VERSION" \
      -H "Content-Type: application/json" \
      -d "$body"
  else
    curl -fsS -X "$method" "https://api.notion.com/v1$path" \
      -H "Authorization: Bearer $NOTION_TOKEN_WIFE" \
      -H "Notion-Version: $NOTION_VERSION"
  fi
}

usage() {
  sed -n '4,15p' "$0" >&2
  exit 1
}

cmd="${1:-}"
[[ -z "$cmd" ]] && usage
shift || true

case "$cmd" in
  list-tags)
    filter="${1:-}"
    api GET "/data_sources/$DATA_SOURCE_ID" \
      | jq -r --arg f "$(printf '%s' "$filter" | tr '[:upper:]' '[:lower:]')" '
          .properties.Tags.multi_select.options[]
          | select($f == "" or ((.name | ascii_downcase) | contains($f)))
          | "\(.color)\t\(.name)"
        ' \
      | column -t -s $'\t'
    ;;

  find-recipe)
    q="${1:?Usage: find-recipe <substring>}"
    body="$(jq -nc --arg q "$q" \
      '{filter: {property: "Name", title: {contains: $q}}, page_size: 25}')"
    api POST "/data_sources/$DATA_SOURCE_ID/query" "$body" \
      | jq -r '.results[]
          | "\(.id)\t\((.properties.Name.title // []) | map(.plain_text) | join(""))"' \
      | column -t -s $'\t'
    ;;

  show-recipe)
    id="${1:?Usage: show-recipe <page-id>}"
    api GET "/blocks/$id/children?page_size=100" \
      | jq -r '
          .results[]
          | (.[.type] // {}) as $b
          | (($b.rich_text // []) | map(.plain_text) | join("")) as $t
          | if   .type == "heading_1"          then "# \($t)"
            elif .type == "heading_2"          then "## \($t)"
            elif .type == "heading_3"          then "### \($t)"
            elif .type == "bulleted_list_item" then "  - \($t)"
            elif .type == "numbered_list_item" then "  1. \($t)"
            elif .type == "to_do"              then "  [ ] \($t)"
            elif .type == "paragraph"          then "\($t)"
            elif .type == "quote"              then "> \($t)"
            elif .type == "code"               then "```\n\($t)\n```"
            else "[\(.type)] \($t)"
            end'
    ;;

  add-tag)
    name="${1:?Usage: add-tag <name> [color]}"
    color="${2:-default}"
    case "$color" in
      default|gray|brown|orange|yellow|green|blue|purple|pink|red) ;;
      *) echo "error: invalid color '$color' (must be default|gray|brown|orange|yellow|green|blue|purple|pink|red)" >&2; exit 2 ;;
    esac
    current="$(api GET "/data_sources/$DATA_SOURCE_ID" \
      | jq '[.properties.Tags.multi_select.options[] | {name, color}]')"
    if jq -e --arg n "$name" 'any(.name == $n)' <<<"$current" >/dev/null; then
      echo "Tag '$name' already exists; assign it directly." >&2
      exit 0
    fi
    new="$(jq --arg n "$name" --arg c "$color" '. + [{name: $n, color: $c}]' <<<"$current")"
    body="$(jq -nc --argjson opts "$new" \
      '{properties: {Tags: {multi_select: {options: $opts}}}}')"
    api PATCH "/data_sources/$DATA_SOURCE_ID" "$body" \
      | jq -r '.properties.Tags.multi_select.options | length as $n | "OK — Tags now has \($n) options"'
    ;;

  *)
    echo "error: unknown command '$cmd'" >&2
    usage
    ;;
esac
