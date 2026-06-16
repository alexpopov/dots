import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { DynamicBorder, SessionManager } from "@earendil-works/pi-coding-agent";
import { Container, type SelectItem, SelectList, Text } from "@earendil-works/pi-tui";
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";

// Archived-session state. Per-machine (session file paths are local), so
// stored under ~/.pi/agent/ — NOT in dots.
const ARCHIVED_FILE = join(process.env.HOME ?? "", ".pi", "agent", "archived-sessions.json");

function loadArchived(): Set<string> {
  try {
    if (!existsSync(ARCHIVED_FILE)) return new Set();
    const data = JSON.parse(readFileSync(ARCHIVED_FILE, "utf8"));
    return new Set(Array.isArray(data?.archived) ? data.archived : []);
  } catch {
    return new Set();
  }
}

function saveArchived(archived: Set<string>): void {
  try {
    mkdirSync(dirname(ARCHIVED_FILE), { recursive: true });
    writeFileSync(ARCHIVED_FILE, JSON.stringify({ archived: [...archived].sort() }, null, 2));
  } catch {
    // best-effort; the next /done call will retry
  }
}

// /find-session [query] — search all pi sessions across every cwd, not
// just the current one. Pi's built-in /resume is cwd-scoped, so if you
// start a session in ~/foo and later move to ~/bar, /resume in ~/bar
// won't show it. This command uses SessionManager.listAll() to enumerate
// every session globally, presents a picker, then switches into the
// chosen session via ctx.switchSession.
//
// Usage:
//   /find-session              show all sessions (newest first)
//   /find-session pi widget    pre-filter by substring before showing

export default function (pi: ExtensionAPI) {
  // (No quit-confirm.) An earlier version hooked session_shutdown to
  // ask "mark done?" before exiting — broken: TUI is already tearing
  // down by that event, ctx.ui.confirm's promise never resolves, pi
  // hangs until force-killed. A follow-up tried /q + Ctrl+Q as a
  // manual quit-with-confirm, but if the user has to remember /q they
  // might as well just /done before /exit. Pi has no
  // session_before_quit hook. Leaving this as a known gap.

  pi.registerCommand("done", {
    description:
      "Mark the current session done (archived) AND quit pi. /done by " +
      "itself = 'I'm finished with this conversation, get me out'. " +
      "/done stay marks without quitting. /done undo unmarks (no quit).",
    handler: async (args: string, ctx: any) => {
      const file = ctx.sessionManager?.getSessionFile?.();
      if (!file) {
        ctx.ui.notify("No session file (ephemeral session). Nothing to mark.", "warning");
        return;
      }
      const arg = (args ?? "").trim().toLowerCase();
      const archived = loadArchived();

      if (arg === "undo" || arg === "unmark" || arg === "undone") {
        if (!archived.has(file)) {
          ctx.ui.notify("Session wasn't marked done.", "info");
          return;
        }
        archived.delete(file);
        saveArchived(archived);
        ctx.ui.notify("Unmarked. Session will show in /find-session.", "info");
        return; // never quit on undo
      }

      const stayAfter = arg === "stay" || arg === "keep";

      if (!archived.has(file)) {
        archived.add(file);
        saveArchived(archived);
      }

      if (stayAfter) {
        ctx.ui.notify("Marked done. (Staying — /done without 'stay' to quit.)", "info");
        return;
      }

      // Default: mark + quit. ctx.shutdown defers until idle, so any
      // pending agent work finishes first. The archived entry is
      // already on disk so the exit-hint extension still prints the
      // resume command and you can /done undo if you regret it.
      ctx.ui.notify("Marked done. Bye.", "info");
      try { ctx.shutdown(); } catch (err: any) {
        ctx.ui.notify(`shutdown failed: ${err?.message ?? err}`, "error");
      }
    },
  });

  pi.registerCommand("archive-old", {
    description:
      "Bulk-archive sessions older than N days (default 30). Use " +
      "/archive-old 7 for a week, /archive-old 90 --dry-run to preview, etc.",
    handler: async (args: string, ctx: any) => {
      const tokens = (args ?? "").trim().split(/\s+/).filter(Boolean);
      const dryRun = tokens.includes("--dry-run");
      const dayToken = tokens.find((t) => /^\d+$/.test(t));
      const days = dayToken ? parseInt(dayToken, 10) : 30;
      const cutoff = Date.now() - days * 24 * 60 * 60 * 1000;

      let sessions: any[];
      try {
        sessions = await SessionManager.listAll();
      } catch (err: any) {
        ctx.ui.notify(`Failed to list sessions: ${err?.message ?? err}`, "error");
        return;
      }

      const archived = loadArchived();
      const currentFile = ctx.sessionManager?.getSessionFile?.();
      const candidates: string[] = [];
      for (const s of sessions) {
        const file = s.file ?? s.path ?? s.sessionFile;
        if (!file || typeof file !== "string") continue;
        if (file === currentFile) continue; // don't archive the active session
        if (archived.has(file)) continue;
        const ts = timestampOf(s);
        if (ts > 0 && ts < cutoff) candidates.push(file);
      }

      if (candidates.length === 0) {
        ctx.ui.notify(`No unarchived sessions older than ${days} days.`, "info");
        return;
      }

      if (dryRun) {
        ctx.ui.notify(
          `Would archive ${candidates.length} session(s) older than ${days} days. Re-run without --dry-run to apply.`,
          "info",
        );
        return;
      }

      for (const file of candidates) archived.add(file);
      saveArchived(archived);
      ctx.ui.notify(
        `Archived ${candidates.length} session(s) older than ${days} days.`,
        "info",
      );
    },
  });

  pi.registerCommand("find-session", {
    description:
      "Search all pi sessions across every folder/project (not just the " +
      "current cwd). /find-session [query] [--all|--done] — by default " +
      "hides sessions marked done via /done. --all includes them (with a " +
      "[done] marker); --done shows only archived.",
    handler: async (args: string, ctx: any) => {
      const tokens = (args ?? "").trim().split(/\s+/).filter(Boolean);
      const showAll = tokens.includes("--all");
      const showDoneOnly = tokens.includes("--done");
      const query = tokens.filter((t) => !t.startsWith("--")).join(" ").toLowerCase();

      let sessions: any[];
      try {
        sessions = await SessionManager.listAll();
      } catch (err: any) {
        ctx.ui.notify(`Failed to list sessions: ${err?.message ?? err}`, "error");
        return;
      }
      if (!sessions || sessions.length === 0) {
        ctx.ui.notify("No pi sessions found anywhere.", "info");
        return;
      }

      const archived = loadArchived();
      const items = buildItems(sessions, query, archived, { showAll, showDoneOnly });
      if (items.length === 0) {
        const what = showDoneOnly ? "archived" : showAll ? "" : "(unarchived) ";
        ctx.ui.notify(`No ${what}sessions match "${query}".`.replace(/\s+/g, " ").trim(), "info");
        return;
      }

      const totalNote = items.length === sessions.length
        ? `${sessions.length} sessions`
        : `${items.length} of ${sessions.length}${showAll ? " (incl. done)" : showDoneOnly ? " done" : ""}${query ? ` matching "${query}"` : ""}`;

      const choice = await ctx.ui.custom<string | null>(
        (tui: any, theme: any, _kb: any, done: (v: string | null) => void) => {
          const container = new Container();
          container.addChild(new DynamicBorder((s: string) => theme.fg("accent", s)));
          container.addChild(new Text(
            theme.fg("accent", theme.bold(`Find session — ${totalNote}`)),
            1, 0,
          ));

          const visibleCount = Math.min(items.length, 20);
          const selectList = new SelectList(items, visibleCount, {
            selectedPrefix: (t: string) => theme.fg("accent", t),
            selectedText: (t: string) => theme.fg("accent", t),
            description: (t: string) => theme.fg("muted", t),
            scrollInfo: (t: string) => theme.fg("dim", t),
            noMatch: (t: string) => theme.fg("warning", t),
          });
          selectList.onSelect = (item: SelectItem) => done(item.value);
          selectList.onCancel = () => done(null);
          container.addChild(selectList);

          container.addChild(new Text(
            theme.fg("dim", "↑↓ or jk navigate • enter select • esc cancel"),
            1, 0,
          ));
          container.addChild(new DynamicBorder((s: string) => theme.fg("accent", s)));

          return {
            render: (w: number) => container.render(w),
            invalidate: () => container.invalidate(),
            handleInput: (data: string) => {
              // hjkl ↔ arrows, same as our fork-to-tmux picker
              if (data === "j") data = "\x1b[B";
              else if (data === "k") data = "\x1b[A";
              selectList.handleInput(data);
              tui.requestRender();
            },
          };
        },
      );

      if (!choice) return;

      try {
        await ctx.switchSession(choice, {
          withSession: async (newCtx: any) => {
            newCtx.ui.notify(`Switched to: ${basename(choice)}`, "info");
          },
        });
      } catch (err: any) {
        ctx.ui.notify(`Failed to switch: ${err?.message ?? err}`, "error");
      }
    },
  });
}

function buildItems(
  sessions: any[],
  query: string,
  archived: Set<string>,
  flags: { showAll: boolean; showDoneOnly: boolean },
): SelectItem[] {
  // Resolve file paths up front so we can sort by mtime fallback.
  const enriched = sessions
    .map((s) => {
      const file = s.file ?? s.path ?? s.sessionFile;
      return file && typeof file === "string" ? { s, file } : null;
    })
    .filter((x): x is { s: any; file: string } => x !== null);

  // Newest first (uses the mtime fallback inside timestampOf).
  enriched.sort((a, b) => timestampOf(b.s, b.file) - timestampOf(a.s, a.file));

  const items: SelectItem[] = [];
  for (const { s, file } of enriched) {
    const isDone = archived.has(file);
    if (flags.showDoneOnly && !isDone) continue;
    if (!flags.showAll && !flags.showDoneOnly && isDone) continue;
    const { label: rawLabel, forkBadge } = pickLabel(s, file);
    const label = isDone ? `[done] ${rawLabel}` : rawLabel;
    const desc = pickDescription(s, file, forkBadge);
    if (query && !`${label} ${desc} ${file}`.toLowerCase().includes(query)) continue;
    items.push({ value: file, label, description: desc });
  }
  return items;
}

// Extract the bare label and any "(fork N)" suffix. The fork count
// makes forks indistinguishable when they share a parent prefix and the
// suffix gets truncated off; we lift it into the description column
// instead where it always survives.
function pickLabel(s: any, file: string): { label: string; forkBadge: string | null } {
  let raw = "";
  if (typeof s.name === "string" && s.name.trim()) raw = s.name.trim();
  else if (typeof s.displayName === "string" && s.displayName.trim()) raw = s.displayName.trim();
  else if (typeof s.firstMessage === "string" && s.firstMessage.trim()) {
    raw = s.firstMessage.trim().slice(0, 80);
  } else {
    raw = basename(file, ".jsonl");
  }
  // Detect "Foo (fork 2)" or "Foo (fork 12)" suffix.
  const forkMatch = /\s*\(fork\s+(\d+)\)\s*$/.exec(raw);
  if (forkMatch) {
    return { label: raw.slice(0, forkMatch.index).trim(), forkBadge: `fork ${forkMatch[1]}` };
  }
  // Fork-to-tmux fallback: filename contains `_fork_<ms-timestamp>`.
  // Multiple `_fork_` segments mean fork-of-fork; show the chain depth.
  const forkSegments = file.match(/_fork_\d+/g);
  if (forkSegments && forkSegments.length > 0) {
    return { label: raw, forkBadge: `fork×${forkSegments.length}` };
  }
  return { label: raw, forkBadge: null };
}

function pickDescription(s: any, file: string, forkBadge: string | null): string {
  const parts: string[] = [];
  if (forkBadge) parts.push(forkBadge);
  const ts = timestampOf(s, file);
  if (ts > 0) parts.push(relativeTime(ts));
  const cwd = typeof s.cwd === "string" ? s.cwd : null;
  if (cwd) parts.push(shrinkPath(cwd));
  return parts.join("  ·  ");
}

// Try every plausible timestamp field listAll might expose. If none,
// fall back to the file's mtime — the actual "last activity" signal we
// want anyway. statSync may throw if the file vanished between listAll
// and now; safe to ignore.
function timestampOf(s: any, file?: string): number {
  if (typeof s.timestamp === "number") return s.timestamp;
  if (typeof s.mtime === "number") return s.mtime;
  if (typeof s.mtimeMs === "number") return s.mtimeMs;
  if (typeof s.updatedAt === "number") return s.updatedAt;
  if (file) {
    try { return statSync(file).mtimeMs; } catch {}
  }
  return 0;
}

function relativeTime(ts: number): string {
  const ageMs = Date.now() - ts;
  const seconds = ageMs / 1000;
  if (seconds < 60) return `${Math.floor(seconds)}s ago`;
  const minutes = seconds / 60;
  if (minutes < 60) return `${Math.floor(minutes)}m ago`;
  const hours = minutes / 60;
  if (hours < 24) return `${Math.floor(hours)}h ago`;
  const days = hours / 24;
  if (days < 30) return `${Math.floor(days)}d ago`;
  const months = days / 30;
  if (months < 12) return `${Math.floor(months)}mo ago`;
  return `${Math.floor(months / 12)}y ago`;
}

function shrinkPath(p: string): string {
  const home = process.env.HOME;
  if (home && p.startsWith(home)) return "~" + p.slice(home.length);
  return p;
}
