import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { DynamicBorder } from "@earendil-works/pi-coding-agent";
import { Container, type SelectItem, SelectList, Text } from "@earendil-works/pi-tui";
import { spawn } from "node:child_process";
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename, dirname } from "node:path";
import { randomUUID } from "node:crypto";

// Intercept /fork and /clone: when running inside tmux, open the forked
// session in a new tmux split instead of replacing the current pane.
// Outside tmux, fall through to pi's default behavior.
//
// Configurable via env:
//   PI_FORK_TMUX_SPLIT_DIR=h|v  — default direction (h=right, v=down). When
//                                 prompting, the matching option is listed
//                                 first so Enter accepts it.
//   PI_FORK_TMUX_PROMPT=0|1     — show a Right/Down selector before splitting
//                                 (default 1). Set to 0 to use the env default
//                                 without prompting.
//   PI_FORK_TMUX_FOCUS=0|1      — focus new pane after split (default 1).

const DEFAULT_DIR = (process.env.PI_FORK_TMUX_SPLIT_DIR ?? "h") === "v" ? "-v" : "-h";
const PROMPT = (process.env.PI_FORK_TMUX_PROMPT ?? "1") !== "0";
const FOCUS_NEW = (process.env.PI_FORK_TMUX_FOCUS ?? "1") !== "0";

export default function (pi: ExtensionAPI) {
  pi.on("session_before_fork", async (event: any, ctx: any) => {
    // Not in tmux — let pi's default fork-in-place behavior run.
    if (!process.env.TMUX) return;

    const sourceFile = ctx.sessionManager?.getSessionFile?.();
    if (!sourceFile || !existsSync(sourceFile)) {
      // Ephemeral session has no file to copy; default behavior.
      return;
    }

    // Ask for direction (or use env default if prompting is off).
    let dir: string | null = DEFAULT_DIR;
    if (PROMPT) {
      dir = await pickSplitDirection(ctx);
      if (dir === null) {
        ctx.ui.notify("Fork cancelled", "info");
        return { cancel: true };
      }
    }

    try {
      // Include the picked entry AND the assistant response that follows
      // it (the rest of that turn — assistant text, tool calls, tool
      // results, etc.), stopping just before the next user message. Users
      // who want less context can pick an earlier entry in the tree.
      //
      // The /fork "before" vs /clone "at" pi distinction is ignored on
      // purpose — pi's "before" is optimized for "rewrite this message"
      // (cuts entry, restores as editor draft), which doesn't translate
      // to tmux where the new pane has no editor relationship to the
      // picked text. For "branch from here and continue" (the actual use
      // case for tmux forks), we always want the full picked exchange.
      const lines = readFileSync(sourceFile, "utf8")
        .split("\n")
        .filter((l) => l.length > 0);
      const kept: string[] = [];
      let foundPicked = false;
      for (const line of lines) {
        let entry: any;
        try { entry = JSON.parse(line); } catch { kept.push(line); continue; }

        if (!foundPicked) {
          kept.push(line);
          if (entry.id === event.entryId) foundPicked = true;
          continue;
        }

        // After picked: stop at the next user message to bound the turn.
        if (entry.type === "message" && entry.message?.role === "user") break;
        kept.push(line);
      }

      // Give the fork a distinct session name so it's recognizable in
      // /resume and not confused with its parent. Format: "<base name>
      // (fork N)". We strip any existing "(fork N)" suffix from the parent
      // name first — otherwise forking a fork produced the dumb
      // "X (fork 1) (fork 1)". N counts the whole fork family (every
      // descendant of the original session), so a fork of a fork becomes
      // "(fork 2)" and sibling forks get distinct numbers.
      const baseName = stripForkSuffix(lastSessionInfoName(kept) ?? "Untitled");
      const forkNumber = countFamilyForks(sourceFile) + 1;
      const forkName = `${baseName} (fork ${forkNumber})`;
      const lastEntryId = lastEntryIdOf(kept);
      kept.push(JSON.stringify({
        type: "session_info",
        id: randomUUID().replace(/-/g, "").slice(0, 8),
        parentId: lastEntryId,
        timestamp: new Date().toISOString(),
        name: forkName,
      }));

      const newFile = sourceFile.replace(/\.jsonl$/, `_fork_${Date.now()}.jsonl`);
      writeFileSync(newFile, kept.join("\n") + "\n");

      const tmuxArgs = [
        "split-window",
        dir,
        ...(FOCUS_NEW ? [] : ["-d"]),
        "pi", "--session", newFile,
      ];
      const proc = spawn("tmux", tmuxArgs, { stdio: "ignore", detached: true });
      proc.on("error", () => {});
      proc.unref();

      ctx.ui.notify(
        `Forked to new pane as "${forkName}" — /name in the new pane to rename`,
        "info",
      );
      return { cancel: true };
    } catch (err: any) {
      ctx.ui.notify(
        `tmux-fork failed: ${err?.message ?? err}; falling back to default fork`,
        "warning",
      );
      return; // don't cancel — let default behavior run
    }
  });
}

function lastSessionInfoName(jsonlLines: string[]): string | null {
  for (let i = jsonlLines.length - 1; i >= 0; i--) {
    try {
      const e = JSON.parse(jsonlLines[i]);
      if (e.type === "session_info" && typeof e.name === "string") return e.name;
    } catch {}
  }
  return null;
}

function lastEntryIdOf(jsonlLines: string[]): string | null {
  for (let i = jsonlLines.length - 1; i >= 0; i--) {
    try {
      const e = JSON.parse(jsonlLines[i]);
      if (typeof e.id === "string") return e.id;
    } catch {}
  }
  return null;
}

// Strip a trailing " (fork N)" suffix (or a chain of them) so we recover the
// original session title. "X (fork 1) (fork 2)" -> "X".
function stripForkSuffix(name: string): string {
  let base = name;
  const re = /\s*\(fork\s+\d+\)\s*$/i;
  while (re.test(base)) base = base.replace(re, "");
  return base.trim() || "Untitled";
}

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// The original session stem, with every "_fork_<ts>" segment removed.
// "X_fork_111_fork_222" -> "X".
function originalStem(sourceFile: string): string {
  return basename(sourceFile, ".jsonl").replace(/(?:_fork_\d+)+$/, "");
}

// Count every descendant fork of the original session in the same dir —
// "<orig>_fork_<ts>(_fork_<ts>)*.jsonl" — regardless of how deep this fork is
// in the chain. +1 (added by the caller) is the next family-wide fork number,
// so chains increment (fork 1 -> fork 2 -> ...) and siblings stay distinct.
function countFamilyForks(sourceFile: string): number {
  try {
    const dir = dirname(sourceFile);
    const orig = originalStem(sourceFile);
    const re = new RegExp(`^${escapeRegExp(orig)}(?:_fork_\\d+)+\\.jsonl$`);
    return readdirSync(dir).filter((f) => re.test(f)).length;
  } catch {
    return 0;
  }
}

async function pickSplitDirection(ctx: any): Promise<string | null> {
  // Order items so the env-default is first → Enter accepts it.
  const right: SelectItem = { value: "-h", label: "Right (side-by-side)" };
  const down: SelectItem = { value: "-v", label: "Down (stacked)" };
  const items: SelectItem[] = DEFAULT_DIR === "-v" ? [down, right] : [right, down];

  return ctx.ui.custom<string | null>((tui: any, theme: any, _kb: any, done: (v: string | null) => void) => {
    const container = new Container();
    container.addChild(new DynamicBorder((s: string) => theme.fg("accent", s)));
    container.addChild(new Text(theme.fg("accent", theme.bold("Fork into new tmux pane")), 1, 0));

    const selectList = new SelectList(items, items.length, {
      selectedPrefix: (t: string) => theme.fg("accent", t),
      selectedText: (t: string) => theme.fg("accent", t),
    });
    selectList.onSelect = (item: SelectItem) => done(item.value);
    selectList.onCancel = () => done(null);
    container.addChild(selectList);

    container.addChild(new Text(theme.fg("dim", "↑↓ navigate • enter select • esc cancel"), 1, 0));
    container.addChild(new DynamicBorder((s: string) => theme.fg("accent", s)));

    return {
      render: (w: number) => container.render(w),
      invalidate: () => container.invalidate(),
      handleInput: (data: string) => {
        // Translate vim j/k to down/up arrow escape sequences so the
        // SelectList (which only knows arrows) processes them as expected.
        if (data === "j") data = "\x1b[B";
        else if (data === "k") data = "\x1b[A";
        selectList.handleInput(data);
        tui.requestRender();
      },
    };
  });
}
