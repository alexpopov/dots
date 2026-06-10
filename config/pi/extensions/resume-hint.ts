import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { basename } from "node:path";

// Print a "↻ resume: pi --session <id>" hint to stderr when pi exits, so
// you can easily resume after Ctrl+C / Ctrl+D / or any other quit.
//
// Adapted from Ivan Gromov's resume-hint extension
// (fbsource/users/iv/ivangromov/resume-hint).
//
// Why process.on("exit") and not pi's session_shutdown event:
// session_shutdown fires BEFORE the TUI tears down. Anything we print there
// gets erased by the terminal reset that follows. process.on("exit") fires
// after teardown, so the hint actually lands in the user's shell.
//
// Configurable via env:
//   PI_RESUME_HINT_DISABLE=1  — skip the hint print.

let lastSessionFile: string | undefined;
let activeHasUI = false;
let hintPrinted = false;

export default function (pi: ExtensionAPI) {
  if (process.env.PI_RESUME_HINT_DISABLE === "1") return;

  // Re-stash on every session start so /resume, /fork, /new switch us to
  // the new active session.
  pi.on("session_start", (_event: any, ctx: any) => {
    lastSessionFile = ctx.sessionManager?.getSessionFile?.() ?? undefined;
    activeHasUI = !!ctx.hasUI;
    hintPrinted = false;
  });

  // Register the exit listener at most once even if the extension is
  // reloaded via /reload (each load would otherwise add another listener
  // and we'd print N hints on exit).
  if (!(globalThis as any).__pi_resume_hint_installed) {
    (globalThis as any).__pi_resume_hint_installed = true;
    process.on("exit", () => {
      if (hintPrinted) return;
      if (!activeHasUI) return; // skip in -p / json / rpc modes
      if (!lastSessionFile) return; // ephemeral (--no-session) → nothing to resume
      hintPrinted = true;

      const fileName = basename(lastSessionFile, ".jsonl");
      // Filename shape is `<timestamp>_<uuid>.jsonl`. Take the last
      // `_`-separated chunk so we work even if the timestamp contains
      // unusual chars; fall back to the whole name if there's no `_`.
      const parts = fileName.split("_");
      const uuid = parts.length >= 2 ? parts[parts.length - 1] : fileName;
      const short = uuid.replace(/-/g, "").slice(0, 8);

      process.stderr.write(
        `\n↻ resume: pi --session ${short}    # full id: ${uuid}\n`,
      );
    });
  }
}
