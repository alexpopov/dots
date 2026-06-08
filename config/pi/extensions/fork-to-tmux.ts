import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { DynamicBorder } from "@earendil-works/pi-coding-agent";
import { Container, type SelectItem, SelectList, Text } from "@earendil-works/pi-tui";
import { spawn } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";

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
        `Forked into new tmux pane (${dir === "-h" ? "right" : "down"}, ${position}, ${kept.length} entries)`,
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
      handleInput: (data: string) => { selectList.handleInput(data); tui.requestRender(); },
    };
  });
}
