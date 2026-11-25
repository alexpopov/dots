#!/usr/bin/env python3
"""Minimal AnkiConnect client (Anki desktop must be running).

CLI:  anki.py ACTION ['{"param": ...}']     params as JSON arg, or on stdin
      anki.py notes 'German:einkaufen'      shortcut: find + summarize notes in the German deck
Lib:  sys.path.insert(0, SKILL_DIR); from anki import call, DECK
"""
import json, sys, urllib.request

URL = "http://localhost:8765"
DECK = 'deck:"Deutsch: 4000 German Words by Frequency"'


def call(action, **params):
    req = json.dumps({"action": action, "version": 6, "params": params}).encode()
    r = json.load(urllib.request.urlopen(URL, req))
    if r["error"]:
        raise SystemExit(f"{action}: {r['error']}")
    return r["result"]


def notes(query):
    """Print the fields that matter for every matching note in the German deck, plus card queue positions."""
    nids = call("findNotes", query=f"{DECK} {query}")
    for n in call("notesInfo", notes=nids) if nids else []:
        f = {k: v["value"] for k, v in n["fields"].items()}
        print(f"{n['noteId']}  {f['German']} | {f['English']} | {f['Part of Speech']}")
        for k in ("Grammar", "Notes", "Conjugation"):
            if f.get(k):
                print(f"    {k}: {f[k][:120]}")
        for c in call("cardsInfo", cards=n["cards"]):
            print(f"    card {c['cardId']} ord={c['ord']} type={c['type']} queue={c['queue']} due={c['due']}")
    print(f"({len(nids)} notes)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    if sys.argv[1] == "notes":
        notes(" ".join(sys.argv[2:]))
    else:
        raw = sys.argv[2] if len(sys.argv) > 2 else ("" if sys.stdin.isatty() else sys.stdin.read())
        print(json.dumps(call(sys.argv[1], **json.loads(raw or "{}")), ensure_ascii=False, indent=1))
