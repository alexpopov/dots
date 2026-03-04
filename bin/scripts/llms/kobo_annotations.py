"""Extract fix annotations from KOReader sidecar lua file.

Usage: python3 /tmp/kobo_annotations.py [lua_file] [filter]

  lua_file  Path to metadata.epub.lua (default: Borges on Kobo)
  filter    Only show annotations whose note starts with this (default: "f")
"""
import re
import sys

DEFAULT_LUA = (
    "/Volumes/KOBOeReader/Borges, Jorge Luis/Collected Fictions/"
    "Collected Fictions - Jorge Luis Borges.sdr/metadata.epub.lua"
)

lua_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_LUA
note_filter = sys.argv[2] if len(sys.argv) > 2 else "f"

with open(lua_path) as f:
    content = f.read()

entries = re.split(r'\[\d+\] = \{', content)
for entry in entries[1:]:
    note_m = re.search(r'\["note"\]\s*=\s*"([^"]*?)"', entry)
    if not note_m:
        continue
    note = note_m.group(1)
    if not note.lower().startswith(note_filter.lower()):
        continue
    chapter_m = re.search(r'\["chapter"\]\s*=\s*"([^"]*?)"', entry)
    text_m = re.search(r'\["text"\]\s*=\s*"([^"]*?)"', entry)
    chapter = chapter_m.group(1) if chapter_m else "?"
    text = text_m.group(1) if text_m else "?"
    print(f'{chapter}: [{note}] "{text}"')
