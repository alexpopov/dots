import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { basename, join } from "node:path";
import { homedir } from "node:os";
import {
  mkdirSync,
  readdirSync,
  renameSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";

// Record "which pi session is running in which tmux pane" to a small on-disk
// registry, so tmux-resurrect/continuum can save that mapping alongside the
// pane layout and tell you how to resume each session after a reboot.
//
// Nothing in pi exposes its session id to the outside world: the session
// .jsonl is opened/appended/closed per write (so lsof can't see it) and the
// id isn't in the process environment. Without this file the tmux side can
// only *guess* (newest session file in the pane's cwd), which is wrong as
// soon as two pi panes share a directory -- which is the normal case here.
//
// Consumer: bin/scripts/pi-tmux-sessions (save|restore|hint|list).
//
// Entry format is deliberately NOT json: the reader is a POSIX shell script
// running under macOS bash 3.2 from a tmux hook, where jq may not be on PATH.
// One `key=value` per line, values are single-line and unescaped.
//
// Keyed by $TMUX_PANE (%12). Pane ids reset when the tmux server restarts, so
// a stale file can collide with a new pane; the reader defends against that by
// checking that the recorded pid is a live descendant of the pane's process.
//
// Written on session_start (new/resume/fork switch the active session),
// agent_end (picks up auto-rename's LLM-generated names) and session_shutdown.
//
// Configurable via env:
//   PI_TMUX_REGISTRY_DIR=<dir>   — override the registry location.
//   PI_TMUX_REGISTRY_DISABLE=1   — skip the extension entirely.

const PRUNE_DAYS = 30;

function registryDir(): string {
  if (process.env.PI_TMUX_REGISTRY_DIR) return process.env.PI_TMUX_REGISTRY_DIR;
  const base =
    process.env.XDG_DATA_HOME && process.env.XDG_DATA_HOME.trim()
      ? process.env.XDG_DATA_HOME
      : join(homedir(), ".local", "share");
  return join(base, "pi-tmux", "panes");
}

// "%12" -> "12". Keeps the filename shell-safe (a literal % is fine, but it
// reads badly in globs and in tmux's own format strings).
function paneFileName(pane: string): string {
  return `pane-${pane.replace(/[^0-9A-Za-z]/g, "")}`;
}

// Session files are named `<timestamp>_<uuid>.jsonl`; forks append
// `_fork_<ms>`. The uuid is the chunk that parses as a uuid, scanning from the
// end so fork suffixes don't win.
function idFromFile(file: string): string {
  const stem = basename(file, ".jsonl");
  const parts = stem.split("_");
  for (let i = parts.length - 1; i >= 0; i--) {
    if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(parts[i])) {
      return parts[i];
    }
  }
  return parts.length >= 2 ? parts[parts.length - 1] : stem;
}

// Strip anything that would break the one-line key=value format.
function clean(value: string): string {
  return value.replace(/[\r\n\t]+/g, " ").trim();
}

export default function (pi: ExtensionAPI) {
  if (process.env.PI_TMUX_REGISTRY_DISABLE === "1") return;
  const pane = process.env.TMUX_PANE;
  if (!pane) return; // not inside tmux -- nothing to map
  // Subagent/council children share the parent's pane but are short-lived and
  // not something you'd resume by hand; they'd clobber the real entry.
  if (process.env.PI_AGENT_TEAM_CHILD === "1") return;

  const dir = registryDir();
  const file = join(dir, `${paneFileName(pane)}.conf`);

  const write = (ctx: any, state: string) => {
    try {
      const sessionFile: string | undefined = ctx?.sessionManager?.getSessionFile?.();
      if (!sessionFile) return; // --no-session / ephemeral: nothing to resume
      const name = pi.getSessionName?.() ?? "";
      const id = idFromFile(sessionFile);
      const body =
        [
          `pane=${pane}`,
          `pid=${process.pid}`,
          `id=${id}`,
          `short=${id.replace(/-/g, "").slice(0, 8)}`,
          `file=${clean(sessionFile)}`,
          `name=${clean(name ?? "")}`,
          `cwd=${clean(process.cwd())}`,
          `state=${state}`,
          `updated=${new Date().toISOString()}`,
        ].join("\n") + "\n";
      mkdirSync(dir, { recursive: true });
      // Atomic-ish: the tmux save hook can read this at any moment.
      const tmp = `${file}.${process.pid}.tmp`;
      writeFileSync(tmp, body, "utf8");
      renameSync(tmp, file);
    } catch {
      // A registry write must never take pi down.
    }
  };

  const prune = () => {
    try {
      const cutoff = Date.now() - PRUNE_DAYS * 86400_000;
      for (const entry of readdirSync(dir)) {
        if (!entry.startsWith("pane-")) continue;
        const p = join(dir, entry);
        try {
          if (statSync(p).mtimeMs < cutoff) unlinkSync(p);
        } catch {}
      }
    } catch {}
  };

  pi.on("session_start", (_event: any, ctx: any) => {
    write(ctx, "running");
    prune();
  });

  // Cheap (one small file write per turn) and keeps the recorded name in sync
  // with auto-rename.ts, which renames on turn 4, 8, 16, ...
  pi.on("agent_end", (_event: any, ctx: any) => write(ctx, "running"));

  // Clean exit: keep the entry (you may still want to resume what you just
  // quit) but mark it, so the tmux side can prefer a pane that's still live.
  pi.on("session_shutdown", (_event: any, ctx: any) => write(ctx, "exited"));
}
