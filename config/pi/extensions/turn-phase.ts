import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// Turn-phase indicator: a compact line above the editor showing whether the
// MAIN agent is idle, generating ("working"), or parked inside a tool's
// execute -- the synchronous-wait phase -- with elapsed time. Hidden when idle.
//
// This is the distinction that matters for "why is my input queuing": ANY
// non-idle state means a turn is active, so your message lands between turns
// (queues) rather than immediately. And it separates "taking a turn" (working)
// from "blocked waiting on a tool" (a tool in flight + growing elapsed):
//   - a foreground `bash` build shows   "- bash 12m"   the whole time (blocking)
//   - `bash_background` blips for <1s and returns to idle (truly detached)
//   - a bg-bash / subagent completion wake shows "\ working" -- the turn your
//     message would queue behind.
//
// Mechanism: agent_start..agent_settled = turn active; tool_execution_start..
// tool_execution_end = the in-tool (synchronous-wait) phase. A poll animates
// the spinner and ticks elapsed.
//
// No emoji: they mis-measure / need VS16 and jitter column width. Uses the
// Braille-dots spinner (U+2800 block) -- the de-facto terminal spinner (ora,
// npm, cargo): East Asian Width = Neutral, so always ONE cell, no variation
// selectors, and even a font missing the glyph renders single-width tofu.
// Avoids Ambiguous-width glyphs (● ◐ ▶ ✓ ★, and even ·/•) which render 1 OR 2
// cells by terminal/locale. Separators are ASCII; a long wait is flagged with
// COLOR, not a glyph.
//
// Env: PI_TURN_PHASE_DISABLE=1 to turn off; PI_TURN_PHASE_POLL_MS (default 150);
// PI_TURN_PHASE_WARN_MS (default 15000) = when an in-tool wait turns "warning".

const KEY = "turn-phase";
const SPIN = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
const POLL_MS = Number(process.env.PI_TURN_PHASE_POLL_MS) || 150;
const WARN_MS = Number(process.env.PI_TURN_PHASE_WARN_MS) || 15000;

function fmt(ms: number): string {
  const s = Math.floor(ms / 1000);
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) {
    const r = s % 60;
    return r ? `${m}m${String(r).padStart(2, "0")}s` : `${m}m`;
  }
  const h = Math.floor(m / 60);
  return `${h}h${String(m % 60).padStart(2, "0")}m`;
}

export default function (pi: ExtensionAPI) {
  if (process.env.PI_TURN_PHASE_DISABLE === "1") return;

  let active = false;
  let frame = 0;
  let ctx: any = null;
  let poll: ReturnType<typeof setInterval> | null = null;
  const inFlight = new Map<string, { name: string; startedAt: number }>();

  const stop = () => { if (poll) { clearInterval(poll); poll = null; } };
  const clear = () => { try { ctx?.ui?.setWidget?.(KEY, undefined); } catch {} };

  const render = () => {
    if (!active || !ctx?.ui?.setWidget) return;
    const now = Date.now();
    const spin = SPIN[frame % SPIN.length];
    ctx.ui.setWidget(KEY, (_tui: any, theme: any) => ({
      render: () => {
        const tools = [...inFlight.values()].sort((a, b) => a.startedAt - b.startedAt);
        if (tools.length === 0) {
          return [`${theme.fg("dim", spin)} ${theme.fg("muted", "working")}`];
        }
        const oldest = tools[0];
        const waited = now - oldest.startedAt;
        const long = waited >= WARN_MS;
        const label = tools.length === 1
          ? `${oldest.name} ${fmt(waited)}`
          : `${tools.length} tools, ${oldest.name} ${fmt(waited)}`;
        const tail = long ? theme.fg("dim", "  waiting -- input queues, Esc interrupts") : "";
        return [`${theme.fg(long ? "warning" : "dim", spin)} ${theme.fg(long ? "warning" : "text", label)}${tail}`];
      },
      invalidate: () => {},
    }));
  };

  const start = () => {
    if (poll) return;
    poll = setInterval(() => { frame++; render(); }, POLL_MS);
    poll.unref?.();
  };

  pi.on("session_start", (_e: any, c: any) => { ctx = c; });
  pi.on("session_shutdown", () => { stop(); clear(); });

  // Turn boundaries. agent_settled (not agent_end) = truly done, so the widget
  // persists across chained turns (retry/compaction/follow-up) and only clears
  // when the agent is genuinely idle.
  pi.on("agent_start", (_e: any, c: any) => { ctx = c || ctx; active = true; inFlight.clear(); frame = 0; render(); start(); });
  pi.on("agent_settled", (_e: any, c: any) => { ctx = c || ctx; active = false; inFlight.clear(); stop(); clear(); });

  // In-tool (synchronous-wait) phase.
  pi.on("tool_execution_start", (e: any, c: any) => { ctx = c || ctx; inFlight.set(e.toolCallId, { name: e.toolName || "tool", startedAt: Date.now() }); render(); });
  pi.on("tool_execution_end", (e: any, c: any) => { ctx = c || ctx; inFlight.delete(e.toolCallId); render(); });
}
