import {
  AuthStorage,
  createAgentSession,
  DefaultResourceLoader,
  getAgentDir,
  ModelRegistry,
  SessionManager,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import {
  Box,
  CURSOR_MARKER,
  Key,
  matchesKey,
  Text,
  truncateToWidth,
  visibleWidth,
  wrapTextWithAnsi,
} from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { spawn, spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
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
// /supervise-loop only: an in-process SDK agent that emits no event for this
// long is considered hung and aborted. Any streamed text / thinking / tool
// event resets the timer, so this is wall-clock-of-silence, not total runtime.
const DEFAULT_HEALTH_TIMEOUT_SECONDS = Number(process.env.PI_SUPERVISE_HEALTH_TIMEOUT) || 600;

// Side-kick defaults. A side-kick is a long-lived in-process agent the main
// agent can talk to repeatedly across tool calls. The health-timeout bounds a
// single send (no SDK event for this long → that send is aborted; the
// side-kick stays alive for the next send).
const DEFAULT_SIDEKICK_HEALTH_SECONDS = Number(process.env.PI_SIDEKICK_HEALTH_TIMEOUT) || 600;
const DEFAULT_SIDEKICK_NAME = "sidekick";
const DEFAULT_SIDEKICK_ROLE =
  "You are a side-kick agent working alongside a primary agent in the same " +
  "project. The primary agent delegates focused work to you and will talk to " +
  "you repeatedly, so remember what you've done across messages. Be concise, " +
  "do the work concretely (use your tools), and end each reply with the " +
  "result the primary agent needs — not a restatement of the request.";

// --- settings loading -------------------------------------------------------
// Read ~/.pi/agent/settings.json (global) and ./.pi/settings.json (project).
// Project keys override global keys, per-block (matches Ivan's pattern in
// fbsource/users/iv/ivangromov/subagent/supervise.ts). Defaults are
// preserved: with no settings present, behavior is identical to a fresh
// install. Each call site reads settings at execute() time so /reload
// picks up changes.

interface SubagentSettings {
  model?: string;
  tools?: string;
  timeoutSeconds?: number;
  silentForSeconds?: number;
}

interface CouncilMemberSettings {
  label?: string;
  model?: string;
  tools?: string;
  mode?: "fresh" | "inherit";
  contextHint?: string;
}

interface CouncilSettings {
  tools?: string;
  timeoutSeconds?: number;
  silentForSeconds?: number;
  members?: CouncilMemberSettings[];
}

interface SupervisorMemberConfig {
  label?: string;
  model?: string;
  tools?: string;
}

interface SuperviseSettingsBlock {
  dispatcherModel?: string;
  executorModel?: string;
  supervisorModel?: string;
  // Panel of supervisors voted-on conservatively (ASK_USER > BLOCKED >
  // REPAIR > COMPLETE). If omitted, defaults to a single member configured
  // by supervisorModel — i.e. behavior is identical to pre-panel days.
  supervisorMembers?: SupervisorMemberConfig[];
  maxIterations?: number;
  oracleRequired?: boolean;
  timeoutSeconds?: number;
  silentForSeconds?: number;
  // /supervise-loop only: per-agent health-timeout (seconds of no SDK event).
  healthTimeoutSeconds?: number;
}

interface SidekickSettings {
  model?: string;
  tools?: string;
  // Per-send health-timeout (seconds of no SDK event) before that send is
  // aborted. The side-kick survives — only the in-flight send is killed.
  healthTimeoutSeconds?: number;
}

interface AllSettings {
  subagent: SubagentSettings;
  council: CouncilSettings;
  supervise: SuperviseSettingsBlock;
  sidekick: SidekickSettings;
  sources: Array<{ path: string; exists: boolean; blocks: string[] }>;
}

function readJsonSafe(path: string): any {
  try {
    return JSON.parse(readFileSync(path, "utf-8"));
  } catch {
    return undefined;
  }
}

function loadSettings(cwd: string): AllSettings {
  const globalPath = join(homedir(), ".pi", "agent", "settings.json");
  const projectPath = join(cwd, ".pi", "settings.json");
  const merged: AllSettings = {
    subagent: {},
    council: {},
    supervise: {},
    sidekick: {},
    sources: [],
  };
  for (const p of [globalPath, projectPath]) {
    const exists = existsSync(p);
    const obj = exists ? readJsonSafe(p) : undefined;
    const blocks: string[] = [];
    if (obj?.subagent && typeof obj.subagent === "object") {
      Object.assign(merged.subagent, obj.subagent);
      blocks.push("subagent");
    }
    if (obj?.council && typeof obj.council === "object") {
      // Members array: project wins entirely; don't try to merge per-member.
      Object.assign(merged.council, obj.council);
      blocks.push("council");
    }
    if (obj?.supervise && typeof obj.supervise === "object") {
      Object.assign(merged.supervise, obj.supervise);
      blocks.push("supervise");
    }
    if (obj?.sidekick && typeof obj.sidekick === "object") {
      Object.assign(merged.sidekick, obj.sidekick);
      blocks.push("sidekick");
    }
    merged.sources.push({ path: p, exists, blocks });
  }
  return merged;
}

// Default council roster used by /council when no settings.council.members
// is configured. Picked for diversity: Opus (deep), Sonnet (fast/strong),
// Haiku (cheap second opinion).
const DEFAULT_COUNCIL_ROSTER: CouncilMemberSettings[] = [
  { label: "opus", model: "anthropic/claude-opus-4-8" },
  { label: "sonnet", model: "anthropic/claude-sonnet-4-6" },
  { label: "haiku", model: "anthropic/claude-haiku-4-5" },
];

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
      model: Type.Optional(Type.String({
        description: "Override the default pi model for this subagent run. " +
          "Accepts ids, provider-prefixed ids, or patterns " +
          "(e.g. 'claude-opus-4-8', 'anthropic/claude-sonnet-4-6', 'sonnet'). " +
          "Use a cheaper model like Sonnet or Haiku for simple subtasks; " +
          "match the parent (default) for complex work.",
      })),
      tools: Type.Optional(Type.String({
        description: "Comma-separated tool allowlist for the child (e.g. " +
          "'read,grep,find,ls' for a recon-only subagent). Restricts what " +
          "the child can do — useful when delegating a self-contained " +
          "investigation that should not be able to edit files or run bash. " +
          "Defaults to settings.subagent.tools, then to pi's default (all tools).",
      })),
      timeoutSeconds: Type.Optional(Type.Integer({
        minimum: 0,
        description: `Hard upper bound on child runtime. Defaults to ${DEFAULT_TIMEOUT_SECONDS}s. After this, the child gets SIGTERM, then SIGKILL ${SIGKILL_GRACE_MS / 1000}s later. Set to 0 for NO hard timeout (long-running assistant) — pair with silentForSeconds=0 to also disable the silence watcher, or keep silentForSeconds>0 as a safety net.`,
      })),
      silentForSeconds: Type.Optional(Type.Integer({
        minimum: 0,
        description: `Kill the child if it produces no stdout/stderr/session-file activity for this long. Defaults to ${DEFAULT_SILENT_SECONDS}s. Set to 0 to disable the silence check.`,
      })),
    }),

    async execute(toolCallId, params, signal, onUpdate, ctx) {
      const s = loadSettings(ctx.cwd).subagent;
      return runOnePi({
        prompt: params.prompt,
        mode: params.mode ?? "fresh",
        contextHint: params.contextHint,
        model: params.model ?? s.model,
        tools: params.tools ?? s.tools,
        timeoutSeconds: params.timeoutSeconds ?? s.timeoutSeconds ?? DEFAULT_TIMEOUT_SECONDS,
        silentForSeconds: params.silentForSeconds ?? s.silentForSeconds ?? DEFAULT_SILENT_SECONDS,
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
          tools: Type.Optional(Type.String({
            description: "Comma-separated tool allowlist for this member " +
              "(e.g. 'read,grep,find,ls'). Falls back to settings.council.tools.",
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
      const csettings = loadSettings(ctx.cwd).council;
      const timeoutSeconds = params.timeoutSeconds ?? csettings.timeoutSeconds ?? DEFAULT_TIMEOUT_SECONDS;
      const silentForSeconds = params.silentForSeconds ?? csettings.silentForSeconds ?? DEFAULT_SILENT_SECONDS;
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
          tools: member.tools ?? csettings.tools,
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

  // ----- /council: ask the configured roster a single prompt ---------------
  pi.registerCommand("council", {
    description:
      "Ask the configured council roster a single prompt. Each member runs " +
      "in parallel; all answers are returned to the chat. Roster comes from " +
      "settings.council.members (see /council-status); falls back to a " +
      "Opus/Sonnet/Haiku default.",
    handler: async (args: string, ctx: any) => {
      const prompt = (args ?? "").trim();
      if (!prompt) {
        ctx.ui.notify("Usage: /council <prompt>", "error");
        return;
      }
      const all = loadSettings(ctx.cwd);
      const c = all.council;
      const roster = c.members ?? DEFAULT_COUNCIL_ROSTER;
      if (roster.length === 0) {
        ctx.ui.notify("Council roster is empty. Configure settings.council.members.", "error");
        return;
      }
      const timeoutSeconds = c.timeoutSeconds ?? DEFAULT_TIMEOUT_SECONDS;
      const silentForSeconds = c.silentForSeconds ?? DEFAULT_SILENT_SECONDS;

      // Status line while running. tool-aggregator owns the main widget; we
      // use our own key so the two don't fight.
      const updateStatus = (msg: string) => {
        try { ctx.ui.setWidget("council-slash", [msg]); } catch {}
      };
      updateStatus(`council: ${roster.length} members starting…`);

      const states = roster.map(() => "pending" as "pending" | "running" | "done" | "failed");
      const flushStatus = () => {
        const counts = {
          done: states.filter((s) => s === "done").length,
          failed: states.filter((s) => s === "failed").length,
          running: states.filter((s) => s === "running").length,
        };
        updateStatus(`council: ${counts.done}/${roster.length} done, ${counts.running} running${counts.failed ? `, ${counts.failed} failed` : ""}`);
      };

      const promises = roster.map((member, idx) => {
        const label = member.label ?? member.model ?? `M${idx + 1}`;
        states[idx] = "running";
        flushStatus();
        return runOnePi({
          prompt,
          mode: member.mode ?? "fresh",
          contextHint: member.contextHint,
          model: member.model,
          tools: member.tools ?? c.tools,
          timeoutSeconds,
          silentForSeconds,
          ctx,
          parentToolCallId: "slash-council",
        }).then((result) => {
          states[idx] = result.isError ? "failed" : "done";
          flushStatus();
          return { member, result, label };
        });
      });

      const completed = await Promise.all(promises);
      try { ctx.ui.setWidget("council-slash", []); } catch {}
      const aggregated = aggregateCouncil(completed);
      pi.sendMessage({
        customType: "council",
        content: extractText(aggregated),
        display: true,
        details: aggregated.details,
      });
    },
  });

  // ----- diagnostic /status commands ---------------------------------------
  // Print resolved settings so you can debug "is my config picked up?"
  // without restarting pi. Modeled on Ivan's /supervise-status.
  pi.registerCommand("subagent-status", {
    description: "Show resolved subagent settings (defaults vs overrides).",
    handler: async (_args: string, ctx: any) => {
      const all = loadSettings(ctx.cwd);
      ctx.ui.notify(formatSubagentStatus(all), "info");
    },
  });
  pi.registerCommand("council-status", {
    description: "Show resolved council settings (roster + defaults).",
    handler: async (_args: string, ctx: any) => {
      const all = loadSettings(ctx.cwd);
      ctx.ui.notify(formatCouncilStatus(all), "info");
    },
  });
  pi.registerCommand("supervise-status", {
    description: "Show resolved supervise settings (models, oracle, iterations).",
    handler: async (_args: string, ctx: any) => {
      const all = loadSettings(ctx.cwd);
      ctx.ui.notify(formatSuperviseStatus(all), "info");
    },
  });

  // ----- /supervise-loop: in-process SDK agents + live modal ---------------
  // Same dispatcher → approve → executor → oracle → supervisor loop as
  // /supervise, but roles run in-process via createAgentSession (not pi -p
  // subprocesses), which lets us stream their text/thinking/tool events into
  // a live modal and steer them mid-run with @tags. Use /supervise for a
  // quick fire-and-forget run; /supervise-loop when you want to watch and
  // course-correct.
  pi.registerCommand("supervise-loop", {
    description: "Supervise loop with a live modal: watch agents stream, steer with @tags mid-run.",
    handler: async (args: string, ctx: any) => {
      const task = (args ?? "").trim();
      if (!task) {
        ctx.ui.notify("Usage: /supervise-loop <task>", "error");
        return;
      }
      if (!ctx.hasUI) {
        ctx.ui.notify("/supervise-loop needs an interactive UI. Use the supervise tool or /supervise in -p mode.", "error");
        return;
      }
      await runSuperviseLoop(task, ctx);
    },
  });

  // ----- side-kick: a long-lived agent the main agent talks to repeatedly ---
  // Unlike `subagent` (one-shot subprocess), a side-kick is an in-process
  // session kept alive in a registry across tool calls, so it accumulates its
  // own history and remembers prior exchanges.
  pi.registerTool({
    name: "sidekick_start",
    label: "Sidekick Start",
    description:
      "Start a long-lived side-kick agent you can talk to repeatedly with " +
      "sidekick_send. Unlike `subagent` (one-shot), a side-kick keeps its own " +
      "conversation history across sends, so it remembers what it has done — a " +
      "companion for a sustained sub-thread (e.g. a researcher that builds up " +
      "knowledge, or a worker that owns one module).\n\n" +
      "All params optional: name (default 'sidekick'; use distinct names to run " +
      "several at once), role (standing instructions), model, tools allowlist. " +
      "You can also skip this and call sidekick_send directly — it auto-starts " +
      "a default side-kick.",
    parameters: Type.Object({
      name: Type.Optional(Type.String({ description: "Side-kick name. Default 'sidekick'. Use distinct names to run several." })),
      role: Type.Optional(Type.String({ description: "Standing instructions / persona. Delivered once, with the first message." })),
      model: Type.Optional(Type.String({ description: "Model override (e.g. 'sonnet', 'anthropic/claude-opus-4-8'). Defaults to settings.sidekick.model, then pi default." })),
      tools: Type.Optional(Type.String({ description: "Comma-separated tool allowlist (e.g. 'read,grep,find,ls'). Defaults to settings.sidekick.tools, then pi default." })),
    }),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      const name = (params.name ?? DEFAULT_SIDEKICK_NAME).trim() || DEFAULT_SIDEKICK_NAME;
      const existing = sidekicks.get(name);
      if (existing) {
        return { content: [{ type: "text", text: `Side-kick '${name}' already exists (${existing.handle.status}). Use sidekick_send to talk to it, or sidekick_stop to replace it.` }], isError: true };
      }
      const s = loadSettings(ctx.cwd).sidekick;
      try {
        await startSidekick({
          name,
          role: (params.role ?? "").trim() || DEFAULT_SIDEKICK_ROLE,
          model: params.model ?? s.model,
          tools: params.tools ?? s.tools,
          cwd: ctx.cwd,
          healthTimeoutMs: (s.healthTimeoutSeconds ?? DEFAULT_SIDEKICK_HEALTH_SECONDS) * 1000,
        });
        return { content: [{ type: "text", text: `Side-kick '${name}' started. Talk to it: sidekick_send({ name: "${name}", message: ... }).` }] };
      } catch (err: any) {
        return { content: [{ type: "text", text: `Failed to start side-kick '${name}': ${err?.message ?? err}` }], isError: true };
      }
    },
    renderShell: "self",
    renderCall: renderEmpty,
    renderResult: renderResultEmptyOrError("sidekick_start"),
  });

  pi.registerTool({
    name: "sidekick_send",
    label: "Sidekick Send",
    description:
      "Send a message to a side-kick and get its reply. The side-kick remembers " +
      "your earlier messages to it (it has its own running history). If the named " +
      "side-kick doesn't exist yet, it's auto-created with default settings — so " +
      "for a quick companion you can just call this directly. Use sidekick_start " +
      "first when you want a specific role / model / tools.",
    parameters: Type.Object({
      message: Type.String({ description: "What to say to the side-kick." }),
      name: Type.Optional(Type.String({ description: "Side-kick name. Default 'sidekick'." })),
      model: Type.Optional(Type.String({ description: "Only used if the side-kick must be auto-created; ignored if it already exists." })),
      tools: Type.Optional(Type.String({ description: "Only used if the side-kick must be auto-created." })),
    }),
    async execute(_id, params, signal, onUpdate, ctx) {
      const name = (params.name ?? DEFAULT_SIDEKICK_NAME).trim() || DEFAULT_SIDEKICK_NAME;
      let entry = sidekicks.get(name);
      if (!entry) {
        const s = loadSettings(ctx.cwd).sidekick;
        try {
          entry = await startSidekick({
            name,
            role: DEFAULT_SIDEKICK_ROLE,
            model: params.model ?? s.model,
            tools: params.tools ?? s.tools,
            cwd: ctx.cwd,
            healthTimeoutMs: (s.healthTimeoutSeconds ?? DEFAULT_SIDEKICK_HEALTH_SECONDS) * 1000,
          });
        } catch (err: any) {
          return { content: [{ type: "text", text: `Failed to start side-kick '${name}': ${err?.message ?? err}` }], isError: true };
        }
      }
      if (entry.handle.status === "running") {
        return { content: [{ type: "text", text: `Side-kick '${name}' is still working on a previous message. Wait for it to finish before sending another.` }], isError: true };
      }
      // The role rides along with the first message only; after that the
      // side-kick remembers it, so later sends are bare user turns.
      const text = entry.firstSendDone
        ? params.message
        : `You are operating as a side-kick agent. Your standing role:\n${entry.role}\n\nFirst message from the primary agent:\n${params.message}`;
      entry.streamBuf = "";
      entry.onPreview = (t) => onUpdate?.({ content: [{ type: "text", text: t }] });
      const onAbort = () => { void entry!.handle.abort(); };
      signal?.addEventListener("abort", onAbort);
      try {
        const res = await entry.handle.prompt(text);
        entry.firstSendDone = true;
        entry.sends++;
        const body = res.report?.trim() || "(side-kick returned no text)";
        return {
          content: [{ type: "text", text: body }],
          isError: !res.ok,
          details: { name, sends: entry.sends, status: entry.handle.status, error: res.error },
        };
      } finally {
        signal?.removeEventListener("abort", onAbort);
        entry.onPreview = undefined;
      }
    },
    renderShell: "self",
    renderCall: renderEmpty,
    renderResult: renderResultEmptyOrError("sidekick_send"),
  });

  pi.registerTool({
    name: "sidekick_stop",
    label: "Sidekick Stop",
    description: "Stop a side-kick and free its resources. Its conversation is discarded. Default name 'sidekick'.",
    parameters: Type.Object({
      name: Type.Optional(Type.String({ description: "Side-kick name. Default 'sidekick'." })),
    }),
    async execute(_id, params, _signal, _onUpdate, _ctx) {
      const name = (params.name ?? DEFAULT_SIDEKICK_NAME).trim() || DEFAULT_SIDEKICK_NAME;
      const ok = disposeSidekick(name);
      if (!ok) {
        const active = [...sidekicks.keys()];
        return { content: [{ type: "text", text: `No side-kick named '${name}'.${active.length ? ` Active: ${active.join(", ")}.` : " None active."}` }], isError: true };
      }
      return { content: [{ type: "text", text: `Side-kick '${name}' stopped.` }] };
    },
    renderShell: "self",
    renderCall: renderEmpty,
    renderResult: renderResultEmptyOrError("sidekick_stop"),
  });

  pi.registerCommand("sidekick", {
    description: "Inspect side-kicks: /sidekick (list), /sidekick stop <name>, /sidekick stop-all.",
    handler: async (args: string, ctx: any) => {
      const a = (args ?? "").trim();
      if (!a || a === "list") {
        if (sidekicks.size === 0) { ctx.ui.notify("No active side-kicks.", "info"); return; }
        ctx.ui.notify(["active side-kicks:", ...[...sidekicks.values()].map((e) => "  " + sidekickSummaryLine(e))].join("\n"), "info");
        return;
      }
      if (a === "stop-all") {
        const n = sidekicks.size;
        for (const name of [...sidekicks.keys()]) disposeSidekick(name);
        ctx.ui.notify(`Stopped ${n} side-kick(s).`, "info");
        return;
      }
      const m = a.match(/^stop\s+(.+)$/);
      if (m) {
        const name = m[1].trim();
        const ok = disposeSidekick(name);
        ctx.ui.notify(ok ? `Stopped '${name}'.` : `No side-kick '${name}'.`, ok ? "info" : "warning");
        return;
      }
      ctx.ui.notify("Usage: /sidekick [list | stop <name> | stop-all]", "warning");
    },
  });

  // Tear down all side-kicks when the session ends so in-process sessions
  // don't linger. Registered in the parent only (factory early-returns in
  // children).
  pi.on("session_shutdown", () => {
    for (const name of [...sidekicks.keys()]) disposeSidekick(name);
  });
}

// --- settings formatters (used by /*-status commands) -----------------------

function fmtSettingsSources(all: AllSettings): string {
  return all.sources
    .map((src) => {
      if (!src.exists) return `  ${src.path}: (missing)`;
      if (src.blocks.length === 0) return `  ${src.path}: (no relevant blocks)`;
      return `  ${src.path}: ${src.blocks.join(", ")}`;
    })
    .join("\n");
}

function fmtMark(v: unknown): string {
  return v === undefined ? "(default)" : "(settings)";
}

function formatSubagentStatus(all: AllSettings): string {
  const s = all.subagent;
  return [
    "subagent — resolved settings",
    `  model           : ${s.model ?? "(pi default)"} ${fmtMark(s.model)}`,
    `  tools           : ${s.tools ?? "(all)"} ${fmtMark(s.tools)}`,
    `  timeoutSeconds  : ${s.timeoutSeconds ?? DEFAULT_TIMEOUT_SECONDS} ${fmtMark(s.timeoutSeconds)}`,
    `  silentForSeconds: ${s.silentForSeconds ?? DEFAULT_SILENT_SECONDS} ${fmtMark(s.silentForSeconds)}`,
    "",
    "sources",
    fmtSettingsSources(all),
  ].join("\n");
}

function formatCouncilStatus(all: AllSettings): string {
  const c = all.council;
  const roster = c.members ?? DEFAULT_COUNCIL_ROSTER;
  const rosterSrc = c.members ? "(settings)" : "(default roster)";
  const rosterLines = roster.map((m, i) => {
    const label = m.label ?? m.model ?? `M${i + 1}`;
    const extras = [
      m.tools ? `tools=${m.tools}` : null,
      m.mode ? `mode=${m.mode}` : null,
    ].filter(Boolean).join(" ");
    const suffix = extras ? `  [${extras}]` : "";
    return `    ${label.padEnd(8)}: ${m.model ?? "(pi default)"}${suffix}`;
  });
  return [
    "council — resolved settings",
    `  tools           : ${c.tools ?? "(per-member or pi default)"} ${fmtMark(c.tools)}`,
    `  timeoutSeconds  : ${c.timeoutSeconds ?? DEFAULT_TIMEOUT_SECONDS} ${fmtMark(c.timeoutSeconds)}`,
    `  silentForSeconds: ${c.silentForSeconds ?? DEFAULT_SILENT_SECONDS} ${fmtMark(c.silentForSeconds)}`,
    "",
    `  roster ${rosterSrc}:`,
    ...rosterLines,
    "",
    "sources",
    fmtSettingsSources(all),
  ].join("\n");
}

function formatSuperviseStatus(all: AllSettings): string {
  const s = all.supervise;
  const panel = s.supervisorMembers && s.supervisorMembers.length > 0
    ? s.supervisorMembers
    : [{ label: "supervisor", model: s.supervisorModel }];
  const panelSrc = s.supervisorMembers ? "(settings)" : "(single supervisor)";
  const panelLines = panel.map((m, i) => {
    const label = m.label ?? m.model ?? `M${i + 1}`;
    const extras = m.tools ? `  [tools=${m.tools}]` : "";
    return `    ${label.padEnd(12)}: ${m.model ?? "(pi default)"}${extras}`;
  });
  return [
    "supervise — resolved settings",
    `  dispatcherModel : ${s.dispatcherModel ?? "(pi default)"} ${fmtMark(s.dispatcherModel)}`,
    `  executorModel   : ${s.executorModel ?? "(pi default)"} ${fmtMark(s.executorModel)}`,
    `  supervisorModel : ${s.supervisorModel ?? "(pi default)"} ${fmtMark(s.supervisorModel)}`,
    `  maxIterations   : ${s.maxIterations ?? DEFAULT_MAX_ITERATIONS} ${fmtMark(s.maxIterations)}`,
    `  oracleRequired  : ${s.oracleRequired ?? true} ${fmtMark(s.oracleRequired)}`,
    `  healthTimeoutSec: ${s.healthTimeoutSeconds ?? DEFAULT_HEALTH_TIMEOUT_SECONDS} ${fmtMark(s.healthTimeoutSeconds)} (/supervise-loop only)`,
    "",
    `  supervisor panel ${panelSrc}:`,
    ...panelLines,
    "",
    "sources",
    fmtSettingsSources(all),
  ].join("\n");
}

// --- shared spawn/parse helper ----------------------------------------------

interface RunOnePiOptions {
  prompt: string;
  mode: "fresh" | "inherit";
  contextHint?: string;
  model?: string;
  tools?: string;
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
  if (opts.tools) args.push("--tools", opts.tools);
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

  // (G) Hard timeout — absolute upper bound on runtime. timeoutSeconds<=0
  // disables it entirely (no hard cap), mirroring silentForSeconds=0. The
  // child then runs until it exits, the parent aborts (Esc), or — if
  // silentForSeconds>0 — the silence watcher trips. Use with care: a truly
  // no-cap child can run forever if it also never goes silent.
  const hardTimer = opts.timeoutSeconds > 0
    ? setTimeout(
        () => killChild(`timeout after ${opts.timeoutSeconds}s`),
        opts.timeoutSeconds * 1000,
      )
    : null;

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
  if (hardTimer) clearTimeout(hardTimer);
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
  const ss = loadSettings(ctx.cwd).supervise;
  const maxIterations = opts.maxIterations ?? ss.maxIterations ?? DEFAULT_MAX_ITERATIONS;
  const oracleRequired = opts.oracleRequired ?? ss.oracleRequired ?? true;
  const dispatcherModel = opts.dispatcherModel ?? ss.dispatcherModel;
  const executorModel = opts.executorModel ?? ss.executorModel;
  const supervisorModel = opts.supervisorModel ?? ss.supervisorModel;
  // Panel: explicit array wins, else a single member from supervisorModel.
  // The single-member fast path keeps the existing artifact format intact.
  const supervisorPanel: SupervisorMemberConfig[] =
    ss.supervisorMembers && ss.supervisorMembers.length > 0
      ? ss.supervisorMembers
      : [{ label: "supervisor", model: supervisorModel }];
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
    model: dispatcherModel,
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
          model: dispatcherModel,
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
        model: dispatcherModel,
        ctx, signal,
      });
      writeFileSync(join(runDir, `dispatcher-iteration-${iteration}.md`), dispatcherOutput);
    }

    // executor
    executionReport = await runRole({
      role: "executor",
      prompt: buildExecutorPrompt(approvedPlan, iteration, maxIterations, loopContext),
      model: executorModel,
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

    // supervisor — panel of N if configured, else single member.
    log(`iteration ${iteration}: supervisor${supervisorPanel.length > 1 ? ` panel (${supervisorPanel.length})` : ""} auditing...`);
    const panel = await runSupervisorPanel({
      members: supervisorPanel,
      prompt: buildSupervisorPrompt({
        approvedPlan,
        executionReport,
        oracleResult,
        baseline: baselineEvidence,
        current: currentEvidence,
      }),
      ctx, signal,
    });
    lastSupervisorReport = panel.combinedReport;

    const verdict = panel.aggregated;
    const oracleFailed = oracleRequired && oracleResult && oracleResult.exitCode !== 0;
    let decision = verdict.effectiveDecision;
    let downgrades = [...verdict.downgrades];
    if (oracleFailed && decision === "COMPLETE") {
      decision = "REPAIR";
      downgrades.push("oracle_failed_overrides_complete");
    }

    writeFileSync(
      join(runDir, `supervisor-iteration-${iteration}.md`),
      `${panel.combinedReport}\n\n---\n\nverdict: decision=${decision} dod=${verdict.finalDodMet} iter=${verdict.iterationAccepted} downgrades=[${downgrades.join(", ")}] panel_size=${panel.members.length}\noracle: ${
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

// --- supervisor panel -------------------------------------------------------
// Spawn N supervisors in parallel and aggregate their verdicts conservatively.
// When the panel is size 1 (the default), behavior is byte-identical to the
// previous single-supervisor path: the same report, the same verdict.
//
// Aggregation rule (matches Ivan Gromov's aggregateLoopSupervisorVerdict in
// fbsource/users/iv/ivangromov/subagent/supervise.ts:1074):
//   ASK_USER > BLOCKED > REPAIR > COMPLETE.
// Any dissent demotes COMPLETE to REPAIR. Any single NO on FINAL_DOD_MET
// flips the panel to NO. Dissent is recorded in `downgrades` so the
// supervisor artifact explains why a unanimous-looking COMPLETE got demoted.

interface PanelMemberResult {
  label: string;
  report: string;
  verdict: SupervisorVerdict;
}

interface PanelResult {
  combinedReport: string;
  members: PanelMemberResult[];
  aggregated: SupervisorVerdict;
}

async function runSupervisorPanel(args: {
  members: SupervisorMemberConfig[];
  prompt: string;
  ctx: any;
  signal?: AbortSignal;
}): Promise<PanelResult> {
  const systemContext = SUPERVISOR_CONTEXT;
  const results: PanelMemberResult[] = await Promise.all(
    args.members.map(async (m, idx) => {
      const label = m.label ?? m.model ?? `supervisor-${idx + 1}`;
      const r = await runOnePi({
        prompt: `${systemContext}\n\n${args.prompt}`,
        mode: "fresh",
        timeoutSeconds: DEFAULT_TIMEOUT_SECONDS,
        silentForSeconds: DEFAULT_SILENT_SECONDS,
        ctx: args.ctx,
        parentToolCallId: `supervise-panel-${idx}`,
        model: m.model,
        tools: m.tools,
        signal: args.signal,
      });
      const report = extractText(r);
      return { label, report, verdict: parseSupervisorVerdict(report) };
    }),
  );

  // Size-1 fast path: keep the artifact format identical to pre-panel days.
  if (results.length === 1) {
    return { combinedReport: results[0].report, members: results, aggregated: results[0].verdict };
  }

  const combinedReport = results
    .map((r) => {
      const dgs = r.verdict.downgrades.length > 0 ? ` (downgrades: ${r.verdict.downgrades.join(", ")})` : "";
      return `## ${r.label} → ${r.verdict.effectiveDecision}${dgs}\n\n${r.report}`;
    })
    .join("\n\n---\n\n");

  return { combinedReport, members: results, aggregated: aggregatePanelVerdict(results) };
}

function aggregatePanelVerdict(members: PanelMemberResult[]): SupervisorVerdict {
  const decisions = members.map((m) => m.verdict.effectiveDecision);
  const downgrades: string[] = [];

  // Carry forward per-member downgrades labelled with the member name.
  for (const m of members) {
    for (const d of m.verdict.downgrades) downgrades.push(`${m.label}:${d}`);
  }

  // Conservative decision: any ASK_USER > any BLOCKED > any REPAIR > all COMPLETE.
  let effective: SupervisorVerdict["effectiveDecision"];
  if (decisions.includes("ASK_USER")) effective = "ASK_USER";
  else if (decisions.includes("BLOCKED")) effective = "BLOCKED";
  else if (decisions.includes("REPAIR")) effective = "REPAIR";
  else if (decisions.every((d) => d === "COMPLETE")) effective = "COMPLETE";
  else effective = "REPAIR";

  // YES only if unanimous; NO if any said NO; UNKNOWN otherwise.
  const dodMets = members.map((m) => m.verdict.finalDodMet);
  const finalDodMet: SupervisorVerdict["finalDodMet"] =
    dodMets.includes("NO") ? "NO" :
    dodMets.every((d) => d === "YES") ? "YES" :
    "UNKNOWN";

  const iters = members.map((m) => m.verdict.iterationAccepted);
  const iterationAccepted: SupervisorVerdict["iterationAccepted"] =
    iters.includes("NO") ? "NO" :
    iters.every((d) => d === "YES") ? "YES" :
    "UNKNOWN";

  // Demote COMPLETE if not unanimous on DoD met.
  if (effective === "COMPLETE" && finalDodMet !== "YES") {
    effective = "REPAIR";
    downgrades.push("panel:complete_but_dod_not_unanimous");
  }

  // Note dissent so the artifact explains a non-unanimous panel verdict.
  if (new Set(decisions).size > 1) {
    downgrades.push(`panel:dissent(${decisions.join(",")})`);
  }

  return {
    rawDecision: effective,
    effectiveDecision: effective,
    finalDodMet,
    iterationAccepted,
    downgrades,
  };
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

// ===========================================================================
// SUPERVISE LOOP (in-process) — /supervise-loop
// Same dispatcher → approve → executor → oracle → supervisor loop as
// /supervise, but each role runs in-process via createAgentSession instead
// of a `pi -p` subprocess. That lets us stream the agents' text / thinking /
// tool events into a live modal and steer them mid-run with @tags.
//
// Ported from Ivan Gromov's sdk-team.ts + supervise.ts (/supervise-loop),
// adapted to @earendil-works and folded onto this file's existing supervise
// machinery (oracle / evidence / prompt builders / verdict / panel).
// ===========================================================================

// --- in-process SDK agent runner --------------------------------------------

type SdkAgentStatus = "idle" | "running" | "done" | "error";

interface SdkEvent {
  tag: string;
  type: "text" | "thinking" | "tool-call" | "tool-result" | "status" | "error";
  text: string;
  toolName?: string;
  isError?: boolean;
}

interface SdkAgentHandle {
  tag: string;
  readonly status: SdkAgentStatus;
  readonly latestReport: string;
  prompt(prompt: string): Promise<{ ok: boolean; report: string; error?: string }>;
  steer(text: string): Promise<void>;
  abort(): Promise<void>;
  dispose(): void;
}

interface CreateSdkAgentOpts {
  tag: string;
  model?: string;
  tools?: string;
  context: string;
  cwd: string;
  healthTimeoutMs: number;
  onEvent?: (e: SdkEvent) => void;
}

const THINKING_LEVELS = new Set(["off", "minimal", "low", "medium", "high", "xhigh"]);

// "anthropic/claude-opus-4-8", "plugboard-codex/gpt-5.5", "opus",
// optionally with a trailing ":<thinking>" we strip.
function splitModelSpec(spec: string): { provider?: string; id: string } {
  let s = spec.trim();
  const colon = s.lastIndexOf(":");
  if (colon > 0 && THINKING_LEVELS.has(s.slice(colon + 1).toLowerCase())) {
    s = s.slice(0, colon);
  }
  const slash = s.indexOf("/");
  if (slash > 0) return { provider: s.slice(0, slash), id: s.slice(slash + 1) };
  return { id: s };
}

// Resolve a model string to a Model object via the registry. Returns
// undefined when unspecified OR unresolvable — caller then omits `model`
// and createAgentSession falls back to the settings default.
async function resolveModelSpec(registry: any, spec: string | undefined): Promise<any | undefined> {
  if (!spec) return undefined;
  const { provider, id } = splitModelSpec(spec);
  try {
    if (provider) {
      const found = registry.find?.(provider, id);
      if (found) return found;
    }
    const avail = (await registry.getAvailable?.()) ?? [];
    const lc = id.toLowerCase();
    const idOf = (m: any) => String(m?.id ?? m?.model ?? "").toLowerCase();
    return (
      avail.find((m: any) => idOf(m) === lc) ??
      avail.find((m: any) => idOf(m).includes(lc)) ??
      avail.find((m: any) => String(m?.name ?? "").toLowerCase().includes(lc))
    );
  } catch {
    return undefined;
  }
}

function parseToolsCsv(tools: string | undefined): string[] | undefined {
  if (!tools) return undefined;
  const arr = tools.split(",").map((t) => t.trim()).filter(Boolean);
  return arr.length ? arr : undefined;
}

// Set PI_AGENT_TEAM_CHILD=1 around in-process session creation so our own
// extensions early-return (no nested supervise/subagent registration) while
// the child session's DefaultResourceLoader discovers extensions. Restored
// immediately after — the parent's already-loaded extensions are unaffected.
async function withAgentChildEnv<T>(fn: () => Promise<T>): Promise<T> {
  const prev = process.env.PI_AGENT_TEAM_CHILD;
  process.env.PI_AGENT_TEAM_CHILD = "1";
  try {
    return await fn();
  } finally {
    if (prev === undefined) delete process.env.PI_AGENT_TEAM_CHILD;
    else process.env.PI_AGENT_TEAM_CHILD = prev;
  }
}

function sdkMessageText(message: any): string {
  const c = message?.content;
  if (typeof c === "string") return c;
  if (Array.isArray(c)) {
    return c.filter((p: any) => p?.type === "text").map((p: any) => p.text ?? "").join("");
  }
  return "";
}

async function createSdkAgent(opts: CreateSdkAgentOpts): Promise<SdkAgentHandle> {
  const authStorage = AuthStorage.create();
  const modelRegistry = ModelRegistry.create(authStorage);
  const model = await resolveModelSpec(modelRegistry, opts.model);
  const tools = parseToolsCsv(opts.tools);

  const { session } = await withAgentChildEnv(async () => {
    const resourceLoader = new DefaultResourceLoader({ cwd: opts.cwd, agentDir: getAgentDir() });
    await resourceLoader.reload();
    return await createAgentSession({
      cwd: opts.cwd,
      authStorage,
      modelRegistry,
      ...(model ? { model } : {}),
      ...(tools ? { tools } : {}),
      resourceLoader,
      sessionManager: SessionManager.inMemory(opts.cwd),
    } as any);
  });

  let status: SdkAgentStatus = "idle";
  let latestReport = "";
  let lastEventAt = Date.now();
  const emit = (e: Omit<SdkEvent, "tag">) => {
    lastEventAt = Date.now();
    opts.onEvent?.({ ...e, tag: opts.tag });
  };

  const unsubscribe = session.subscribe((event: any) => {
    if (event.type === "message_update") {
      const u = event.assistantMessageEvent;
      if (u?.type === "text_delta" && u.delta) emit({ type: "text", text: u.delta });
      else if (u?.type === "thinking_delta" && u.delta) emit({ type: "thinking", text: u.delta });
      return;
    }
    if (event.type === "tool_execution_start") {
      emit({ type: "tool-call", toolName: event.toolName, text: `→ ${event.toolName}` });
      return;
    }
    if (event.type === "tool_execution_end") {
      emit({ type: "tool-result", toolName: event.toolName, isError: event.isError, text: `${event.isError ? "✗" : "✓"} ${event.toolName}` });
      return;
    }
    if (event.type === "message_end" && event.message?.role === "assistant") {
      const t = sdkMessageText(event.message).trim();
      if (t) latestReport = t;
    }
  });

  return {
    tag: opts.tag,
    get status() { return status; },
    get latestReport() { return latestReport; },
    async prompt(prompt: string) {
      status = "running";
      lastEventAt = Date.now();
      emit({ type: "status", text: `started @${opts.tag}` });
      const healthMs = Math.max(1000, opts.healthTimeoutMs);
      const interval = Math.max(5000, Math.min(30000, Math.floor(healthMs / 6)));
      let healthTimedOut = false;
      const timer = setInterval(() => {
        if (Date.now() - lastEventAt >= healthMs) {
          healthTimedOut = true;
          emit({ type: "error", text: `health check failed: no event for ${Math.round(healthMs / 1000)}s`, isError: true });
          void session.abort();
        }
      }, interval);
      const full = opts.context
        ? `<role-context>\n${opts.context}\n</role-context>\n\n${prompt}`
        : prompt;
      try {
        await session.prompt(full);
        clearInterval(timer);
        if (healthTimedOut) {
          status = "error";
          return { ok: false, report: latestReport, error: "health timeout" };
        }
        status = "done";
        emit({ type: "status", text: `done @${opts.tag}` });
        return { ok: true, report: latestReport };
      } catch (err: any) {
        clearInterval(timer);
        status = "error";
        const error = healthTimedOut ? "health timeout" : (err?.message ?? String(err));
        emit({ type: "error", text: error, isError: true });
        return { ok: false, report: latestReport, error };
      }
    },
    async steer(text: string) {
      const payload = `[User steering @${opts.tag}]\n${text}`;
      if (session.isStreaming) await session.steer(payload);
      else await session.prompt(payload);
    },
    async abort() {
      try { await session.abort(); } catch {}
    },
    dispose() {
      try { unsubscribe(); } catch {}
      try { session.dispose(); } catch {}
    },
  };
}

// --- live modal state + helpers ---------------------------------------------

interface LiveLoopState {
  task: string;
  phase: string;
  input: string;
  inputCursor: number;
  completionHint: string;
  logs: string[];
  agents: Map<string, SdkAgentHandle>;
  knownTags: Set<string>;
  latestDispatcher: string;
  latestSupervisor: string;
  globalSteering: string[];
  awaitingUser: boolean;
  userReason: string;
  userResolver?: (v: string | null) => void;
  exitRequested: boolean;
  cancelCurrent?: () => void;
  requestRender?: () => void;
  abort?: () => void;
}

function trimLiveLogs(state: LiveLoopState): void {
  if (state.logs.length > 300) state.logs.splice(0, state.logs.length - 300);
  state.requestRender?.();
}

function appendLiveLog(state: LiveLoopState, line: string): void {
  state.logs.push(line);
  trimLiveLogs(state);
}

// Coalesce consecutive text/thinking deltas from the same tag onto one line.
function appendStreamingLog(state: LiveLoopState, tag: string, kind: "text" | "thinking", delta: string): void {
  const prefix = kind === "thinking" ? `@${tag} thinking: ` : `@${tag} `;
  const last = state.logs.length - 1;
  if (last >= 0 && state.logs[last].startsWith(prefix)) state.logs[last] += delta;
  else state.logs.push(prefix + delta);
  trimLiveLogs(state);
}

function styleAgentTags(text: string, theme: any): string {
  return text.replace(/(^|[^\w])(@[A-Za-z][A-Za-z0-9_-]*)\b/g, (_m, p: string, tag: string) =>
    `${p}${theme.fg("accent", theme.bold(tag))}`);
}

function renderWrapped(lines: string[], text: string, width: number): void {
  const normalized = text.replace(/\s+/g, " ").trim();
  if (!normalized) { lines.push(""); return; }
  for (const line of wrapTextWithAnsi(normalized, width)) lines.push(truncateToWidth(line, width));
}

function padAnsi(text: string, width: number): string {
  const pad = Math.max(0, width - visibleWidth(text));
  return text + " ".repeat(pad);
}

function getAgentTagCompletions(state: LiveLoopState): string[] {
  return [...new Set(["all", "loop", ...state.knownTags, ...state.agents.keys()])].sort();
}

function formatAgentTagHelp(state: LiveLoopState): string {
  if (state.awaitingUser) return "Type your response to continue, or /exit to stop the loop.";
  const examples = getAgentTagCompletions(state)
    .filter((t) => t !== "loop")
    .slice(0, 4)
    .map((t) => `@${t}`)
    .join("/");
  return `${examples || "@tag"} msg • Tab complete • Enter steer • /exit stop • Esc abort`;
}

function steeringBlock(state: LiveLoopState): string {
  if (state.globalSteering.length === 0) return "";
  return `\n\n## Live user steering\n${state.globalSteering.map((l) => `- ${l}`).join("\n")}`;
}

function waitForUserPrompt(state: LiveLoopState, reason: string): Promise<string | null> {
  if (state.exitRequested) return Promise.resolve(null);
  appendLiveLog(state, `@loop waiting for user input: ${reason}`);
  state.awaitingUser = true;
  state.userReason = reason;
  state.requestRender?.();
  return new Promise((resolve) => { state.userResolver = resolve; });
}

async function routeLiveSteer(state: LiveLoopState, raw: string): Promise<void> {
  const trimmed = raw.trim();
  if (!trimmed) return;
  if (trimmed === "/exit") {
    state.exitRequested = true;
    appendLiveLog(state, "@loop exit requested by user");
    const r = state.userResolver;
    state.userResolver = undefined;
    state.awaitingUser = false;
    state.userReason = "";
    r?.(null);
    state.cancelCurrent?.();
    for (const a of state.agents.values()) void a.abort();
    return;
  }
  if (state.awaitingUser) {
    appendLiveLog(state, `@loop user response: ${trimmed}`);
    const r = state.userResolver;
    state.userResolver = undefined;
    state.awaitingUser = false;
    state.userReason = "";
    r?.(trimmed);
    state.requestRender?.();
    return;
  }
  const m = trimmed.match(/^@(\S+)\s+([\s\S]+)$/);
  if (!m) {
    state.globalSteering.push(trimmed);
    appendLiveLog(state, `@loop queued steering for next prompts: ${trimmed}`);
    return;
  }
  const target = m[1];
  const text = m[2];
  const targets = target === "all" || target === "loop"
    ? [...state.agents.values()]
    : ([state.agents.get(target)].filter(Boolean) as SdkAgentHandle[]);
  if (targets.length === 0) {
    state.globalSteering.push(trimmed);
    appendLiveLog(state, `@loop queued steering for inactive @${target}: ${text}`);
    return;
  }
  for (const a of targets) {
    appendLiveLog(state, `@loop → @${a.tag}: ${text}`);
    void a.steer(text).catch((e) => appendLiveLog(state, `@${a.tag} steer failed: ${String(e)}`));
  }
}

function completeAgentTag(state: LiveLoopState): void {
  const before = state.input.slice(0, state.inputCursor);
  const m = before.match(/(^|\s)@(\S*)$/);
  if (!m) {
    state.completionHint = "Type @ then a tag, then Tab (e.g. @exe → @executor).";
    return;
  }
  const prefix = m[2] ?? "";
  const candidates = getAgentTagCompletions(state).filter((t) => t.startsWith(prefix));
  if (candidates.length === 0) { state.completionHint = `No @tag for @${prefix}`; return; }
  if (candidates.length > 1) {
    state.completionHint = `@${prefix} → ${candidates.map((t) => `@${t}`).join(", ")}`;
    return;
  }
  const start = before.length - prefix.length;
  const replacement = candidates[0];
  const suffix = state.input.slice(state.inputCursor);
  state.input = state.input.slice(0, start) + replacement + (suffix.startsWith(" ") ? "" : " ") + suffix;
  state.inputCursor = start + replacement.length + 1;
  state.completionHint = `Completed @${replacement}`;
}

// Insert (possibly pasted) text at the cursor, stripping control chars and
// bracketed-paste markers. Ported from Ivan's live-input.ts.
function insertLiveInput(state: LiveLoopState, data: string): void {
  const text = data
    .replace(/\x1b\[200~|\x1b\[201~/g, "")
    .replace(/\r\n|\r|\n/g, " ")
    .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "");
  if (!text) return;
  state.input = state.input.slice(0, state.inputCursor) + text + state.input.slice(state.inputCursor);
  state.inputCursor += text.length;
  state.completionHint = "";
  state.requestRender?.();
}

function renderInputBox(state: LiveLoopState, theme: any, width: number): string[] {
  const totalWidth = Math.max(24, width);
  const innerWidth = Math.max(22, totalWidth - 2);
  const textWidth = Math.max(1, innerWidth - 2);
  const cursor = Math.max(0, Math.min(state.inputCursor, state.input.length));
  let start = 0;
  if (cursor > textWidth - 1) start = cursor - textWidth + 1;
  let display = state.input.slice(start, start + textWidth);
  if (start > 0 && display.length > 0) display = "…" + display.slice(1);
  const cursorInDisplay = Math.max(0, Math.min(display.length, cursor - start));
  const raw = `> ${display}`;
  const cursorIndex = 2 + cursorInDisplay;
  const before = raw.slice(0, cursorIndex);
  const cursorChar = cursorIndex < raw.length ? raw[cursorIndex] : " ";
  const after = cursorIndex < raw.length ? raw.slice(cursorIndex + 1) : "";
  const content = `${before}${CURSOR_MARKER}\x1b[7m${cursorChar}\x1b[27m${after}`;
  const border = (s: string) => theme.fg("accent", s);
  return [
    border(`╭${"─".repeat(innerWidth)}╮`),
    border("│") + padAnsi(content, innerWidth) + border("│"),
    border(`╰${"─".repeat(innerWidth)}╯`),
  ];
}

function buildLiveLoopComponent(state: LiveLoopState, theme: any): any {
  const component: any = {
    focused: true,
    render(width: number): string[] {
      const lines: string[] = [];
      const w = Math.max(20, width - 2);
      lines.push(theme.fg("toolTitle", theme.bold("supervise-loop")) + theme.fg("muted", ` — ${state.phase}`));
      renderWrapped(lines, theme.fg("dim", state.task), w);
      if (state.awaitingUser) {
        lines.push("");
        renderWrapped(lines, theme.fg("warning", styleAgentTags(`@loop needs input: ${state.userReason}`, theme)), w);
      }
      lines.push("");
      const agentRows = [...state.agents.values()].map((a) => {
        const icon = a.status === "running" ? "…" : a.status === "done" ? "✓" : a.status === "error" ? "✗" : "·";
        return `${icon} ${styleAgentTags(`@${a.tag}`, theme)}`;
      });
      renderWrapped(lines, `agents: ${agentRows.join("  ") || "(starting…)"}`, w);
      lines.push("");
      lines.push(theme.fg("accent", "latest dispatcher"));
      for (const l of (state.latestDispatcher || "(none yet)").split(/\r?\n/).slice(0, 6)) {
        renderWrapped(lines, theme.fg("dim", styleAgentTags(l, theme)), w);
      }
      lines.push("");
      lines.push(theme.fg("accent", "latest supervisor"));
      for (const l of (state.latestSupervisor || "(none yet)").split(/\r?\n/).slice(0, 6)) {
        renderWrapped(lines, theme.fg("dim", styleAgentTags(l, theme)), w);
      }
      lines.push("");
      lines.push(theme.fg("accent", "live log"));
      for (const l of state.logs.slice(-8)) renderWrapped(lines, styleAgentTags(l, theme), w);
      lines.push("");
      renderWrapped(lines, theme.fg("muted", styleAgentTags(formatAgentTagHelp(state), theme)), w);
      if (state.completionHint) renderWrapped(lines, theme.fg("dim", styleAgentTags(state.completionHint, theme)), w);
      lines.push(...renderInputBox(state, theme, width));
      return lines;
    },
    invalidate(): void {},
    handleInput(data: string): void {
      if (matchesKey(data, Key.escape)) { state.abort?.(); return; }
      if (matchesKey(data, Key.enter)) {
        const text = state.input;
        state.input = "";
        state.inputCursor = 0;
        state.completionHint = "";
        void routeLiveSteer(state, text);
        state.requestRender?.();
        return;
      }
      if (matchesKey(data, Key.tab)) { completeAgentTag(state); state.requestRender?.(); return; }
      if (matchesKey(data, Key.left)) { state.inputCursor = Math.max(0, state.inputCursor - 1); state.requestRender?.(); return; }
      if (matchesKey(data, Key.right)) { state.inputCursor = Math.min(state.input.length, state.inputCursor + 1); state.requestRender?.(); return; }
      if (matchesKey(data, Key.home)) { state.inputCursor = 0; state.requestRender?.(); return; }
      if (matchesKey(data, Key.end)) { state.inputCursor = state.input.length; state.requestRender?.(); return; }
      if (matchesKey(data, Key.delete)) {
        if (state.inputCursor < state.input.length) {
          state.input = state.input.slice(0, state.inputCursor) + state.input.slice(state.inputCursor + 1);
        }
        state.requestRender?.();
        return;
      }
      if (matchesKey(data, Key.backspace)) {
        if (state.inputCursor > 0) {
          state.input = state.input.slice(0, state.inputCursor - 1) + state.input.slice(state.inputCursor);
          state.inputCursor--;
        }
        state.requestRender?.();
        return;
      }
      insertLiveInput(state, data);
    },
  };
  return component;
}

async function runLiveModal(ctx: any, state: LiveLoopState, work: () => Promise<void>): Promise<void> {
  let error: unknown;
  await ctx.ui.custom<void>((tui: any, theme: any, _kb: any, done: () => void) => {
    state.requestRender = () => tui.requestRender();
    state.abort = () => {
      state.exitRequested = true;
      appendLiveLog(state, "@loop abort requested");
      const r = state.userResolver;
      state.userResolver = undefined;
      state.awaitingUser = false;
      state.userReason = "";
      r?.(null);
      state.cancelCurrent?.();
      for (const a of state.agents.values()) void a.abort();
    };
    setImmediate(() => {
      work()
        .catch((err: any) => { error = err; appendLiveLog(state, `@loop error: ${err?.message ?? String(err)}`); })
        .finally(() => done());
    });
    return buildLiveLoopComponent(state, theme);
  });
  if (error) throw error;
}

interface SdkRoleMember { tag: string; model?: string; tools?: string; }

// Spawn one role's agents (1 for dispatcher/executor, N for supervisor panel),
// stream their events into the modal, prompt them all, return their reports.
async function runSdkRole(args: {
  state: LiveLoopState;
  role: string;
  members: SdkRoleMember[];
  context: string;
  prompt: string;
  cwd: string;
  healthTimeoutMs: number;
}): Promise<{ tag: string; ok: boolean; report: string; error?: string }[]> {
  const { state } = args;
  state.phase = args.role;
  state.agents.clear();
  state.requestRender?.();
  const handles: SdkAgentHandle[] = [];
  const prevCancel = state.cancelCurrent;
  state.cancelCurrent = () => { prevCancel?.(); for (const h of handles) void h.abort(); };
  try {
    for (const m of args.members) {
      let handle: SdkAgentHandle;
      handle = await createSdkAgent({
        tag: m.tag,
        model: m.model,
        tools: m.tools,
        context: args.context,
        cwd: args.cwd,
        healthTimeoutMs: args.healthTimeoutMs,
        onEvent: (e) => {
          if (e.type === "text" || e.type === "thinking") appendStreamingLog(state, e.tag, e.type, e.text);
          else appendLiveLog(state, `@${e.tag} ${e.text}`);
          if (e.type === "text") {
            if (args.role.includes("dispatcher")) state.latestDispatcher = handle.latestReport || state.latestDispatcher;
            if (args.role.includes("supervisor")) state.latestSupervisor = handle.latestReport || state.latestSupervisor;
          }
        },
      });
      handles.push(handle);
      state.agents.set(handle.tag, handle);
    }
    state.requestRender?.();
    const steer = steeringBlock(state);
    const results = await Promise.all(
      handles.map((h) => h.prompt(`${args.prompt}${steer}`).then((r) => ({ tag: h.tag, ...r }))),
    );
    for (const h of handles) {
      if (args.role.includes("dispatcher")) state.latestDispatcher = h.latestReport;
      if (args.role.includes("supervisor")) state.latestSupervisor = h.latestReport;
    }
    return results;
  } finally {
    state.cancelCurrent = prevCancel;
    for (const h of handles) h.dispose();
    state.requestRender?.();
  }
}

// --- main entrypoint --------------------------------------------------------

async function runSuperviseLoop(task: string, ctx: any): Promise<{ summary: string; details: any } | null> {
  const ss = loadSettings(ctx.cwd).supervise;
  const maxIterations = ss.maxIterations ?? DEFAULT_MAX_ITERATIONS;
  const oracleRequired = ss.oracleRequired ?? true;
  const healthTimeoutMs = (ss.healthTimeoutSeconds ?? DEFAULT_HEALTH_TIMEOUT_SECONDS) * 1000;
  const dispatcherModel = ss.dispatcherModel;
  const executorModel = ss.executorModel;
  const supervisorPanel: SupervisorMemberConfig[] =
    ss.supervisorMembers && ss.supervisorMembers.length > 0
      ? ss.supervisorMembers
      : [{ label: "supervisor", model: ss.supervisorModel }];
  const supMembers: SdkRoleMember[] = supervisorPanel.map((m, i) => ({
    tag: m.label ?? `supervisor-${i + 1}`,
    model: m.model,
    tools: m.tools,
  }));

  const runDir = makeRunDir(ctx.cwd, task);
  mkdirSync(join(runDir, "oracle", "state"), { recursive: true });
  mkdirSync(join(runDir, "oracle", "runs"), { recursive: true });
  mkdirSync(join(runDir, "evidence"), { recursive: true });

  const state: LiveLoopState = {
    task,
    phase: "starting",
    input: "",
    inputCursor: 0,
    completionHint: "",
    logs: [],
    agents: new Map(),
    knownTags: new Set(["dispatcher", "executor", "oracle", ...supMembers.map((m) => m.tag)]),
    latestDispatcher: "",
    latestSupervisor: "",
    globalSteering: [],
    awaitingUser: false,
    userReason: "",
    exitRequested: false,
  };

  // Phase A — initial dispatcher plan (in the modal).
  let dispatcherOutput = "";
  await runLiveModal(ctx, state, async () => {
    appendLiveLog(state, `@loop planning: ${task}`);
    const res = await runSdkRole({
      state, role: "dispatcher initial",
      members: [{ tag: "dispatcher", model: dispatcherModel }],
      context: DISPATCHER_CONTEXT, prompt: buildDispatcherPrompt(task, null),
      cwd: ctx.cwd, healthTimeoutMs,
    });
    dispatcherOutput = res[0]?.report ?? "";
    writeFileSync(join(runDir, "dispatcher-initial.md"), dispatcherOutput);
  });
  if (state.exitRequested) {
    ctx.ui.notify(`supervise-loop stopped before approval. Artifacts: ${runDir}`, "warning");
    return null;
  }

  // Phase B — user approval (editor, outside the modal). Feedback re-runs the
  // dispatcher in a fresh modal pass.
  const approval = await promptForApprovedPlan(task, dispatcherOutput, ctx, oracleRequired, async (feedback) => {
    let revised = dispatcherOutput;
    await runLiveModal(ctx, state, async () => {
      const res = await runSdkRole({
        state, role: "dispatcher feedback",
        members: [{ tag: "dispatcher", model: dispatcherModel }],
        context: DISPATCHER_CONTEXT,
        prompt: buildDispatcherFeedbackPrompt(task, dispatcherOutput, feedback),
        cwd: ctx.cwd, healthTimeoutMs,
      });
      revised = res[0]?.report ?? dispatcherOutput;
      writeFileSync(join(runDir, `dispatcher-feedback-${Date.now()}.md`), revised);
    });
    dispatcherOutput = revised;
    return revised;
  });
  if (!approval) {
    ctx.ui.notify("supervise-loop canceled before execution.", "info");
    return null;
  }
  const approvedPlan = approval.approvedPackage;
  const approvedOracleCode = approval.oracleCode;
  writeFileSync(join(runDir, "user-approved-plan.md"), approvedPlan);

  // Freeze oracle.
  const frozenOracleFile = join(runDir, "oracle", "oracle.sh");
  writeFileSync(frozenOracleFile, approvedOracleCode || "", { mode: 0o400 });
  try { chmodSync(frozenOracleFile, 0o400); } catch {}

  // Baseline evidence.
  const baseline = collectVcsEvidence(ctx.cwd);
  writeFileSync(join(runDir, "evidence", "attempt-0-status.txt"), baseline.status);
  writeFileSync(join(runDir, "evidence", "attempt-0-diff.patch"), baseline.diff);

  // Phase C — the loop (in the modal).
  let finalDecision = "REPAIR";
  let lastSupervisorReport = "";
  let finalIteration = 0;
  let oracleResult: { exitCode: number; output: string; assertions: number } | null = null;
  let loopContext = "";

  await runLiveModal(ctx, state, async () => {
    for (let iteration = 1; iteration <= maxIterations; iteration++) {
      if (state.exitRequested) break;
      finalIteration = iteration;

      if (iteration > 1) {
        const res = await runSdkRole({
          state, role: `dispatcher iteration ${iteration}`,
          members: [{ tag: "dispatcher", model: dispatcherModel }],
          context: DISPATCHER_CONTEXT, prompt: buildDispatcherPrompt(task, loopContext),
          cwd: ctx.cwd, healthTimeoutMs,
        });
        if (state.exitRequested) break;
        dispatcherOutput = res[0]?.report ?? dispatcherOutput;
        writeFileSync(join(runDir, `dispatcher-iteration-${iteration}.md`), dispatcherOutput);
      }

      const execRes = await runSdkRole({
        state, role: `execution iteration ${iteration}`,
        members: [{ tag: "executor", model: executorModel }],
        context: EXECUTOR_CONTEXT,
        prompt: buildExecutorPrompt(approvedPlan, iteration, maxIterations, loopContext),
        cwd: ctx.cwd, healthTimeoutMs,
      });
      if (state.exitRequested) break;
      const executionReport = execRes[0]?.report ?? "";
      writeFileSync(join(runDir, `execution-iteration-${iteration}.md`), executionReport);

      state.phase = `oracle iteration ${iteration}`;
      state.requestRender?.();
      if (approvedOracleCode) appendLiveLog(state, `@oracle running iteration ${iteration}`);
      oracleResult = approvedOracleCode
        ? runOracle({ frozenOracleFile, runDir, iteration, requireAssertion: oracleRequired })
        : null;
      if (oracleResult) {
        writeFileSync(
          join(runDir, "oracle", "runs", `oracle-iteration-${iteration}.txt`),
          `exit=${oracleResult.exitCode} assertions=${oracleResult.assertions}\n${oracleResult.output}`,
        );
        appendLiveLog(state, `@oracle exit ${oracleResult.exitCode}${oracleResult.exitCode === 0 ? "" : " (fail)"}`);
      }
      if (state.exitRequested) break;

      const current = collectVcsEvidence(ctx.cwd);
      writeFileSync(join(runDir, "evidence", `attempt-${iteration}-status.txt`), current.status);
      writeFileSync(join(runDir, "evidence", `attempt-${iteration}-diff.patch`), current.diff);

      const supRes = await runSdkRole({
        state, role: `supervisor iteration ${iteration}`,
        members: supMembers,
        context: SUPERVISOR_CONTEXT,
        prompt: buildSupervisorPrompt({ approvedPlan, executionReport, oracleResult, baseline, current }),
        cwd: ctx.cwd, healthTimeoutMs,
      });
      if (state.exitRequested) break;

      const memberVerdicts: PanelMemberResult[] = supRes.map((r) => ({
        label: r.tag, report: r.report, verdict: parseSupervisorVerdict(r.report),
      }));
      const verdict = memberVerdicts.length === 1 ? memberVerdicts[0].verdict : aggregatePanelVerdict(memberVerdicts);
      const combinedReport = memberVerdicts.length === 1
        ? memberVerdicts[0].report
        : memberVerdicts.map((m) => `## ${m.label} → ${m.verdict.effectiveDecision}\n\n${m.report}`).join("\n\n---\n\n");
      lastSupervisorReport = combinedReport;
      state.latestSupervisor = combinedReport;

      let decision = verdict.effectiveDecision;
      const downgrades = [...verdict.downgrades];
      const oracleFailed = oracleRequired && oracleResult && (oracleResult as any).exitCode !== 0;
      if (oracleFailed && decision === "COMPLETE") {
        decision = "REPAIR";
        downgrades.push("oracle_failed_overrides_complete");
      }
      writeFileSync(
        join(runDir, `supervisor-iteration-${iteration}.md`),
        `${combinedReport}\n\n---\n\nverdict: decision=${decision} dod=${verdict.finalDodMet} iter=${verdict.iterationAccepted} downgrades=[${downgrades.join(", ")}] panel_size=${memberVerdicts.length}`,
      );
      finalDecision = decision;
      appendLiveLog(state, `@loop iteration ${iteration}: ${decision}`);

      if (decision === "COMPLETE") break;
      if (decision === "ASK_USER" || decision === "BLOCKED") {
        const answer = await waitForUserPrompt(state, `${decision}: answer to continue, or /exit to stop`);
        if (!answer) break;
        writeFileSync(join(runDir, `user-response-iteration-${iteration}.md`), answer);
        loopContext = `## Previous supervisor verdict (${decision})\n${combinedReport}\n\n## User response\n${answer}`;
        finalDecision = "REPAIR";
        continue;
      }
      loopContext = `## Previous supervisor verdict\n${combinedReport}\n\n## Repair instructions\nSee the supervisor report above.`;
    }

    if (state.exitRequested) {
      finalDecision = "STOPPED";
    } else if (finalDecision === "REPAIR" && finalIteration >= maxIterations) {
      finalDecision = "ASK_USER";
      lastSupervisorReport = `Max iterations (${maxIterations}) exhausted.\n\nLast supervisor report:\n${lastSupervisorReport}`;
      appendLiveLog(state, `@loop max iterations (${maxIterations}) exhausted`);
    }
    state.phase = `done: ${finalDecision}`;
    state.requestRender?.();
  });

  const summary = buildSupervisorSummary({
    runDir, task, finalDecision, finalIteration, maxIterations, lastSupervisorReport, oracleResult,
  });
  writeFileSync(join(runDir, "summary.md"), summary);
  ctx.ui.notify(
    `supervise-loop: ${finalDecision} after ${finalIteration} iteration(s). Artifacts: ${runDir}`,
    finalDecision === "COMPLETE" ? "info" : "warning",
  );
  return {
    summary,
    details: { runDir, finalDecision, iterations: finalIteration, maxIterations },
  };
}

// ===========================================================================
// SIDE-KICK — a long-lived in-process agent the main agent talks to repeatedly
// Reuses the createSdkAgent runner, but keeps the handle alive in a registry
// across tool calls instead of disposing it after one prompt. Each sidekick_send
// calls prompt() on the SAME session, so the side-kick accumulates its own
// conversation history and remembers prior exchanges — the "dynamic duo".
// ===========================================================================

interface SidekickEntry {
  name: string;
  handle: SdkAgentHandle;
  role: string;
  model?: string;
  tools?: string;
  cwd: string;
  createdAt: number;
  sends: number;
  firstSendDone: boolean;
  streamBuf: string;
  onPreview?: (text: string) => void;
}

// Module-level: persists across tool calls for the life of the pi session.
// Only the parent factory registers the tools that touch it (the factory
// early-returns in child sessions), so children never populate this.
const sidekicks = new Map<string, SidekickEntry>();

async function startSidekick(opts: {
  name: string;
  role: string;
  model?: string;
  tools?: string;
  cwd: string;
  healthTimeoutMs: number;
}): Promise<SidekickEntry> {
  const entry: SidekickEntry = {
    name: opts.name,
    handle: null as any,
    role: opts.role,
    model: opts.model,
    tools: opts.tools,
    cwd: opts.cwd,
    createdAt: Date.now(),
    sends: 0,
    firstSendDone: false,
    streamBuf: "",
  };
  // context: "" — the role is injected into the first send instead of being
  // re-prepended to every prompt (createSdkAgent would otherwise repeat it).
  entry.handle = await createSdkAgent({
    tag: opts.name,
    model: opts.model,
    tools: opts.tools,
    context: "",
    cwd: opts.cwd,
    healthTimeoutMs: opts.healthTimeoutMs,
    onEvent: (e) => {
      if (e.type === "text") {
        entry.streamBuf += e.text;
        entry.onPreview?.(entry.streamBuf);
      }
    },
  });
  sidekicks.set(opts.name, entry);
  return entry;
}

function disposeSidekick(name: string): boolean {
  const entry = sidekicks.get(name);
  if (!entry) return false;
  try { entry.handle.dispose(); } catch {}
  sidekicks.delete(name);
  return true;
}

function sidekickSummaryLine(e: SidekickEntry): string {
  const age = Math.round((Date.now() - e.createdAt) / 1000);
  return `${e.name} [${e.handle.status}] model=${e.model ?? "(default)"} sends=${e.sends} age=${age}s`;
}
