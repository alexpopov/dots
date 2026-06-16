import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { DynamicBorder, SessionManager } from "@earendil-works/pi-coding-agent";
import { Container, type SelectItem, SelectList, Text } from "@earendil-works/pi-tui";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
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
  pi.registerCommand("done", {
    description:
      "Mark the current session as done (archived). Hides it from " +
      "/find-session by default. /done undo to unmark.",
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
        return;
      }
      if (archived.has(file)) {
        ctx.ui.notify("Already marked done. /done undo to unmark.", "info");
        return;
      }
      archived.add(file);
      saveArchived(archived);
      ctx.ui.notify("Marked done. Hidden from /find-session (use --all or --done to see).", "info");
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
  // Newest first.
  const sorted = [...sessions].sort((a, b) => timestampOf(b) - timestampOf(a));
  const items: SelectItem[] = [];
  for (const s of sorted) {
    const file = s.file ?? s.path ?? s.sessionFile;
    if (!file || typeof file !== "string") continue;
    const isDone = archived.has(file);
    if (flags.showDoneOnly && !isDone) continue;
    if (!flags.showAll && !flags.showDoneOnly && isDone) continue;
    const rawLabel = pickLabel(s, file);
    const label = isDone ? `[done] ${rawLabel}` : rawLabel;
    const desc = pickDescription(s);
    if (query && !`${label} ${desc} ${file}`.toLowerCase().includes(query)) continue;
    items.push({ value: file, label, description: desc });
  }
  return items;
}

function pickLabel(s: any, file: string): string {
  if (typeof s.name === "string" && s.name.trim()) return s.name.trim();
  if (typeof s.displayName === "string" && s.displayName.trim()) return s.displayName.trim();
  if (typeof s.firstMessage === "string" && s.firstMessage.trim()) {
    return s.firstMessage.trim().slice(0, 80);
  }
  return basename(file, ".jsonl");
}

function pickDescription(s: any): string {
  const parts: string[] = [];
  const ts = timestampOf(s);
  if (ts > 0) parts.push(relativeTime(ts));
  const cwd = typeof s.cwd === "string" ? s.cwd : null;
  if (cwd) parts.push(shrinkPath(cwd));
  return parts.join("  ·  ");
}

function timestampOf(s: any): number {
  if (typeof s.timestamp === "number") return s.timestamp;
  if (typeof s.mtime === "number") return s.mtime;
  if (typeof s.mtimeMs === "number") return s.mtimeMs;
  if (typeof s.updatedAt === "number") return s.updatedAt;
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
