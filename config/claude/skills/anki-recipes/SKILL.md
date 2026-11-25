---
name: anki-recipes
description: 'Use this skill when adding, querying, or updating cards in Alp''s Anki collection — especially the German "Deutsch: 4000 German Words by Frequency" deck. Covers the custom Grammar/Notes/Conjugation fields and their card templates, the AnkiConnect helper script (anki.py), the schema-change → full-sync gotcha, the HTML/CSS conventions, and the content style for grammar notes.'
---

# Alp's Anki

For reading and enriching cards in Alp's Anki collection by talking to the **AnkiConnect** add-on directly (HTTP on `localhost:8765`) through **`anki.py`** in this skill's directory. No MCP server — it was removed in favour of this (full API, no connect timeouts). Anki **desktop must be running**; if a call gets "Connection refused", `open -a Anki` and retry for ~20 s.

```bash
A=~/.claude/skills/anki-recipes/anki.py
python3 -I $A sync
python3 -I $A notes 'German:einkaufen'                 # find + summarize notes in the German deck (fields, card due positions)
python3 -I $A notesInfo '{"notes":[1421053897312]}'    # any AnkiConnect action; params as a JSON arg…
python3 -I $A updateNoteFields <<'EOF'                 # …or on stdin — use this for HTML field content
{"note":{"id":1421053897312,"fields":{"Notes":"…"}}}
EOF
```

For multi-note edits, write a short Python script that does `sys.path.insert(0, os.path.expanduser("~/.claude/skills/anki-recipes")); from anki import call, DECK` and calls `call("updateNoteFields", note={...})`. Don't hand-build JSON in inline `curl` — the system bash is 3.2 and nested quoting breaks (Claude Code refuses some such commands outright). `python3 -I $A apiReflect '{"scopes":["actions"],"actions":null}'` lists every action the installed AnkiConnect supports.

## Profiles

Anki has separate profiles: **Alex** (Alp's — the deck below lives here) and **Cayleigh** (Cay's), plus Jayde. AnkiConnect only sees the **active** profile, so check before editing:

```bash
python3 -I $A getActiveProfile
python3 -I $A loadProfile '{"name":"Alex"}'
```

Switching triggers Anki's auto-sync for both profiles; an "Email or password was incorrect" popup comes from whichever profile isn't logged in — harmless to local edits.

## The German deck

- **Deck:** `Deutsch: 4000 German Words by Frequency`
- **Note type (model):** `Memrise - 4000 German Words by Frequency`
- Two card templates: **`English -> German`** and **`German -> English`** (each note makes 2 cards).
- Original Memrise fields (don't restructure these): `German`, `Picture`, `German Alternatives`/`Hidden`/`Typing Corrects`, `English` (+ same trio), `Plural and inflected forms` (+ trio), `Sample sentence` (+ trio), `Part of Speech`, `Audio`, `Level`, `Thing`.

### Custom fields added for this workflow (indices 21–23)

| Field | Renders as | Purpose |
|---|---|---|
| `Grammar` | **always-visible** callout box on the back | terse structured facts (case, prep type, principal parts) |
| `Conjugation` | **▸ Conjugation** collapsible (`<details>`), back only | verb paradigm as an HTML table |
| `Notes` | **▸ Notes** collapsible (`<details>`), back only | freeform prose explanation |

All three are wrapped in `{{#Field}}…{{/Field}}` conditionals, so a card with the field empty renders exactly as before — no clutter. Back-of-card order: **Grammar box → Conjugation → Notes**. Fronts were never modified.

## Enriching a card — the standard flow

1. **`sync`** first (pull latest; Alp reviews on iPhone).
2. **Find the card** — match the headword against the `German` field *exactly*:
   - `deck:"Deutsch: 4000 German Words by Frequency" German:werden` → exact field match.
   - `German:zum*` → prefix; a bare word (`German:ins`) returning 0 means the card doesn't exist.
   - A plain term (`copilot.microsoft.com`) is full-text across all fields.
3. **`notesInfo`** to read current field values (append to existing `Notes`, don't clobber).
4. **`updateNoteFields`** with only the fields you're changing.
5. **`sync`** again to push.

### Rules of engagement (learned from Alp's preferences)

- **Never create duplicate cards.** If the headword already exists (even niche ones like `sondern`, `nicht nur...sondern auch`, both `am` cards), enrich the existing note. Only create new notes when Alp explicitly asks — and confirm first, since content edits vs. note creation are different commitments.
- **Don't "litigate the cards"** — do **not** renumber or rewrite the `English` / `Part of Speech` / typing-corrects fields. They ripple into audio/typing expectations. Put clarifications in `Grammar`/`Notes` instead. (E.g. `zu`'s messy "1) to, at; 2) too / to" gloss was left alone; the 3-sense split went in Notes.)
- **Clean up Copilot links.** Early cards had `<a href="copilot.microsoft.com/...">` jammed into `Sample sentence`. Strip them and move any real content into `Notes`.
- **Watch phone line-wrapping.** A mid-phrase wrap can mislead (e.g. `ist geworden` looked like `ist` was a separate principal part). Keep multi-word units glued / labeled.

## Content conventions

- **Grammar** (plain text + light `<b>`/`<i>`): one or two dense lines. Lead with the caveat when a card invites overgeneralization (e.g. `im = in + dem only (dative m/n) — NOT a general "in the"`).
- **Notes** (HTML): use `<br/>` for line breaks, `<b>`/`<i>`, `&middot;` (·) as a separator, `&nbsp;&nbsp;` to indent. Be **accurate and honest** — if English can't disambiguate two words (auf vs an), say so and give the real cue (geometry: auf = horizontal top, an = vertical/edge).
- **Conjugation** (HTML table): pronouns down the side, tenses across the top. Standard template:

  ```html
  <table>
  <tr><th></th><th>Präsens</th><th>Präteritum</th><th>Konj. II</th></tr>
  <tr><td>ich</td><td>…</td><td>…</td><td>…</td></tr>
  <tr><td>du</td>…</tr>
  <tr><td>er/sie/es</td>…</tr>
  <tr><td>wir</td>…</tr>
  <tr><td>ihr</td>…</tr>
  <tr><td>sie/Sie</td>…</tr>
  </table>
  <b>Perfekt:</b> ist/hat …<br/>
  <b>Imperativ:</b> …! &middot; …! &middot; … Sie!
  ```
  Include Konjunktiv II (the würde-conditional) and note the perfect auxiliary (**sein** vs **haben**). **Whenever adding/enriching a verb, fill in this Conjugation table.**

## Sync rules & the schema-change gotcha

Anki syncs at the **object level**: reviewing a card (scheduling/revlog) and editing its fields (note object) are different objects, so a **normal sync merges both** — Alp's phone review progress and Mac content edits coexist with no conflict, no direction to pick.

**Content-only edits** (`updateNoteFields`) sync cleanly via `python3 -I $A sync`.

**Schema/structural changes** — `addModelField`, `updateModelTemplates`, adding a note type — bump the collection's schema time and force a **full one-way sync**. `sync` then errors (full sync required — the old MCP reported it as `Sync status 2` / ChangesRequired) and cannot proceed. Recovery, in order (avoids losing un-synced phone reviews):
1. **Alp syncs the iPhone first** (push its reviews to AnkiWeb).
2. Make the schema change on the Mac via `anki.py`.
3. **Alp** opens Anki **desktop** → Sync → chooses **Upload to AnkiWeb**.
4. Alp re-syncs the phone to pull.

Always tell Alp this is coming *before* a schema change, and have him sync the phone first. The `Grammar`/`Notes`/`Conjugation` fields already exist, so routine verb/word enrichment is now content-only (no upload dance).

## Gotchas

- **A whole-deck `findNotes`/`findCards` returns ~4000 IDs** — never print it raw; pipe through `jq 'length'` / `jq '.[0:3]'`, or do the filtering inside a Python script.
- **Moving new cards to the front can't be done via AnkiConnect.** There's no reposition action, and `setSpecificValueOfCard` on `due` is refused ("Use native scheduling commands for protected state"). `setDueDate "0"` would turn new cards into review cards (skipping learning steps) — don't. Instead open the browser on them (`guiBrowse '{"query":"…"}'`) and have Alp do ⌘A → Cards → Reposition (⌘⇧S). Previously front-loaded cards sit at low due numbers (~27–40) with both templates sharing a number; check with `is:new card:1` sorted by `due` and pick a start just below the lowest. (`forgetCards` doesn't help: it's a no-op on new cards and restores original positions anyway.)
- **Both directions are paired**: since 2026-11-23 each note's E→G and G→E new cards share the same `due` (the Memrise import had parked all G→E cards at +1,000,000). Keep it that way when repositioning — select both cards of a note.
- **Bulk position edits = direct SQLite, Anki closed** (done once for the pairing, worked cleanly): quit Anki → copy `~/Library/Application Support/Anki2/Alex/collection.anki2` to `~/Documents/Anki Backups/` → Python `sqlite3` (the `sqlite3` CLI can't open it here) → `db.create_collation("unicase", …)` first or touching `col` fails → set `due`, `mod=now`, `usn=-1` on changed cards **and** `update col set mod=<now ms>` so sync sees changes → reopen, `sync` (normal sync, no full upload for card-only edits).
- **Per-deck "This deck" limit overrides beat the preset** and AnkiConnect can neither read nor set them. If a new/review count doesn't match the preset's `perDay`, decode the deck's `kind` protobuf from the `decks` table (DeckKind.normal → field 7 `new_limit`, 6 `review_limit`, 8/9 the `*_today` variants; read a backup copy — the live DB is locked while Anki runs) or just have Alp check Deck Options → Daily Limits → "This deck" tab. Deutsch 4000 had `new_limit 7` (found 2026-11-23).
- **Deck presets**: Deutsch 4000 uses its own **German** preset (12 new/day = 6 words × 2 directions; Alp wants ~5–7 words/day); everything else is on **Default** (10/day). All non-German decks are suspended (archived for travel) — unsuspend per deck when needed.
- **Don't view a note in the Anki browser while `updateNoteFields` runs** — the update won't stick. Close the browser / switch notes first.
- `updateModelStyling` **replaces all CSS** — always pass the full stylesheet, not a fragment.

## Card template & CSS reference

Back-side blocks appended after the plural block (both templates):

```html
{{#Grammar}}<div class="grammar-note"><span class="label">Grammar:</span> {{Grammar}}</div>{{/Grammar}}
{{#Conjugation}}<details class="conj"><summary>Conjugation</summary><div class="conj-body">{{Conjugation}}</div></details>{{/Conjugation}}
{{#Notes}}<details class="notes"><summary>Notes</summary><div class="notes-body">{{Notes}}</div></details>{{/Notes}}
```

CSS classes in the model (with `.nightMode` variants for the phone): `.grammar-note` + `.grammar-note .label` (blue-tinted callout, left border); `.notes` / `.conj` + their `summary` (blue, bold, clickable) and `-body`; `.conj table th, td` (bordered, padded, 14px, header row tinted). If you ever need to rebuild them, `modelStyling` / `modelTemplates` return the current source.
