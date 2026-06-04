import { SessionManager, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { Type } from "typebox";
import { spawn } from "node:child_process";
import { existsSync, mkdirSync, statSync } from "node:fs";
import { join } from "node:path";

// --- tunables ---------------------------------------------------------------
// Defaults can be overridden by env vars (great for dotsync-wide changes) or
// per-call via the `timeoutSeconds` / `silentForSeconds` tool parameters.
const DEFAULT_TIMEOUT_SECONDS = Number(process.env.PI_SUBAGENT_TIMEOUT) || 600;
const DEFAULT_SILENT_SECONDS = Number(process.env.PI_SUBAGENT_SILENCE) || 120;
// Grace period between SIGTERM and SIGKILL when killing a hung child.
const SIGKILL_GRACE_MS = 5_000;
// How often to poll for liveness signals.
const SILENCE_CHECK_INTERVAL_MS = 10_000;
const MTIME_CHECK_INTERVAL_MS = 5_000;

export default function (pi: ExtensionAPI) {
  // (A) Recursion guard: children load this file too, but the env var
  // makes them return before registering. One env var, one early-return.
  if (process.env.PI_AGENT_TEAM_CHILD === "1") return;

  pi.registerTool({
    name: "subagent",
    label: "Subagent",
    description:
      "Spawn a fresh pi subprocess to handle a focused subtask. " +
      "Returns the subagent's final answer as text.\n\n" +
      "mode='fresh' (default): child starts empty; only sees the prompt.\n" +
      "mode='inherit': child sees a filtered copy of the parent conversation. " +
      "Thinking blocks dropped, oversize tool results truncated. Use when the " +
      "subtask needs prior context.\n\n" +
      "contextHint: short context string prepended to the prompt. Honored in " +
      "both modes. Often enough on its own — try fresh+contextHint before inherit.",

    parameters: Type.Object({
      prompt: Type.String({
        description: "Task description handed to the subagent.",
      }),
      mode: Type.Optional(StringEnum(["fresh", "inherit"] as const)),
      contextHint: Type.Optional(Type.String({
        description: "Short context line prepended to the prompt. Cheaper than mode=inherit.",
      })),
      timeoutSeconds: Type.Optional(Type.Integer({
        minimum: 1,
        description: `Hard upper bound on child runtime. Defaults to ${DEFAULT_TIMEOUT_SECONDS}s. After this, the child gets SIGTERM, then SIGKILL ${SIGKILL_GRACE_MS / 1000}s later.`,
      })),
      silentForSeconds: Type.Optional(Type.Integer({
        minimum: 0,
        description: `Kill the child if it produces no stdout/stderr/session-file activity for this long. Defaults to ${DEFAULT_SILENT_SECONDS}s. Set to 0 to disable the silence check.`,
      })),
    }),

    async execute(toolCallId, params, signal, onUpdate, ctx) {
      const mode = params.mode ?? "fresh";
      const timeoutSeconds = params.timeoutSeconds ?? DEFAULT_TIMEOUT_SECONDS;
      const silentForSeconds = params.silentForSeconds ?? DEFAULT_SILENT_SECONDS;
      const fullPrompt = params.contextHint
        ? `${params.contextHint}\n\n${params.prompt}`
        : params.prompt;

      // (B) Build CLI args. `--mode json` emits a structured JSONL event
      // stream we can parse reliably. `--session <file>` is only added in
      // inherit mode — also gives us a path to mtime-watch for liveness.
      const args: string[] = ["--mode", "json"];
      let childSessionFile: string | undefined;
      if (mode === "inherit") {
        childSessionFile = buildChildSession(ctx, toolCallId);
        args.push("--session", childSessionFile);
      }
      args.push("-p", fullPrompt);

      // (C) Spawn pi. PI_AGENT_TEAM_CHILD=1 triggers the recursion guard
      // above when the child loads this same extension.
      const child = spawn("pi", args, {
        env: { ...process.env, PI_AGENT_TEAM_CHILD: "1" },
        stdio: ["ignore", "pipe", "pipe"],
      });

      // (D) Liveness state. Any stdout/stderr chunk or session-file mtime
      // bump counts as activity. killReason latches the first reason and
      // is surfaced in the final tool result.
      let lastActivity = Date.now();
      let killReason: string | undefined;
      const bumpActivity = () => { lastActivity = Date.now(); };
      const killChild = (reason: string) => {
        if (killReason) return; // already killing
        killReason = reason;
        child.kill("SIGTERM");
        setTimeout(() => {
          if (!child.killed) child.kill("SIGKILL");
        }, SIGKILL_GRACE_MS);
      };

      // (E) Forward parent abort (Esc) to the child.
      const onAbort = () => killChild("aborted by parent");
      signal?.addEventListener("abort", onAbort);

      // (F) Parse JSONL events as they arrive. The parser keeps running
      // state for assistant messages (final + streaming draft), tool-call
      // activity, and stopReason.
      const parser = new JsonModeParser();
      let stderr = "";
      child.stdout.on("data", (chunk) => {
        bumpActivity();
        parser.push(chunk.toString(), (preview) => {
          onUpdate?.({ content: [{ type: "text", text: preview }] });
        });
      });
      child.stderr.on("data", (chunk) => {
        bumpActivity();
        stderr += chunk.toString();
      });

      // (G) Hard timeout — absolute upper bound on runtime.
      const hardTimer = setTimeout(
        () => killChild(`timeout after ${timeoutSeconds}s`),
        timeoutSeconds * 1000,
      );

      // (H) Silence watcher — kill if no activity for too long. Disable
      // by setting silentForSeconds=0.
      const silenceTimer = silentForSeconds > 0
        ? setInterval(() => {
            const silentMs = Date.now() - lastActivity;
            if (silentMs > silentForSeconds * 1000) {
              killChild(`silent for ${Math.round(silentMs / 1000)}s`);
            }
          }, SILENCE_CHECK_INTERVAL_MS)
        : null;

      // (I) Mtime watcher — only available in inherit mode (we know the
      // child's session file path). Catches "working but stdout-quiet"
      // children that are mid-tool-call but writing to their JSONL.
      let lastMtime = 0;
      const mtimeTimer = childSessionFile
        ? setInterval(() => {
            try {
              const m = statSync(childSessionFile!).mtimeMs;
              if (m > lastMtime) {
                lastMtime = m;
                bumpActivity();
              }
            } catch {}
          }, MTIME_CHECK_INTERVAL_MS)
        : null;

      // (J) Wait for exit (stdio fully drained).
      const exitCode: number = await new Promise((resolve) => {
        child.on("close", (code) => resolve(code ?? -1));
      });
      signal?.removeEventListener("abort", onAbort);
      clearTimeout(hardTimer);
      if (silenceTimer) clearInterval(silenceTimer);
      if (mtimeTimer) clearInterval(mtimeTimer);

      // (K) Build the result from parsed state.
      return parser.toResult(exitCode, stderr, killReason);
    },
  });
}

// --- inherit-mode helpers ---------------------------------------------------

/**
 * Create a child session file containing a filtered copy of the parent
 * branch. Returns the absolute path to the new JSONL.
 */
function buildChildSession(ctx: any, toolCallId: string): string {
  // Set PI_SUBAGENT_DEBUG=1 to trace replay decisions to /tmp/subagent-debug.log
  const dbg = process.env.PI_SUBAGENT_DEBUG
    ? (msg: string) => {
        try {
          require("node:fs").appendFileSync(
            "/tmp/subagent-debug.log",
            `[${new Date().toISOString()}] ${msg}\n`,
          );
        } catch {}
      }
    : () => {};

  // 1. Pick a runs dir. Project-local if .pi/ exists, else user-scoped.
  // Either way, files live OUTSIDE ~/.pi/agent/sessions/ so they don't
  // pollute the /resume picker.
  const projectPi = join(ctx.cwd, ".pi");
  const runsDir = existsSync(projectPi)
    ? join(projectPi, "subagent-runs")
    : join(process.env.HOME!, ".pi", "agent", "subagent-runs");
  mkdirSync(runsDir, { recursive: true });

  // 2. Create a fresh child session in that dir.
  const childSm = SessionManager.create(ctx.cwd, runsDir);
  dbg(`childSm file=${childSm.getSessionFile()}`);

  // 3. getBranch() returns chronological (root → leaf), despite the
  // "walk from entry to root" doc phrasing. Verified empirically; do NOT
  // reverse. Truncate at our own in-flight tool call so the child doesn't
  // load a session ending in an orphan tool call. (Ivan's "safe branch".)
  const chronological = ctx.sessionManager.getBranch();
  const safeBranch = truncateAtToolCall(chronological, toolCallId);
  dbg(`branch=${chronological.length} safe=${safeBranch.length}`);

  // 4. Filter and replay.
  for (const entry of safeBranch) {
    replayFiltered(entry, childSm);
  }

  return childSm.getSessionFile()!;
}

/**
 * Walk the branch from the leaf side, find the assistant message containing
 * the given toolCallId, return everything BEFORE it. If not found, return
 * the full branch unchanged.
 */
function truncateAtToolCall(branch: any[], toolCallId: string): any[] {
  for (let i = branch.length - 1; i >= 0; i--) {
    const e = branch[i];
    if (e.type !== "message" || e.message?.role !== "assistant") continue;
    const content = e.message.content;
    if (!Array.isArray(content)) continue;
    const hasOurCall = content.some(
      (c: any) => c.type === "toolCall" && c.id === toolCallId,
    );
    if (hasOurCall) return branch.slice(0, i);
  }
  return branch;
}

/**
 * Conservative filter: keep most history; only drop thinking blocks from
 * assistant messages and truncate oversize tool results.
 *
 * Skipped entirely: model_change, thinking_level_change, label, session_info,
 * branch_summary, custom (extension state). The child picks its own model
 * via CLI/settings; bookmarks don't translate; branch summaries are
 * structurally tricky to replay; custom state is extension-private.
 */
const TOOL_RESULT_TOKEN_LIMIT = 5000;

// Tools that the parent has but the child won't, so we strip references
// to them from inherited history. Currently just `subagent` (blocked in
// the child by the PI_AGENT_TEAM_CHILD recursion guard).
const CHILD_BLOCKED_TOOLS = new Set(["subagent"]);

function replayFiltered(entry: any, dest: SessionManager): void {
  if (entry.type === "compaction") {
    // Preserve "earlier conversation was summarized" markers.
    dest.appendCompaction(
      entry.summary,
      entry.firstKeptEntryId,
      entry.tokensBefore,
      entry.details,
      entry.fromHook,
    );
    return;
  }

  if (entry.type === "custom_message") {
    // Extension-injected messages that ARE part of LLM context. Pass
    // through unchanged — they may carry meaningful project/state context.
    dest.appendCustomMessageEntry(
      entry.customType,
      entry.content,
      entry.display,
      entry.details,
    );
    return;
  }

  if (entry.type !== "message") return;
  const m = entry.message;

  if (m.role === "assistant" && Array.isArray(m.content)) {
    // Strip thinking blocks AND any tool calls to tools the child won't
    // have. Right now that's just `subagent` (blocked by recursion guard).
    // Without this strip, the child sees a transcript full of subagent
    // calls, pattern-matches "this is how I answer", and tries to call
    // subagent itself — only to hit a "tool not found" wall.
    const filtered = m.content
      .filter((c: any) => c.type !== "thinking")
      .filter((c: any) => !(c.type === "toolCall" && CHILD_BLOCKED_TOOLS.has(c.name)));
    if (filtered.length === 0) return;
    dest.appendMessage({ ...m, content: filtered });
    return;
  }

  if (m.role === "toolResult") {
    // Drop results for blocked tools — otherwise they become orphan
    // toolResults with no matching toolCall in the child's view.
    if (CHILD_BLOCKED_TOOLS.has(m.toolName)) return;

    // Crude token estimate: 4 chars/token. Truncate oversize bodies but
    // preserve the call/result correlation (the LLM still sees that the
    // call happened and roughly what it produced).
    const approxTokens = Math.round(JSON.stringify(m.content).length / 4);
    if (approxTokens > TOOL_RESULT_TOKEN_LIMIT) {
      dest.appendMessage({
        ...m,
        content: [{
          type: "text",
          text: `[truncated: ~${approxTokens} tokens of ${m.toolName} result]`,
        }],
      });
      return;
    }
  }

  // user, toolResult (small), bashExecution, others: pass through.
  dest.appendMessage(m);
}

// --- json-mode parser -------------------------------------------------------

/**
 * Parses pi's `--mode json` event stream (see /usr/local/bin/pi_cli/docs/json.md).
 * Accumulates finalized assistant messages plus the in-flight draft text
 * so we can:
 *   - extract the final answer (last assistant message's text content)
 *   - stream a clean preview to the parent TUI as the child works
 *   - sum usage across turns
 *   - detect stopReason="error"/"length"/"aborted"
 *   - surface stderr if the child dies before producing anything
 */
class JsonModeParser {
  private buffer = "";
  private finals: any[] = [];
  private draftText = "";
  private currentTool: string | null = null;

  push(chunk: string, onPreview: (preview: string) => void): void {
    this.buffer += chunk;
    const lines = this.buffer.split("\n");
    this.buffer = lines.pop() ?? ""; // hold partial trailing line
    for (const line of lines) {
      if (!line.trim()) continue;
      let evt: any;
      try {
        evt = JSON.parse(line);
      } catch {
        continue; // non-JSON noise; harmless to ignore
      }
      this.handle(evt, onPreview);
    }
  }

  private handle(evt: any, onPreview: (preview: string) => void): void {
    if (evt.type === "message_update" && evt.message?.role === "assistant") {
      this.draftText = textOf(evt.message);
      onPreview(this.preview());
      return;
    }
    if (evt.type === "message_end" && evt.message?.role === "assistant") {
      this.finals.push(evt.message);
      this.draftText = ""; // committed; clear streaming draft
      onPreview(this.preview());
      return;
    }
    if (evt.type === "tool_execution_start") {
      this.currentTool = evt.toolName;
      onPreview(this.preview());
      return;
    }
    if (evt.type === "tool_execution_end") {
      this.currentTool = null;
      onPreview(this.preview());
      return;
    }
  }

  private preview(): string {
    const committedTexts = this.finals.map(textOf).filter(Boolean).join("\n\n");
    const live = [committedTexts, this.draftText].filter(Boolean).join("\n\n");
    return this.currentTool
      ? `${live}\n[child running tool: ${this.currentTool}]`
      : live;
  }

  toResult(exitCode: number, stderr: string, killReason?: string): any {
    const last = this.finals[this.finals.length - 1];

    // Killed by parent (timeout, silence, or abort) — surface the reason
    // even if we got partial output.
    if (killReason) {
      const partial = last ? textOf(last).trim() : "";
      return {
        content: [{
          type: "text",
          text: `Subagent killed: ${killReason}.${
            partial ? `\n\nPartial output:\n${partial}` : ""
          }${stderr.trim() ? `\n\nstderr:\n${stderr.trim()}` : ""}`,
        }],
        details: last
          ? {
              killReason,
              stopReason: last.stopReason,
              model: `${last.provider}/${last.model}`,
              usage: sumUsage(this.finals),
            }
          : { killReason },
        isError: true,
      };
    }

    // No assistant output at all → child died early.
    if (!last) {
      return {
        content: [{
          type: "text",
          text: `Subagent produced no output (exit ${exitCode}).\nstderr:\n${stderr.trim() || "(empty)"}`,
        }],
        isError: true,
      };
    }

    const answer = textOf(last).trim() || "(empty)";
    const stopReason = last.stopReason;
    const details = {
      stopReason,
      model: `${last.provider}/${last.model}`,
      usage: sumUsage(this.finals),
    };

    if (exitCode !== 0 || stopReason === "error") {
      const reason = last.errorMessage ?? `stopReason=${stopReason}, exit=${exitCode}`;
      return {
        content: [{
          type: "text",
          text: `Subagent failed: ${reason}\n\nPartial output:\n${answer}\n\nstderr:\n${stderr.trim() || "(empty)"}`,
        }],
        details,
        isError: true,
      };
    }

    if (stopReason === "length") {
      return {
        content: [{
          type: "text",
          text: `${answer}\n\n[note: subagent stopped at context limit; answer may be incomplete]`,
        }],
        details,
      };
    }

    return {
      content: [{ type: "text", text: answer }],
      details,
    };
  }
}

function textOf(msg: any): string {
  if (!msg || !Array.isArray(msg.content)) return "";
  return msg.content
    .filter((c: any) => c.type === "text")
    .map((c: any) => c.text)
    .join("");
}

function sumUsage(msgs: any[]): {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
  cost: number;
} {
  let input = 0, output = 0, cacheRead = 0, cacheWrite = 0, cost = 0;
  for (const m of msgs) {
    const u = m.usage ?? {};
    input += u.input ?? 0;
    output += u.output ?? 0;
    cacheRead += u.cacheRead ?? 0;
    cacheWrite += u.cacheWrite ?? 0;
    cost += u.cost?.total ?? 0;
  }
  return { input, output, cacheRead, cacheWrite, cost };
}
