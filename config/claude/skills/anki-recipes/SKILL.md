---
name: anki-recipes
description: Use this skill when adding, querying, or updating cards in Alp's Anki collection — especially the German "Deutsch: 4000 German Words by Frequency" deck. Covers the custom Grammar/Notes/Conjugation fields and their card templates, the anki MCP workflow, the schema-change → full-sync gotcha, the HTML/CSS conventions, and the content style for grammar notes.
---

# Alp's Anki

For reading and enriching cards in Alp's Anki collection via the **`mcp__anki__*`** MCP server (a wrapper around the AnkiConnect add-on). Anki **desktop must be running** with AnkiConnect installed, or every call fails.

The anki MCP tools are **deferred** — load schemas with `ToolSearch` before calling, e.g.
`ToolSearch("select:mcp__anki__findNotes,mcp__anki__notesInfo,mcp__anki__updateNoteFields,mcp__anki__sync")`.
Commonly needed: `listDecks`, `modelNames`, `modelFieldNames`, `modelTemplates`, `modelStyling`, `findNotes`, `notesInfo`, `updateNoteFields`, `addModelField`, `updateModelTemplates`, `updateModelStyling`, `sync`.

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

**Content-only edits** (`updateNoteFields`) sync cleanly via `mcp__anki__sync`.

**Schema/structural changes** — `addModelField`, `updateModelTemplates`, adding a note type — bump the collection's schema time and force a **full one-way sync**. `mcp__anki__sync` then returns **`Sync status 2` (ChangesRequired)** and cannot proceed. Recovery, in order (avoids losing un-synced phone reviews):
1. **Alp syncs the iPhone first** (push its reviews to AnkiWeb).
2. Make the schema change on the Mac via MCP.
3. **Alp** opens Anki **desktop** → Sync → chooses **Upload to AnkiWeb**.
4. Alp re-syncs the phone to pull.

Always tell Alp this is coming *before* a schema change, and have him sync the phone first. The `Grammar`/`Notes`/`Conjugation` fields already exist, so routine verb/word enrichment is now content-only (no upload dance).

## Gotchas

- **`findNotes` over a whole deck can exceed the output token limit** — it saves to a file. Probe with `jq 'length' <file>` / extract IDs with `jq '.noteIds[0:3][]'` rather than reading raw; or hand it to a subagent.
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
