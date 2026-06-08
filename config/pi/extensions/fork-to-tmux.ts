import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawn } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";

// Intercept /fork and /clone: when running inside tmux, open the forked
// session in a new tmux split instead of replacing the current pane.
// Outside tmux, fall through to pi's default behavior.
//
// Configurable via env:
//   PI_FORK_TMUX_SPLIT_DIR=h|v  — split direction (default h, side-by-side)
//   PI_FORK_TMUX_FOCUS=0|1      — focus new pane after split (default 1)

const SPLIT_DIR = (process.env.PI_FORK_TMUX_SPLIT_DIR ?? "h") === "v" ? "-v" : "-h";
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

    try {
      // Truncate parent JSONL at the selected entry.
      //   /fork  → position="before": stop just before the entry
      //   /clone → position="at":     include the entry itself
      const position = event.position ?? "before";
      const lines = readFileSync(sourceFile, "utf8")
        .split("\n")
        .filter((l) => l.length > 0);
      const kept: string[] = [];
      for (const line of lines) {
        kept.push(line);
        let entry: any;
        try { entry = JSON.parse(line); } catch { continue; }
        if (entry.id === event.entryId) {
          if (position === "before") kept.pop();
          break;
        }
      }

      // Write the forked session next to the source.
      const newFile = sourceFile.replace(/\.jsonl$/, `_fork_${Date.now()}.jsonl`);
      writeFileSync(newFile, kept.join("\n") + "\n");

      // tmux split-window: shell out so the command string is quoted properly
      // when sourceFile/newFile contain unusual chars.
      const tmuxArgs = [
        "split-window",
        SPLIT_DIR,
        ...(FOCUS_NEW ? [] : ["-d"]),
        "pi", "--session", newFile,
      ];
      const proc = spawn("tmux", tmuxArgs, { stdio: "ignore", detached: true });
      proc.on("error", () => {}); // tmux failures shouldn't crash pi
      proc.unref();

      ctx.ui.notify(
        `Forked into new tmux pane (${position}, ${kept.length} entries)`,
        "info",
      );
      return { cancel: true }; // cancel the in-place fork
    } catch (err: any) {
      ctx.ui.notify(
        `tmux-fork failed: ${err?.message ?? err}; falling back to default fork`,
        "warning",
      );
      return; // don't cancel — let default behavior run
    }
  });
}
