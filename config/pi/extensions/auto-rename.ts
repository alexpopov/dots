import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawn } from "node:child_process";

// Session-naming extension. Two surfaces:
//
//   /rename               — prompt for a new name (alias for /name)
//   /rename <text>        — set name immediately
//   /rename auto          — LLM-generated name from recent conversation
//
// Plus an automatic LLM-renamer that fires on power-of-2 turn boundaries
// (4, 8, 16, 32, ...). Both surfaces share spawnRenamer().
//
// Auto-fire spacing logic:
//   - Rename quickly (turn 4) so the session is identifiable in /resume.
//   - As the session ages and the topic stabilizes, rename less often.
//   - Frequency drops by half each time → cost stays O(log N) of turns.
//
// The renamer subprocess sees the current name (so it can refine, not
// just replace), the session's ORIGINAL request (so the name reflects the
// overall arc, not just the last action), and the recent conversation, then
// returns a short name of at most 6 words.
//
// It will NOT override a human-supplied name: the automatic timer only renames
// when the current name is empty or one this extension generated itself. An
// explicit `/rename auto` always regenerates (it's a deliberate request).
//
// Configurable via env:
//   PI_AUTO_RENAME_DISABLE=1   — skip the entire extension.
//   PI_AUTO_RENAME_TURNS=4,8,16
//                              — override the default power-of-2 sequence
//                                with a comma-separated list of turn numbers.
//   PI_AUTO_RENAME_MODEL=<id>  — use a specific model for the rename call
//                                (e.g. a cheap haiku-class model).
//   PI_AUTO_RENAME_RECENT_N=6  — how many recent user/assistant messages
//                                to include in the rename prompt (default 6).

const DEFAULT_TURNS = new Set([4, 8, 16, 32, 64, 128, 256, 512, 1024]);
const TURNS: Set<number> = process.env.PI_AUTO_RENAME_TURNS
  ? new Set(
      process.env.PI_AUTO_RENAME_TURNS.split(",")
        .map((s) => parseInt(s.trim(), 10))
        .filter((n) => Number.isFinite(n) && n > 0),
    )
  : DEFAULT_TURNS;

const RECENT_N = Number(process.env.PI_AUTO_RENAME_RECENT_N) || 6;

// Per-session turn count. session_start resets it. agent_end increments.
let turnCount = 0;

// The last name THIS extension set automatically. Lets us tell our own
// auto-names (safe to refine) apart from human-supplied names (leave alone).
let lastAutoName: string | null = null;

export default function (pi: ExtensionAPI) {
  if (process.env.PI_AUTO_RENAME_DISABLE === "1") {
    // Even with auto-fire disabled, still register the manual /rename
    // command (it's a separate concern from the timer).
    registerRenameCommand(pi);
    return;
  }
  // Don't auto-rename inside subagent/council/supervise children — they
  // have their own short-lived sessions and renaming them is noise.
  if (process.env.PI_AGENT_TEAM_CHILD === "1") return;

  registerRenameCommand(pi);

  pi.on("session_start", () => {
    turnCount = 0;
    lastAutoName = null;
  });

  pi.on("agent_end", (_event: any, ctx: any) => {
    turnCount++;
    if (!TURNS.has(turnCount)) return;
    // Never clobber a human-supplied name (or one carried in from a resumed
    // session). Only auto-rename when the name is empty or one we set ourselves.
    const currentName = pi.getSessionName?.() ?? null;
    if (currentName && currentName !== lastAutoName) return;
    triggerLlmRename(pi, ctx, "auto-renamed");
  });
}

function registerRenameCommand(pi: ExtensionAPI) {
  pi.registerCommand("rename", {
    description: "Rename the current session. /rename <text> sets it, /rename alone prompts, /rename auto generates one with the LLM.",
    handler: async (args: string, ctx: any) => {
      const arg = (args ?? "").trim();

      if (arg === "auto") {
        ctx.ui.notify("generating name with LLM…", "info");
        triggerLlmRename(pi, ctx, "renamed");
        return;
      }

      let name = arg;
      if (!name) {
        const input = await ctx.ui.input("Rename session", "New name:");
        if (input == null) return;
        name = input.trim();
      }
      if (!name) {
        ctx.ui.notify("Empty name; not renaming.", "warning");
        return;
      }
      pi.setSessionName(name);
      lastAutoName = null; // human owns the name now; the timer won't override it
      ctx.ui.notify(`Renamed to "${name}"`, "info");
    },
  });
}

function triggerLlmRename(pi: ExtensionAPI, ctx: any, verb: string) {
  const sessionFile = ctx.sessionManager?.getSessionFile?.();
  if (!sessionFile) {
    try { ctx.ui.notify("Can't rename: ephemeral session.", "warning"); } catch {}
    return;
  }
  const currentName = pi.getSessionName?.() ?? null;
  const { firstUser, recent } = extractContext(ctx.sessionManager.getBranch(), RECENT_N);
  if (!recent) {
    try { ctx.ui.notify("Can't rename: no message history yet.", "warning"); } catch {}
    return;
  }
  const prompt = buildRenamePrompt(currentName, turnCount, firstUser, recent);
  spawnRenamer(prompt, (newName) => {
    if (!newName) {
      try { ctx.ui.notify("Rename failed (no name returned).", "warning"); } catch {}
      return;
    }
    pi.setSessionName(newName);
    lastAutoName = newName; // remember our own auto-name so we can refine it later
    try { ctx.ui.notify(`${verb}: "${newName}"`, "info"); } catch {}
  });
}

// --- helpers ---------------------------------------------------------------

function extractContext(branch: any[], n: number): { firstUser: string; recent: string } {
  // The first user message anchors the session's overall theme / original intent.
  let firstUser = "";
  for (let i = 0; i < branch.length; i++) {
    const entry = branch[i];
    if (entry.type !== "message" || entry.message.role !== "user") continue;
    firstUser = extractText(entry.message).slice(0, 600);
    if (firstUser) break;
  }
  // The most recent messages capture where the session is right now.
  const collected: string[] = [];
  for (let i = branch.length - 1; i >= 0 && collected.length < n; i--) {
    const entry = branch[i];
    if (entry.type !== "message") continue;
    const m = entry.message;
    if (m.role === "user") {
      const t = extractText(m).slice(0, 600);
      if (t) collected.push(`USER: ${t}`);
    } else if (m.role === "assistant") {
      const t = extractText(m).slice(0, 400);
      if (t) collected.push(`ASSISTANT: ${t}`);
    }
  }
  return { firstUser, recent: collected.reverse().join("\n\n") };
}

function extractText(m: any): string {
  if (typeof m.content === "string") return m.content;
  if (!Array.isArray(m.content)) return "";
  return m.content
    .filter((c: any) => c.type === "text" && typeof c.text === "string")
    .map((c: any) => c.text)
    .join("\n");
}

function buildRenamePrompt(currentName: string | null, turn: number, firstUser: string, recent: string): string {
  const nameContext = currentName
    ? `The session is currently named: "${currentName}". Prefer to KEEP or lightly refine it; only replace it if the session's core purpose has genuinely changed.`
    : `The session has no name yet.`;
  const origin = firstUser
    ? `How the session began (its original request — this anchors the overall theme):\n${firstUser}\n\n`
    : "";
  return `You are auto-renaming a pi.dev coding session at turn ${turn}.

${nameContext}

${origin}Recent activity:
${recent}

Name the session after its OVERALL theme — the throughline of the whole session, what it is fundamentally about — NOT just the latest step or last action. A long session that began on one task and is still pursuing it should keep that name even when the current sub-task differs. Favor a stable name that stays accurate as the work evolves.

Produce a SHORT, specific name (max 6 words). Reply with ONLY the name — no quotes, no preamble, no markdown, no explanation, no trailing punctuation. Just the words.

Good examples:
- a16 stanley bring-up
- fix nvim treesitter bug
- implement pi subagent extension
- debug devvm DNS`;
}

function spawnRenamer(prompt: string, onResult: (newName: string | null) => void): void {
  const args = ["--mode", "json"];
  if (process.env.PI_AUTO_RENAME_MODEL) {
    args.push("--model", process.env.PI_AUTO_RENAME_MODEL);
  }
  args.push("-p", prompt);

  const child = spawn("pi", args, {
    env: { ...process.env, PI_AGENT_TEAM_CHILD: "1" },
    stdio: ["ignore", "pipe", "pipe"],
  });

  let buffer = "";
  let lastAssistantText = "";
  child.stdout.on("data", (chunk) => {
    buffer += chunk.toString();
    let nl: number;
    while ((nl = buffer.indexOf("\n")) !== -1) {
      const line = buffer.slice(0, nl).trim();
      buffer = buffer.slice(nl + 1);
      if (!line) continue;
      try {
        const evt = JSON.parse(line);
        if (evt.type === "message_end" && evt.message?.role === "assistant") {
          const text = extractText(evt.message);
          if (text) lastAssistantText = text;
        }
      } catch {
        // ignore non-JSON noise
      }
    }
  });
  child.on("error", () => onResult(null));
  child.on("close", () => {
    const cleaned = cleanName(lastAssistantText);
    onResult(cleaned || null);
  });

  child.unref(); // don't keep the parent process alive on its behalf
}

function cleanName(s: string): string {
  let n = s.trim();
  if (!n) return "";
  // Take only the first non-empty line — the LLM might still preamble.
  for (const candidate of n.split("\n")) {
    const t = candidate.trim();
    if (t) { n = t; break; }
  }
  // Strip wrapping quotes/backticks/asterisks.
  n = n.replace(/^["'`*]+|["'`*]+$/g, "").trim();
  // Strip trailing punctuation.
  n = n.replace(/[.!?,;:]+$/g, "").trim();
  // Cap length.
  if (n.length > 60) n = n.slice(0, 57) + "...";
  return n;
}
