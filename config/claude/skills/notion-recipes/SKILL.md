---
name: notion-recipes
description: Use this skill when adding, querying, or updating recipes in Cay's Notion (the `notion-wife` MCP, OR the OAuth `mcp__notion__*` MCP when $USER is cay). Covers the Recipes data source schema, tag conventions, the `recipes-helper.sh` script for fast tag/recipe operations via curl, and the rule that new tags must be confirmed with the user before creation.
---

# Cay's Notion Recipes

For working with Cayleigh's Notion workspace. Pair with **notion-rest-tricks** for the underlying API patterns when using the token-based MCP.

## Which MCP to use

- **If `$USER` is `cay`**: she connects to her own Notion via the **OAuth** `mcp__notion__*` server. Use those tools (`mcp__notion__notion-search`, `notion-fetch`, `notion-create-pages`, `notion-update-page`, `notion-create-comment`, etc.). The schema, tag conventions, and "ask before creating new tags" rule below all still apply — only the transport changes.
- **Otherwise** (e.g. Alex driving from his account): use the token-based `mcp__notion-wife__API-*` MCP and `recipes-helper.sh` (which depends on `NOTION_TOKEN_WIFE`).

The schema/tag/workflow content below is workspace-specific and applies regardless of transport. Tool-name examples are written for the token MCP; translate to OAuth equivalents when `$USER=cay`. The `recipes-helper.sh` script and `notion-rest-tricks` skill are token-only — skip them under OAuth.

## The Recipes database

| Field | Type | Notes |
|---|---|---|
| `database_id` | — | `9730ecb7-e605-4da8-989c-5e95edd423fa` |
| `data_source_id` | — | `8ed55d29-7075-4df6-afcf-f49acd9f72a3` |
| URL | — | https://www.notion.so/9730ecb7e6054da8989c5e95edd423fa |

| Property | Type | Notes |
|---|---|---|
| `Name` | title | Recipe name |
| `Tags` | multi_select | Cuisine, ingredients, meal type, cocktail spirits, etc. ~200 options. |
| `Status` | select | `To do`, `Done`, `Make Again` |
| `Rating` | number | Plain number (no star format) |
| `Link` | url | Source URL |
| `Comments` | rich_text | Short notes — body content goes in page children |
| `Recipe Cooked` | checkbox | |
| `Related Recipes` / `Related back to Recipes` | relation | Dual-property self-relation |

Body content is page block children (ingredients as `bulleted_list_item`, instructions as paragraphs or numbered lists). Set Comments only for short metadata; put the recipe itself in the body.

## Tag conventions

Tags fall into rough buckets — pick liberally from existing tags. Common groupings observed:

- **Course**: Dessert, Dinner, Lunch, Snack, Side, Appetizer, Sandwich, Soup, Stew, Salad, Wrap
- **Difficulty / time**: Easy, Slow, Cold
- **Cuisine**: Korean, Japanese, Russian, Canadian, Swiss, Indian, Malaysian, Thai, Chinese, Mexican, Spanish, Caribbean
- **Protein**: Chicken, Beef, Pork, Fish, Tuna, Salmon, Crab, Shrimp, Tofu, Egg, Ground Meat, Sausage, Turkey, Steak, Bacon, Ham, Wings
- **Veg / produce**: Potatoe, Carrots, Beets, Cabbage, Cucumber, Spinach, Zucchini, Cauliflower, Broccoli, Tomato, Onion, Garlic, Avocado, Mushroom, Asparagus, Eggplant, Lettuce, Endive, Sprouts, Corn, Leek, Celery, Beans, Chickpea, Lentils, Edamame
- **Dairy**: Cheese, Feta, Brie, Cottage Cheese, Yogurt, Quark, Goat, Cream, Ricotta, Milk
- **Cocktail**: Cocktail, shaken, plus spirit/ingredient tags (Mezcal, tequila, Whiskey, Aperol, Campari, sweet/dry vermouth, Lillet/Cocchi, Chartreuse, St-Germain, Benedictine, Frangelico, Absinthe, Orange Liqueur, Angostura, Egg white, Donn's Mix #1, Death and Co, …)
- **Other**: Recipe, Resource, Basics, Christmas, Summer, BBQ, Baking, Marinade, Dressing, Sauce, Pesto

Be aware some tags have typos (`Potatoe`, `Alochol`, `suace`). Use them as-is — don't rename them; that risks losing the relation on existing recipes.

## **RULE: don't use the `Made` tag**

**Do not add the `Made` tag to recipes.** To mark a recipe as cooked, set the `Recipe Cooked` checkbox property to true instead.

- **Why**: `Made` and `Recipe Cooked` are redundant; Cay tracks cooked-status via the checkbox, and the tag is legacy/noise. Per-user preference (Cay, 2026-05-07).
- **How to apply**: When tagging a recipe Cay has cooked, omit `Made` from the Tags list and set `Recipe Cooked: __YES__` (token API) / `"Recipe Cooked": "__YES__"` (OAuth update_properties). Same applies to retroactive cleanup if you spot `Made` on a recipe you're editing — drop it.

## **RULE: new tags require user permission**

**Do not create new tags without asking the user first.** Assigning *existing* tags to recipes is fine.

- **Why**: New tags expand a shared ontology. Cay curates this; ad-hoc additions create duplicates ("Lime" vs "Limes"), typos, and ontology drift. The user wants final say on what gets added to the canonical list.
- **How to apply**: Before any `multi_select` write that includes an unknown option, pause and confirm with the user. If they approve, prefer `recipes-helper.sh add-tag` (which preserves the existing list — see "Common pitfall" in notion-rest-tricks).

If a tag *almost* matches an existing one (e.g. you want "Lime" and "Lime" already exists), use the existing one. Use `recipes-helper.sh list-tags <substring>` to check before assuming a tag is missing.

## `recipes-helper.sh`

Lives at `~/.claude/skills/notion-recipes/recipes-helper.sh` (symlinked from this dotfile). Hits the Notion REST API directly via `curl + jq`, much smaller responses than MCP for tag/recipe lookups.

Requires `NOTION_TOKEN_WIFE` in env. Commands:

```bash
recipes-helper.sh list-tags [substring]    # all tags, optionally filtered (case-insensitive)
recipes-helper.sh find-recipe <substring>  # search recipes by Name (returns id + title)
recipes-helper.sh show-recipe <page-id>    # print page body as plain text
recipes-helper.sh add-tag <name> [color]   # add new tag (USER PERMISSION REQUIRED FIRST)
```

`add-tag` performs a safe read-modify-write: fetches current options, appends the new one with the chosen color, and PATCHes the data source. This avoids the wipe-existing-tags trap when using `update-data-source` directly.

Color must be one of: `default, gray, brown, orange, yellow, green, blue, purple, pink, red`.

## Workflow: adding a recipe

### Token MCP (Alex / non-cay user)

1. **Search first** — `recipes-helper.sh find-recipe <name>` to confirm it doesn't already exist.
2. **Pick tags** — start from the conventions above; use `list-tags <substring>` to verify spellings. If a needed tag is missing, **stop and ask the user** before adding.
3. **Create the page** via `mcp__notion-wife__API-post-page` with parent `{type: "database_id", database_id: "9730ecb7-e605-4da8-989c-5e95edd423fa"}`, an emoji icon, Name + Tags + (optionally Link, Status).
4. **Append the body** via `mcp__notion-wife__API-patch-block-children` — ingredients as `bulleted_list_item`, method as bullets or paragraphs, notes section at the end.
5. **Return the URL** so the user can review/edit.

### OAuth MCP (`$USER=cay`)

1. **Search first** — `mcp__notion__notion-search` for the recipe name to confirm it doesn't already exist. To list/check existing tags, `mcp__notion__notion-fetch` the Recipes data source URL/ID and inspect the `Tags` schema (or use the search-within-data-source flow).
2. **Pick tags** — same conventions as above. If a needed tag is missing, **stop and ask the user** before adding (and use `mcp__notion__notion-update-data-source` with the *full* options list to add it — same wipe-existing-tags trap as the token API).
3. **Create the page** via `mcp__notion__notion-create-pages` with the Recipes data source as parent. The OAuth server accepts Markdown-frontmatter style properties — set Name, Tags, Link, Status there.
4. **Body content** can be passed as Markdown in the same `notion-create-pages` call (the OAuth server speaks Notion-flavoured Markdown), or appended afterward with `notion-update-page`.
5. **Return the URL** so the user can review/edit.
