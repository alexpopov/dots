"""Remove 'f'/'fix' annotations from KOReader sidecar lua file.

Usage: python3 /tmp/clean_kobo_annotations.py [lua_file] [--dry-run]
"""
import re
import sys

DEFAULT_LUA = (
    "/Volumes/KOBOeReader/Borges, Jorge Luis/Collected Fictions/"
    "Collected Fictions - Jorge Luis Borges.sdr/metadata.epub.lua"
)

lua_path = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else DEFAULT_LUA
dry_run = "--dry-run" in sys.argv

with open(lua_path, "r", encoding="utf-8") as f:
    content = f.read()

# Split into annotations block and the rest
# Find the annotations array
annot_start = content.index('["annotations"] = {')
# Find matching closing brace — track nesting
depth = 0
i = content.index("{", annot_start)
for j in range(i, len(content)):
    if content[j] == "{":
        depth += 1
    elif content[j] == "}":
        depth -= 1
        if depth == 0:
            annot_end = j + 1
            break

before = content[:annot_start]
annot_block = content[annot_start:annot_end]
after = content[annot_end:]

# Parse individual entries
entries = re.split(r'\[(\d+)\] = \{', annot_block)
header = entries[0]  # '["annotations"] = {\n        '

# Rebuild entries: entries[1] = "1", entries[2] = content, entries[3] = "2", entries[4] = content...
kept = []
removed = []
for idx in range(1, len(entries), 2):
    entry_content = entries[idx + 1]
    note_m = re.search(r'\["note"\]\s*=\s*"([^"]*)"', entry_content)
    note = note_m.group(1) if note_m else ""

    if note.lower().startswith("f"):
        text_m = re.search(r'\["text"\]\s*=\s*"([^"]*)"', entry_content)
        text = text_m.group(1) if text_m else "?"
        removed.append(f"  [{note}] \"{text}\"")
    else:
        kept.append(entry_content)

print(f"Removing {len(removed)} annotations:")
for r in removed:
    print(r)
print(f"\nKeeping {len(kept)} annotations")

if dry_run:
    print("\n--dry-run: no changes written")
    sys.exit(0)

# Rebuild annotations block
new_annot = '["annotations"] = {\n'
for i, entry in enumerate(kept, 1):
    new_annot += f"        [{i}] = {{{entry}"
new_annot += "    }"

new_content = before + new_annot + after

with open(lua_path, "w", encoding="utf-8") as f:
    f.write(new_content)

print(f"\nWrote updated file to {lua_path}")
