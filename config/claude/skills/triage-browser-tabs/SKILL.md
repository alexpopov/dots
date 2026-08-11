---
name: triage-browser-tabs
description: Triage browser tabs. Use when the user mentions browser tabs, tab triage, tab cleanup, closing tabs, listing tabs, organizing tabs, or wants to manage their Chrome or Safari tabs.
allowed-tools: Bash
---

# Browser Tab Triage

Interact with Chrome or Safari browser tabs using the `browser-triage` script at `~/dots/bin/scripts/browser-triage`. This script uses AppleScript via a background tmux session to list, close, and focus browser tabs.

## Prerequisites

- macOS (uses AppleScript)
- `tmux` must be installed
- The `browser-triage` script at `~/dots/bin/scripts/browser-triage`
- On first use, the script auto-creates a `browser-bridge` tmux session

## Commands

### List all tabs

```bash
~/dots/bin/scripts/browser-triage list
# Safari:
~/dots/bin/scripts/browser-triage -b safari list
```

Returns JSON array of objects: `{"window": N, "tab": N, "mode": "...", "title": "...", "url": "..."}`.

### Close tabs by URL pattern

```bash
~/dots/bin/scripts/browser-triage close-url PATTERN
```

Closes all tabs whose URL contains PATTERN. Pattern must be alphanumeric with dots, dashes, slashes, colons only.

### Close a single tab

```bash
~/dots/bin/scripts/browser-triage close-tab WINDOW TAB
```

Window and tab are 1-indexed integers.

### Close multiple tabs

```bash
~/dots/bin/scripts/browser-triage close-tabs W1:T1 W2:T2 ...
```

Accepts space-separated `WINDOW:TAB` pairs. Tabs are closed in reverse order per window so indices stay valid.

### Focus a tab

```bash
~/dots/bin/scripts/browser-triage focus WINDOW TAB
```

Activates the given tab and brings its window to the front.

## Triage workflow

When the user asks to triage their tabs:

1. Run `browser-triage list` to get all tabs (default: Chrome; use `-b safari` if asked).
2. Categorize tabs into logical groups (e.g. diffs/code review, docs, tasks, reference, dashboards, personal, misc).
3. Identify:
   - **Duplicates**: tabs with identical URLs — recommend closing all but one.
   - **Stale references**: one-off lookups (code search results, API docs, wiki pages) the user has likely already consumed.
   - **Completed work**: diffs that are likely landed, merged tasks, finished projects.
4. Present a clear summary table grouped by category, showing title and `W:T` coordinates.
5. Ask the user which groups or individual tabs to close.
6. When closing, use `close-tabs W:T ...` to batch-close in one command.

## Notes

- The script defaults to Chrome. Pass `-b safari` for Safari.
- Tab/window indices shift after closing tabs. Always re-list (`browser-triage list`) if you need to do further operations after closing tabs.
- The tmux session `browser-bridge` persists between invocations. It is created automatically if missing.
- Timeout is 15 seconds per AppleScript invocation.
