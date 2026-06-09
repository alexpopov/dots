import { SessionManager, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { spawn, spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { randomUUID } from "node:crypto";

// --- tunables ---------------------------------------------------------------
// Defaults can be overridden by env vars (great for dotsync-wide changes) or
// per-call via the `timeoutSeconds` / `silentForSeconds` tool parameters.
const DEFAULT_TIMEOUT_SECONDS = Number(process.env.PI_SUBAGENT_TIMEOUT) || 600;
// Default bumped from 120 → 300: with the active-tool deferral below, long
// silences only happen between tool calls (LLM thinking, slow API), so 5 min
// is a safer "something is genuinely stuck" threshold.
const DEFAULT_SILENT_SECONDS = Number(process.env.PI_SUBAGENT_SILENCE) || 300;
// Grace period between SIGTERM and SIGKILL when killing a hung child.
const SIGKILL_GRACE_MS = 5_000;
// How often to poll for liveness signals.
const SILENCE_CHECK_INTERVAL_MS = 10_000;
const MTIME_CHECK_INTERVAL_MS = 5_000;

// Supervise-specific defaults.
const DEFAULT_MAX_ITERATIONS = Number(process.env.PI_SUPERVISE_MAX_ITERATIONS) || 5;
const ORACLE_TIMEOUT_SECONDS = Number(process.env.PI_SUPERVISE_ORACLE_TIMEOUT) || 300;

// Render helpers used by all three tools (subagent / council / supervise) to
// suppress per-call rendering. tool-aggregator.ts owns the consolidated
// widget + summary; here we just opt out of the default boxed renderer.
// Errored tool results still render inline so the user sees failure context.
const EMPTY_COMPONENT = { render: () => [], invalidate: () => {} };

function renderEmpty() {
  return EMPTY_COMPONENT;
}

function renderResultEmptyOrError(toolName: string) {
  return (result: any, _options: any, theme: any) => {
    if (!result.isError) return EMPTY_COMPONENT;
    const content = result.content;
    const text = Array.isArray(content)
      ? content.filter((c: any) => c.type === "text").map((c: any) => c.text).join("\n")
      : String(content ?? "");
    return new Text(theme.fg("error", `${toolName} error: `) + (text || "(no detail)"), 0, 0);
  };
}

// --- factory ----------------------------------------------------------------

export default function (pi: ExtensionAPI) {
  // Recursion guard: children load this file too, but the env var makes
  // them return before registering. One env var, one early-return.
  if (process.env.PI_AGENT_TEAM_CHILD === "1") return;

  // ----- subagent: one child, optional context inheritance -----------------
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
      return runOnePi({
        prompt: params.prompt,
        mode: params.mode ?? "fresh",
        contextHint: params.contextHint,
        timeoutSeconds: params.timeoutSeconds ?? DEFAULT_TIMEOUT_SECONDS,
        silentForSeconds: params.silentForSeconds ?? DEFAULT_SILENT_SECONDS,
        ctx,
        parentToolCallId: toolCallId,
        signal,
        onPreview: (preview) =>
          onUpdate?.({ content: [{ type: "text", text: preview }] }),
      });
    },

    renderShell: "self",
    renderCall: renderEmpty,
    renderResult: renderResultEmptyOrError("subagent"),
  });

  // ----- council: N children in parallel, aggregated result ----------------
  pi.registerTool({
    name: "council",
    label: "Council",
    description:
      "Run N subagents in parallel and return all their answers. Use for: " +
      "multi-model comparison (ask different models the same question), " +
      "parallelizable subtasks (split work N ways), " +
      "multi-perspective review (one member per lens — security, perf, etc.).\n\n" +
      "Each member runs as an independent pi subprocess with its own prompt, " +
      "model, and mode. No coordination between members. Results are returned " +
      "as one text block per member, headed by `## <label>`. Failures don't " +
      "abort the council — partial success is fine.\n\n" +
      "Always-fresh-by-default like subagent. Each member can opt into " +
      "mode='inherit' for parent context.",

    parameters: Type.Object({
      members: Type.Array(
        Type.Object({
          prompt: Type.String({ description: "This member's task." }),
          model: Type.Optional(Type.String({
            description: "Override the default pi model for this member. " +
              "Accepts ids, provider-prefixed ids, or patterns " +
              "(e.g. 'claude-opus-4-8', 'anthropic/claude-opus-4-8', 'opus').",
          })),
          mode: Type.Optional(StringEnum(["fresh", "inherit"] as const)),
          contextHint: Type.Optional(Type.String()),
          label: Type.Optional(Type.String({
            description: "Display label for this member in the result. " +
              "Falls back to the model id, then to M<n>.",
          })),
        }),
        { minItems: 1 },
      ),
      timeoutSeconds: Type.Optional(Type.Integer({ minimum: 1 })),
      silentForSeconds: Type.Optional(Type.Integer({ minimum: 0 })),
    }),

    async execute(toolCallId, params, signal, onUpdate, ctx) {
      const timeoutSeconds = params.timeoutSeconds ?? DEFAULT_TIMEOUT_SECONDS;
      const silentForSeconds = params.silentForSeconds ?? DEFAULT_SILENT_SECONDS;
      const N = params.members.length;

      // Per-member preview state. Combined into one TUI display.
      type MemberState = {
        state: "pending" | "running" | "done" | "failed";
        preview: string;
      };
      const states: MemberState[] = Array.from({ length: N }, () => ({
        state: "pending",
        preview: "",
      }));

      const flushPreview = () => {
        const blocks = states.map((s, i) => {
          const label = labelFor(params.members[i], i);
          const body = s.preview || (s.state === "pending" ? "(waiting)" : "(no output yet)");
          return `## ${label} [${s.state}]\n${body}`;
        });
        onUpdate?.({ content: [{ type: "text", text: blocks.join("\n\n") }] });
      };

      // Spawn all members in parallel. runOnePi handles abort/timeout/etc.
      // per child; failures resolve as { isError: true } results, not throws.
      const promises = params.members.map((member, idx) => {
        states[idx].state = "running";
        return runOnePi({
          prompt: member.prompt,
          mode: member.mode ?? "fresh",
          contextHint: member.contextHint,
          model: member.model,
          timeoutSeconds,
          silentForSeconds,
          ctx,
          parentToolCallId: toolCallId,
          signal,
          onPreview: (p) => {
            states[idx].preview = p;
            flushPreview();
          },
        }).then((result) => {
          states[idx] = {
            state: result.isError ? "failed" : "done",
            preview: extractText(result),
          };
          flushPreview();
          return { member, result, label: labelFor(member, idx) };
        });
      });

      flushPreview(); // initial paint with everyone running
      const completed = await Promise.all(promises);

      return aggregateCouncil(completed);
    },

    renderShell: "self",
    renderCall: renderEmpty,
    renderResult: renderResultEmptyOrError("council"),
  });

  // ----- supervise: dispatcher → executor → oracle → supervisor loop -------
  const superviseParams = Type.Object({
    task: Type.String({ description: "The work to supervise." }),
    maxIterations: Type.Optional(Type.Integer({ minimum: 1 })),
    oracleRequired: Type.Optional(Type.Boolean({
      description: "If true (default), the dispatcher must produce an oracle and " +
        "the oracle must call at least one oracle_assert* helper.",
    })),
    dispatcherModel: Type.Optional(Type.String()),
    executorModel: Type.Optional(Type.String()),
    supervisorModel: Type.Optional(Type.String()),
    autoApprove: Type.Optional(Type.Boolean({
      description: "Skip the user-approval editor and use the dispatcher's output " +
        "verbatim. Set automatically when ctx.hasUI is false (e.g. pi -p mode).",
    })),
  });

  pi.registerTool({
    name: "supervise",
    label: "Supervise",
    description:
      "Run a task through a three-role gated loop: dispatcher → executor → oracle → " +
      "supervisor. The dispatcher plans the work and writes a Definition of Done plus " +
      "a deterministic bash oracle. After user approval (skipped if autoApprove or no " +
      "UI), the executor implements, the oracle runs as a hard check, the supervisor " +
      "audits. Loop completes only when supervisor says COMPLETE AND DoD met AND oracle " +
      "passed. Max iterations bounds runaway loops. Use for important work where you " +
      "want a quality gate, not just 'the LLM says it's done'.",

    parameters: superviseParams,

    async execute(toolCallId, params, signal, onUpdate, ctx) {
      return runSupervise(params as any, ctx, signal, (preview) =>
        onUpdate?.({ content: [{ type: "text", text: preview }] }));
    },

    renderShell: "self",
    renderCall: renderEmpty,
    renderResult: renderResultEmptyOrError("supervise"),
  });

  pi.registerCommand("supervise", {
    description: "Run a task through the dispatcher/executor/supervisor loop.",
    handler: async (args: string, ctx: any) => {
      const task = (args ?? "").trim();
      if (!task) {
        ctx.ui.notify("Usage: /supervise <task>", "error");
        return;
      }
      const result = await runSupervise({ task }, ctx, undefined, (preview) =>
        ctx.ui.setWidget("supervise", preview.split("\n")));
      ctx.ui.setWidget("supervise", []); // clear
      // Inject result back into the parent session so the LLM can see it.
      pi.sendMessage({
        customType: "supervise",
        content: extractText(result),
        display: true,
        details: result.details,
      });
    },
  });
}

// --- shared spawn/parse helper ----------------------------------------------

interface RunOnePiOptions {
  prompt: string;
  mode: "fresh" | "inherit";
  contextHint?: string;
  model?: string;
  timeoutSeconds: number;
  silentForSeconds: number;
  ctx: any;
  parentToolCallId: string;
  signal?: AbortSignal;
  onPreview?: (preview: string) => void;
}

/**
 * Spawn one pi subprocess and return a ToolResult shape. All complexity
 * lives here: arg construction, child session snapshot, kill machinery,
 * JSONL parsing, result aggregation. Both `subagent` and `council` use it.
 */
async function runOnePi(opts: RunOnePiOptions): Promise<any> {
  const fullPrompt = opts.contextHint
    ? `${opts.contextHint}\n\n${opts.prompt}`
    : opts.prompt;

  // (B) Build CLI args. `--mode json` for structured output; `--model`
  // overrides default per-member; `--session` only in inherit mode (also
  // gives us a path to mtime-watch for liveness).
  const args: string[] = ["--mode", "json"];
  if (opts.model) args.push("--model", opts.model);
  let childSessionFile: string | undefined;
  if (opts.mode === "inherit") {
    childSessionFile = buildChildSession(opts.ctx, opts.parentToolCallId);
    args.push("--session", childSessionFile);
  }
  args.push("-p", fullPrompt);

  // (C) Spawn. PI_AGENT_TEAM_CHILD=1 triggers the recursion guard above.
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
  opts.signal?.addEventListener("abort", onAbort);

  // (F) Parse JSONL events as they arrive.
  const parser = new JsonModeParser();
  let stderr = "";
  child.stdout.on("data", (chunk) => {
    bumpActivity();
    parser.push(chunk.toString(), (preview) => {
      opts.onPreview?.(preview);
    });
  });
  child.stderr.on("data", (chunk) => {
    bumpActivity();
    stderr += chunk.toString();
  });

  // (G) Hard timeout — absolute upper bound on runtime.
  const hardTimer = setTimeout(
    () => killChild(`timeout after ${opts.timeoutSeconds}s`),
    opts.timeoutSeconds * 1000,
  );

  // (H) Silence watcher — kill if no activity for too long.
  // Defers to the hard timeout when the child has a tool call in flight:
  // a long-running bash subprocess (e.g. `wrig sync`) produces no events
  // between `tool_execution_start` and `tool_execution_end`, so naive
  // stdout-only silence detection would false-positive on real work. The
  // hard timeoutSeconds remains the absolute backstop.
  const silenceTimer = opts.silentForSeconds > 0
    ? setInterval(() => {
        if (parser.hasActiveTool()) return;
        const silentMs = Date.now() - lastActivity;
        if (silentMs > opts.silentForSeconds * 1000) {
          killChild(`silent for ${Math.round(silentMs / 1000)}s`);
        }
      }, SILENCE_CHECK_INTERVAL_MS)
    : null;

  // (I) Mtime watcher — only available in inherit mode.
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
  opts.signal?.removeEventListener("abort", onAbort);
  clearTimeout(hardTimer);
  if (silenceTimer) clearInterval(silenceTimer);
  if (mtimeTimer) clearInterval(mtimeTimer);

  return parser.toResult(exitCode, stderr, killReason);
}

// --- council aggregation ----------------------------------------------------

interface MemberSpec {
  prompt: string;
  model?: string;
  mode?: "fresh" | "inherit";
  contextHint?: string;
  label?: string;
}

function labelFor(member: MemberSpec, idx: number): string {
  return member.label ?? member.model ?? `M${idx + 1}`;
}

function extractText(result: { content: Array<{ type: string; text?: string }> }): string {
  return result.content
    .filter((c) => c.type === "text" && c.text)
    .map((c) => c.text!)
    .join("\n");
}

interface CompletedMember {
  member: MemberSpec;
  result: any;
  label: string;
}

function aggregateCouncil(completed: CompletedMember[]): any {
  const successCount = completed.filter((c) => !c.result.isError).length;
  const total = completed.length;

  const blocks: string[] = [];
  blocks.push(`## Council summary: ${successCount}/${total} succeeded`);
  for (const c of completed) {
    const body = extractText(c.result);
    blocks.push(`## ${c.label}\n${body}`);
  }

  const totalCost = completed.reduce(
    (sum, c) => sum + (c.result.details?.usage?.cost ?? 0),
    0,
  );

  return {
    content: [{ type: "text", text: blocks.join("\n\n") }],
    details: {
      members: completed.map((c) => ({
        label: c.label,
        model: c.member.model,
        mode: c.member.mode ?? "fresh",
        isError: !!c.result.isError,
        stopReason: c.result.details?.stopReason,
        killReason: c.result.details?.killReason,
        usage: c.result.details?.usage,
      })),
      totalCost,
      successCount,
      totalCount: total,
    },
    // Only flag the whole council as failed when nobody succeeded.
    isError: successCount === 0,
  };
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
// to them from inherited history. All three are blocked in the child by
// the PI_AGENT_TEAM_CHILD recursion guard.
const CHILD_BLOCKED_TOOLS = new Set(["subagent", "council", "supervise"]);

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
    // have. Without this strip, the child sees a transcript full of
    // subagent/council calls, pattern-matches "this is how I answer", and
    // tries to call them itself — only to hit a "tool not found" wall.
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

  /** True while the child has a tool call in flight. Used by the silence
   *  watcher to defer kills when the child is doing real work that just
   *  happens to be quiet on stdout (e.g. a long bash subprocess). */
  hasActiveTool(): boolean {
    return this.currentTool !== null;
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

// ===========================================================================
// SUPERVISE LOOP
// Dispatcher → user approval → executor → oracle → supervisor → decide.
// Faithful port of the key mechanics from Ivan Gromov's /supervise-loop
// (fbsource/users/iv/ivangromov/subagent/supervise.ts), simplified to a
// subprocess-based, single-agent-per-role implementation.
// ===========================================================================

// --- prompt templates -------------------------------------------------------

const DISPATCHER_CONTEXT = `You are the dispatcher in a three-role pi supervised loop. Plan work so an executor can do it and a supervisor can verify it.

Your output MUST contain these sections, exactly as named (## headers):

## Definition of Done
- Concrete, verifiable items the supervisor will check. Must include at least one actionable bullet.

## Deterministic Oracle
\`\`\`bash
# bash script body that returns 0 iff the work is correct.
# Use the harness helpers; the wrapper runs with set -euo pipefail and counts
# oracle_assert* calls — zero assertions means exit 97.
#
# Available helpers:
#   oracle_assert <cmd...>                 — run cmd; assert exit 0
#   oracle_assert_match <file> <pattern>   — ripgrep finds at least one match
#   oracle_assert_no_match <file> <pat>    — ripgrep finds zero matches
#   oracle_assert_file_exists <path>
#
# Env available:
#   PI_SUPERVISE_ORACLE_STATE_DIR  — writable scratch (state across iterations)
#   PI_SUPERVISE_RUN_DIR           — the run root
#   PI_SUPERVISE_ITERATION         — current iteration number
\`\`\`

## Execution Plan
1. Step-by-step plan the executor will follow.

## Validation Plan
- Commands or evidence the supervisor should look at to corroborate (beyond the oracle).

Guidelines:
- The oracle is FROZEN at user approval. Make it robust. Prefer asserting on specific files
  / specific patterns over vague "build succeeds" checks.
- Definition of Done items must be specific enough that another model could verify them
  from the working tree alone.
- Do not include ## Feedback for dispatcher, ## User-approved Definition of Done, or
  ## User-approved Deterministic Oracle headers — those are reserved for the approval editor.
`;

const EXECUTOR_CONTEXT = `You are the executor in a three-role pi supervised loop.

Implement the work in the approved package below. You have full read/write/bash tools.
When done, produce a concise execution report describing exactly what you changed and
how to verify it. The supervisor will check your work; do not skip steps or claim done
without evidence.
`;

const SUPERVISOR_CONTEXT = `# Supervise loop — supervisor role

You are the supervisor in a three-role pi loop.

Responsibilities:
- Inspect actual working-tree evidence against the user-approved Definition of Done.
- Treat the deterministic oracle output as harness evidence. If oracle exited non-zero
  or timed out, FINAL_DOD_MET must be NO and DECISION cannot be COMPLETE.
- The oracle code is immutable after user approval. If the oracle itself is invalid,
  return ASK_USER or BLOCKED with a proposed replacement and explain that re-approval
  is required.
- Do not accept partial completion, placeholders, skipped tests, or executor confidence
  without evidence.
- Ask the user for clarification when the Definition of Done cannot be evaluated or
  scope is ambiguous.

Start your answer with exactly these three lines:
DECISION: COMPLETE | REPAIR | ASK_USER | BLOCKED
FINAL_DOD_MET: YES | NO
ITERATION_ACCEPTED: YES | NO

Rules:
- Use DECISION: COMPLETE only when the Definition of Done is fully satisfied AND
  FINAL_DOD_MET is YES.
- If this iteration's executor succeeded but final DoD is still unmet, use
  DECISION: REPAIR, FINAL_DOD_MET: NO, ITERATION_ACCEPTED: YES.
- Use DECISION: ASK_USER or BLOCKED when user input is required.

Then provide concise evidence and concrete repair instructions when not complete.
`;

// --- main entrypoint --------------------------------------------------------

interface SuperviseOptions {
  task: string;
  maxIterations?: number;
  oracleRequired?: boolean;
  dispatcherModel?: string;
  executorModel?: string;
  supervisorModel?: string;
  autoApprove?: boolean;
}

async function runSupervise(
  opts: SuperviseOptions,
  ctx: any,
  signal?: AbortSignal,
  onPreview?: (preview: string) => void,
): Promise<any> {
  const maxIterations = opts.maxIterations ?? DEFAULT_MAX_ITERATIONS;
  const oracleRequired = opts.oracleRequired ?? true;
  const autoApprove = opts.autoApprove ?? !ctx.hasUI; // print/RPC mode auto-approves

  const runDir = makeRunDir(ctx.cwd, opts.task);
  mkdirSync(join(runDir, "oracle", "state"), { recursive: true });
  mkdirSync(join(runDir, "oracle", "runs"), { recursive: true });
  mkdirSync(join(runDir, "evidence"), { recursive: true });
  const log = (msg: string) => onPreview?.(`run: ${runDir}\n${msg}`);

  // --- 1. dispatcher (initial) --
  log("dispatcher: planning...");
  let dispatcherOutput = await runRole({
    role: "dispatcher",
    prompt: buildDispatcherPrompt(opts.task, null),
    model: opts.dispatcherModel,
    ctx, signal,
  });
  writeFileSync(join(runDir, "dispatcher-initial.md"), dispatcherOutput);

  // --- 2. user approval loop --
  let approvedPlan: string;
  let approvedOracleCode: string;
  if (autoApprove) {
    approvedPlan = dispatcherOutput;
    approvedOracleCode = extractCodeBlock(extractSection(dispatcherOutput, "Deterministic Oracle"));
    if (oracleRequired && !approvedOracleCode) {
      return failResult(`autoApprove: dispatcher did not produce an oracle, but oracleRequired=true.\nDispatcher output written to ${runDir}/dispatcher-initial.md`, runDir);
    }
  } else {
    log("waiting for user approval...");
    const approval = await promptForApprovedPlan(opts.task, dispatcherOutput, ctx, oracleRequired,
      // re-dispatcher callback for "send back for replan"
      async (feedback) => {
        const revised = await runRole({
          role: "dispatcher",
          prompt: buildDispatcherFeedbackPrompt(opts.task, dispatcherOutput, feedback),
          model: opts.dispatcherModel,
          ctx, signal,
        });
        dispatcherOutput = revised;
        writeFileSync(join(runDir, `dispatcher-feedback-${Date.now()}.md`), revised);
        return revised;
      });
    if (approval === null) {
      return failResult("User cancelled supervise.", runDir);
    }
    approvedPlan = approval.approvedPackage;
    approvedOracleCode = approval.oracleCode;
  }
  writeFileSync(join(runDir, "user-approved-plan.md"), approvedPlan);

  // --- 3. freeze oracle --
  const frozenOracleFile = join(runDir, "oracle", "oracle.sh");
  writeFileSync(frozenOracleFile, approvedOracleCode || "", { mode: 0o400 });
  chmodSync(frozenOracleFile, 0o400); // belt-and-braces

  // --- 4. main loop --
  const baselineEvidence = collectVcsEvidence(ctx.cwd);
  writeFileSync(join(runDir, "evidence", "attempt-0-status.txt"), baselineEvidence.status);
  writeFileSync(join(runDir, "evidence", "attempt-0-diff.patch"), baselineEvidence.diff);

  let loopContext = "";
  let lastSupervisorReport = "";
  let finalDecision: "COMPLETE" | "REPAIR" | "ASK_USER" | "BLOCKED" | "STOPPED" = "REPAIR";
  let finalIteration = 0;
  let executionReport = "";
  let oracleResult: { exitCode: number; output: string; assertions: number } | null = null;

  for (let iteration = 1; iteration <= maxIterations; iteration++) {
    finalIteration = iteration;
    log(`iteration ${iteration}/${maxIterations}: executor working...`);

    // dispatcher re-plan on iteration > 1
    if (iteration > 1) {
      dispatcherOutput = await runRole({
        role: "dispatcher",
        prompt: buildDispatcherPrompt(opts.task, loopContext),
        model: opts.dispatcherModel,
        ctx, signal,
      });
      writeFileSync(join(runDir, `dispatcher-iteration-${iteration}.md`), dispatcherOutput);
    }

    // executor
    executionReport = await runRole({
      role: "executor",
      prompt: buildExecutorPrompt(approvedPlan, iteration, maxIterations, loopContext),
      model: opts.executorModel,
      ctx, signal,
    });
    writeFileSync(join(runDir, `execution-iteration-${iteration}.md`), executionReport);

    // oracle
    log(`iteration ${iteration}: oracle running...`);
    oracleResult = approvedOracleCode
      ? runOracle({
          frozenOracleFile,
          runDir,
          iteration,
          requireAssertion: oracleRequired,
        })
      : null;
    if (oracleResult) {
      writeFileSync(
        join(runDir, "oracle", "runs", `oracle-iteration-${iteration}.txt`),
        `exit=${oracleResult.exitCode} assertions=${oracleResult.assertions}\n${oracleResult.output}`,
      );
    }

    // evidence
    const currentEvidence = collectVcsEvidence(ctx.cwd);
    writeFileSync(join(runDir, "evidence", `attempt-${iteration}-status.txt`), currentEvidence.status);
    writeFileSync(join(runDir, "evidence", `attempt-${iteration}-diff.patch`), currentEvidence.diff);

    // supervisor
    log(`iteration ${iteration}: supervisor auditing...`);
    const supervisorReport = await runRole({
      role: "supervisor",
      prompt: buildSupervisorPrompt({
        approvedPlan,
        executionReport,
        oracleResult,
        baseline: baselineEvidence,
        current: currentEvidence,
      }),
      model: opts.supervisorModel,
      ctx, signal,
    });
    lastSupervisorReport = supervisorReport;

    const verdict = parseSupervisorVerdict(supervisorReport);
    const oracleFailed = oracleRequired && oracleResult && oracleResult.exitCode !== 0;
    let decision = verdict.effectiveDecision;
    let downgrades = [...verdict.downgrades];
    if (oracleFailed && decision === "COMPLETE") {
      decision = "REPAIR";
      downgrades.push("oracle_failed_overrides_complete");
    }

    writeFileSync(
      join(runDir, `supervisor-iteration-${iteration}.md`),
      `${supervisorReport}\n\n---\n\nverdict: decision=${decision} dod=${verdict.finalDodMet} iter=${verdict.iterationAccepted} downgrades=[${downgrades.join(", ")}]\noracle: ${
        oracleResult ? `exit=${oracleResult.exitCode} assertions=${oracleResult.assertions}` : "(none)"
      }`,
    );

    finalDecision = decision;

    if (decision === "COMPLETE") {
      log(`iteration ${iteration}: COMPLETE`);
      break;
    }

    if (decision === "ASK_USER" || decision === "BLOCKED") {
      if (autoApprove) {
        // No way to get user input; bail.
        log(`iteration ${iteration}: ${decision} but autoApprove — bailing`);
        break;
      }
      log(`iteration ${iteration}: ${decision} — awaiting user`);
      const response = await ctx.ui.editor(
        `${decision}: supervisor needs input`,
        `# Supervisor said: ${decision}\n# Edit your response below; save to continue or clear and save to abort.\n\n${supervisorReport}\n\n---\n\n## Your response\n`,
      );
      const userResponse = (response ?? "").split("## Your response").slice(-1)[0]?.trim();
      if (!userResponse) {
        finalDecision = "STOPPED";
        break;
      }
      writeFileSync(join(runDir, `user-response-iteration-${iteration}.md`), userResponse);
      loopContext = `## Previous supervisor verdict (${decision})\n${supervisorReport}\n\n## User response\n${userResponse}`;
      finalDecision = "REPAIR";
      continue;
    }

    // REPAIR
    loopContext = `## Approved plan (unchanged)\n${approvedPlan}\n\n## Previous supervisor verdict\n${supervisorReport}\n\n## Repair instructions\nSee supervisor's repair guidance above.`;
  }

  if (finalDecision === "REPAIR" && finalIteration >= maxIterations) {
    finalDecision = "ASK_USER";
    lastSupervisorReport = `Max iterations (${maxIterations}) exhausted.\n\nLast supervisor verdict:\n${lastSupervisorReport}`;
  }

  // --- 5. summary --
  const summary = buildSupervisorSummary({
    runDir, task: opts.task, finalDecision, finalIteration, maxIterations,
    lastSupervisorReport, oracleResult,
  });
  writeFileSync(join(runDir, "summary.md"), summary);

  return {
    content: [{ type: "text", text: summary }],
    details: {
      runDir,
      finalDecision,
      iterations: finalIteration,
      maxIterations,
    },
    isError: finalDecision !== "COMPLETE",
  };
}

// --- role execution (thin wrapper around runOnePi) --------------------------

interface RunRoleArgs {
  role: "dispatcher" | "executor" | "supervisor";
  prompt: string;
  model?: string;
  ctx: any;
  signal?: AbortSignal;
}

async function runRole(args: RunRoleArgs): Promise<string> {
  const systemContext = {
    dispatcher: DISPATCHER_CONTEXT,
    executor: EXECUTOR_CONTEXT,
    supervisor: SUPERVISOR_CONTEXT,
  }[args.role];

  // Roles see system context via --append-system-prompt; user prompt is the
  // task-specific body. Subagent execution mode = fresh (no parent inherit).
  const result = await runOnePi({
    prompt: `${systemContext}\n\n${args.prompt}`,
    mode: "fresh",
    timeoutSeconds: DEFAULT_TIMEOUT_SECONDS,
    silentForSeconds: DEFAULT_SILENT_SECONDS,
    ctx: args.ctx,
    parentToolCallId: "supervise-role-call", // synthetic; not used in fresh mode
    model: args.model,
    signal: args.signal,
  });

  return extractText(result);
}

// --- prompt builders --------------------------------------------------------

function buildDispatcherPrompt(task: string, loopContext: string | null): string {
  let body = `## User request\n${task}\n`;
  if (loopContext) {
    body += `\n## Previous loop context\n${loopContext}\n\nProduce a revised plan addressing the repair instructions above.`;
  }
  return body;
}

function buildDispatcherFeedbackPrompt(task: string, prevOutput: string, feedback: string): string {
  return `## User request\n${task}\n\n## Your previous plan\n${prevOutput}\n\n## User feedback\n${feedback}\n\nReturn a complete replacement plan (with all the standard sections) addressing this feedback.`;
}

function buildExecutorPrompt(approvedPlan: string, iteration: number, max: number, loopContext: string): string {
  let body = `## Approved package\n${approvedPlan}\n\n## Iteration\n${iteration} of ${max}`;
  if (loopContext) body += `\n\n## Repair instructions\n${loopContext}`;
  body += `\n\nImplement the work. When done, produce an execution report.`;
  return body;
}

interface SupervisorPromptArgs {
  approvedPlan: string;
  executionReport: string;
  oracleResult: { exitCode: number; output: string; assertions: number } | null;
  baseline: { status: string; diff: string };
  current: { status: string; diff: string };
}

function buildSupervisorPrompt(a: SupervisorPromptArgs): string {
  const oracleSection = a.oracleResult
    ? `exit=${a.oracleResult.exitCode} assertions=${a.oracleResult.assertions}\n\n${tail(a.oracleResult.output, 30_000)}`
    : "(no oracle configured)";
  return `## User-approved task package
${a.approvedPlan}

## Execution report
${a.executionReport}

## Deterministic oracle result
${oracleSection}

## Baseline evidence (before loop started)
### status
${tail(a.baseline.status, 5000)}

### diff
${tail(a.baseline.diff, 10000)}

## Current evidence (after this iteration)
### status
${tail(a.current.status, 5000)}

### diff
${tail(a.current.diff, 10000)}
`;
}

// --- user approval ----------------------------------------------------------

interface ApprovalResult {
  approvedPackage: string;
  oracleCode: string;
}

async function promptForApprovedPlan(
  task: string,
  initialDispatcherOutput: string,
  ctx: any,
  oracleRequired: boolean,
  rerunDispatcher: (feedback: string) => Promise<string>,
): Promise<ApprovalResult | null> {
  let dispatcherOutput = initialDispatcherOutput;
  let draft = buildApprovalTemplate(task, dispatcherOutput);

  for (let attempt = 0; attempt < 20; attempt++) {
    const edited = await ctx.ui.editor(
      "Review supervise plan",
      draft,
    );
    if (edited == null) return null; // user cancelled

    const feedback = extractDispatcherFeedback(edited);
    if (feedback) {
      ctx.ui.notify("Sending back to dispatcher with your feedback...", "info");
      dispatcherOutput = await rerunDispatcher(feedback);
      draft = buildApprovalTemplate(task, dispatcherOutput);
      continue;
    }

    const dod = extractSection(edited, "User-approved Definition of Done");
    const oracleSection = extractSection(edited, "User-approved Deterministic Oracle");
    const oracleCode = extractCodeBlock(oracleSection);

    if (!hasActionableLine(dod)) {
      ctx.ui.notify("Approval requires at least one concrete DoD item OR feedback for dispatcher.", "error");
      draft = edited;
      continue;
    }
    if (oracleRequired && !oracleCode) {
      ctx.ui.notify("oracleRequired=true but no oracle code block found. Edit the oracle section or send feedback.", "error");
      draft = edited;
      continue;
    }

    // Approved.
    return { approvedPackage: edited, oracleCode };
  }
  return null;
}

function buildApprovalTemplate(task: string, dispatcherOutput: string): string {
  const proposedDod = extractSection(dispatcherOutput, "Definition of Done") || "- ";
  const proposedOracle = extractSection(dispatcherOutput, "Deterministic Oracle") || "NONE";
  return `# Review before starting /supervise
# To send back to dispatcher: replace NONE under 'Feedback for dispatcher' and save.
# To approve: leave Feedback as NONE; edit DoD/Oracle if needed.
# After approval, the oracle is FROZEN for the run.
# Use $PI_SUPERVISE_ORACLE_STATE_DIR for mutable oracle state.
# By default the oracle must call at least one oracle_assert* helper.

## Original task
${task}

## Feedback for dispatcher
NONE

## User-approved Definition of Done
${proposedDod}

## User-approved Deterministic Oracle
${proposedOracle}

## User clarifications / constraints
-

## Dispatcher proposed plan
${dispatcherOutput}
`;
}

function extractDispatcherFeedback(text: string): string | null {
  const section = extractSection(text, "Feedback for dispatcher");
  if (!section) return null;
  // "NONE", blank, comments-only, or just "-" / "- " all count as "no feedback".
  const lines = section.split("\n").filter((l) => {
    const t = l.trim();
    return t && !t.startsWith("#") && !/^NONE\b/i.test(t) && t !== "-" && t !== "- " && /[A-Za-z0-9]/.test(t);
  });
  if (lines.length === 0) return null;
  return section.trim();
}

function extractSection(text: string, headerName: string): string {
  // Match `## <headerName>` up to the next `## ` or end-of-string.
  const re = new RegExp(`^##\\s+${escapeRegex(headerName)}\\s*$\\n([\\s\\S]*?)(?=^##\\s|\\Z)`, "im");
  const m = re.exec(text);
  return m ? m[1].trim() : "";
}

function extractCodeBlock(text: string): string {
  const m = /```(?:bash|sh)?\n([\s\S]*?)```/i.exec(text);
  return m ? m[1] : "";
}

function hasActionableLine(text: string): boolean {
  if (!text) return false;
  for (const raw of text.split("\n")) {
    const t = raw.trim();
    if (!t) continue;
    if (t.startsWith("#")) continue;
    if (/^NONE\b/i.test(t)) continue;
    if (t === "-" || t === "- ") continue;
    if (/[A-Za-z0-9]/.test(t)) return true;
  }
  return false;
}

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// --- oracle execution -------------------------------------------------------

interface RunOracleArgs {
  frozenOracleFile: string;
  runDir: string;
  iteration: number;
  requireAssertion: boolean;
}

function runOracle(a: RunOracleArgs): { exitCode: number; output: string; assertions: number } {
  const wrapperPath = join(a.runDir, "oracle", "runs", `oracle-iteration-${a.iteration}.sh`);
  writeFileSync(wrapperPath, buildOracleWrapper(a.requireAssertion), { mode: 0o700 });

  const res = spawnSync("bash", [wrapperPath], {
    cwd: process.cwd(),
    env: {
      ...process.env,
      PI_SUPERVISE_ORACLE: "1",
      PI_SUPERVISE_ORACLE_CODE: a.frozenOracleFile,
      PI_SUPERVISE_ORACLE_STATE_DIR: join(a.runDir, "oracle", "state"),
      PI_SUPERVISE_ORACLE_REQUIRE_ASSERTION: a.requireAssertion ? "1" : "0",
      PI_SUPERVISE_RUN_DIR: a.runDir,
      PI_SUPERVISE_ITERATION: String(a.iteration),
    },
    timeout: ORACLE_TIMEOUT_SECONDS * 1000,
    encoding: "utf8",
  });

  const output = `${res.stdout ?? ""}${res.stderr ? `\n--- stderr ---\n${res.stderr}` : ""}`;
  // Assertion count — we don't have a direct way to read the bash counter from
  // the parent, so we look for the exit-97 sentinel as a proxy for "zero".
  const assertions = res.status === 97 ? 0 : -1; // -1 = unknown but presumed >0
  return {
    exitCode: res.status ?? -1,
    output,
    assertions,
  };
}

function buildOracleWrapper(requireAssertion: boolean): string {
  const guard = requireAssertion
    ? `\nif [[ \${__pi_oracle_assertions:-0} -eq 0 ]]; then echo '[oracle] no oracle_assert* helper was called; add an explicit pass/fail assertion.' >&2; exit 97; fi\n`
    : "";
  return `#!/bin/bash
set -euo pipefail
__pi_oracle_assertions=0
oracle_assert() { __pi_oracle_assertions=$((__pi_oracle_assertions + 1)); "$@"; }
oracle_assert_match() { __pi_oracle_assertions=$((__pi_oracle_assertions + 1)); local file="$1"; local pattern="$2"; rg -n -- "$pattern" "$file" >/dev/null; }
oracle_assert_no_match() { __pi_oracle_assertions=$((__pi_oracle_assertions + 1)); local file="$1"; local pattern="$2"; if rg -n -- "$pattern" "$file"; then return 1; fi; }
oracle_assert_file_exists() { __pi_oracle_assertions=$((__pi_oracle_assertions + 1)); test -e "$1"; }
source "$PI_SUPERVISE_ORACLE_CODE"${guard}`;
}

// --- supervisor verdict parsing --------------------------------------------

interface SupervisorVerdict {
  rawDecision: string;
  effectiveDecision: "COMPLETE" | "REPAIR" | "ASK_USER" | "BLOCKED" | "STOPPED";
  finalDodMet: "YES" | "NO" | "UNKNOWN";
  iterationAccepted: "YES" | "NO" | "UNKNOWN";
  downgrades: string[];
}

function parseSupervisorVerdict(text: string): SupervisorVerdict {
  const rawDecision = match(text, /^\s*DECISION\s*:\s*(APPROVE|REPAIR|ASK_USER|BLOCKED|COMPLETE|STOPPED)\b/im) ?? "UNKNOWN";
  const finalDodMet = (match(text, /^\s*FINAL_DOD_MET\s*:\s*(YES|NO)\b/im) ?? "UNKNOWN") as any;
  const iterationAccepted = (match(text, /^\s*ITERATION_ACCEPTED\s*:\s*(YES|NO)\b/im) ?? "UNKNOWN") as any;

  let effectiveDecision = rawDecision as any;
  const downgrades: string[] = [];

  if (rawDecision === "COMPLETE" && finalDodMet !== "YES") {
    effectiveDecision = "REPAIR";
    downgrades.push(finalDodMet === "NO" ? "complete_with_final_dod_no" : "complete_missing_final_dod");
  }
  if (rawDecision === "APPROVE") {
    effectiveDecision = "REPAIR";
    downgrades.push("approve_is_not_valid_for_supervise");
  }
  if (rawDecision === "UNKNOWN") {
    effectiveDecision = "REPAIR";
    downgrades.push("decision_unparseable");
  }

  return { rawDecision, effectiveDecision, finalDodMet, iterationAccepted, downgrades };
}

function match(text: string, re: RegExp): string | null {
  const m = re.exec(text);
  return m ? m[1].toUpperCase() : null;
}

// --- VCS evidence (git / sapling / hg) -------------------------------------

function collectVcsEvidence(cwd: string): { status: string; diff: string } {
  // Auto-detect: try sl, hg, then git.
  for (const vcs of ["sl", "hg", "git"] as const) {
    try {
      const status = spawnSync(vcs, ["status"], { cwd, encoding: "utf8", timeout: 10_000 });
      if (status.status === 0 || (status.stdout ?? "").length > 0) {
        const diff = spawnSync(vcs, ["diff"], { cwd, encoding: "utf8", timeout: 30_000 });
        return {
          status: `[${vcs} status]\n${status.stdout ?? ""}`,
          diff: `[${vcs} diff]\n${diff.stdout ?? ""}`,
        };
      }
    } catch {}
  }
  return { status: "(no VCS detected)", diff: "" };
}

// --- run dir + slug ---------------------------------------------------------

function makeRunDir(cwd: string, task: string): string {
  const projectPi = join(cwd, ".pi");
  const root = existsSync(projectPi)
    ? join(projectPi, "supervise-runs")
    : join(process.env.HOME!, ".pi", "agent", "supervise-runs");
  const iso = new Date().toISOString().replace(/[:.]/g, "-");
  const slug = safeSlug(task).slice(0, 40) || "task";
  const id = randomUUID().replace(/-/g, "").slice(0, 8);
  const runDir = join(root, `${iso}-${slug}-${id}`);
  mkdirSync(runDir, { recursive: true });
  return runDir;
}

function safeSlug(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
}

// --- summary + failure helpers ----------------------------------------------

interface SummaryArgs {
  runDir: string;
  task: string;
  finalDecision: string;
  finalIteration: number;
  maxIterations: number;
  lastSupervisorReport: string;
  oracleResult: { exitCode: number; output: string; assertions: number } | null;
}

function buildSupervisorSummary(a: SummaryArgs): string {
  const oracleLine = a.oracleResult
    ? `oracle: exit=${a.oracleResult.exitCode} assertions=${a.oracleResult.assertions}`
    : "oracle: (none)";
  return `# Supervise summary

- task: ${a.task}
- final decision: ${a.finalDecision}
- iterations: ${a.finalIteration}/${a.maxIterations}
- ${oracleLine}
- run dir: ${a.runDir}

## Last supervisor report
${a.lastSupervisorReport || "(none)"}
`;
}

function failResult(message: string, runDir?: string): any {
  return {
    content: [{ type: "text", text: message }],
    details: runDir ? { runDir } : {},
    isError: true,
  };
}

// --- misc helpers -----------------------------------------------------------

function tail(s: string, maxChars: number): string {
  if (s.length <= maxChars) return s;
  return `[truncated leading ${s.length - maxChars} chars]\n${s.slice(-maxChars)}`;
}
