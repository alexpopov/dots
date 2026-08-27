// sidekick — a long-lived, conversational in-process agent (sidekick_start /
// sidekick_send / sidekick_stop + /sidekick). Carved out of the old bespoke
// subagent bundle: `subagent` and `/council` now come from the pi-subagents
// package; supervise was dropped (unused). Slimmed down to side-kick +
// shared createSdkAgent paths only (dead council/supervise/runOnePi bulk
// removed); only registrations here are sidekick_start/send/stop + /sidekick.
import {
  createAgentSession,
  DefaultResourceLoader,
  getAgentDir,
  ModelRuntime,
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
// After the child exits, how long to let its stdio pipes drain before settling.
// Only matters when a grandchild holds the pipes open (then "close" never fires).
const STDIO_DRAIN_MS = 250;
// Background dispatch: cap concurrent children, and how much prompt to keep as
// a human label. Completion reports come back as this custom message type.
const MAX_BG_RUNS = Number(process.env.PI_SUBAGENT_MAX_RUNNING) || 8;
const BG_LABEL_CHARS = 70;
const BG_MSG_TYPE = "subagent-done";
const COUNCIL_MSG_TYPE = "council-done";
const SIDEKICK_MSG_TYPE = "sidekick-reply";
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
// Wall-clock cap on a single sidekick_send. Unlike the silence-based health
// timeout (which a constantly-thinking side-kick never trips), this fires in
// real time and hands a "justify yourself" checkpoint back to the primary
// agent (partial progress; the side-kick stays alive). 0 disables (block).
const DEFAULT_SIDEKICK_TIMEOUT_SECONDS = Number(process.env.PI_SIDEKICK_TIMEOUT) || 180;
const DEFAULT_SIDEKICK_NAME = "sidekick";
const DEFAULT_SIDEKICK_ROLE =
  "You are a side-kick agent working alongside a primary agent in the same " +
  "project. The primary agent delegates focused work to you and will talk to " +
  "you repeatedly, so remember what you've done across messages. Be concise, " +
  "do the work concretely (use your tools), and end each reply with the " +
  "result the primary agent needs — not a restatement of the request.";

// Steered into a running side-kick when its wall-clock timeout fires: ask what
// it's doing and have it PAUSE (not abort), so the primary decides continue-vs-
// stop without discarding the turn's context.
const SIDEKICK_CHECKPOINT_MSG =
  "⏸ CHECKPOINT from the primary agent. Pause what you're doing right now. In " +
  "2-4 short lines tell me: (1) what you're working on this moment, (2) what " +
  "you've found so far, (3) what's left and how much longer. Then STOP and wait " +
  "— do NOT continue until I explicitly say so. Keep all your context; I may " +
  "well tell you to continue.";

// Race a promise against a wall-clock timeout WITHOUT disturbing it: on timeout
// the promise keeps running (we re-race the same promise later), so nothing is
// killed by the race itself.
async function raceWithTimeout<T>(p: Promise<T>, ms: number): Promise<{ timedOut: boolean; value?: T }> {
  let to: ReturnType<typeof setTimeout> | undefined;
  const timer = new Promise<{ timedOut: true }>((resolve) => {
    to = setTimeout(() => resolve({ timedOut: true }), ms);
  });
  const done = p.then((value) => ({ timedOut: false as const, value }));
  const r = await Promise.race([done, timer]);
  if (to) clearTimeout(to);
  return r as { timedOut: boolean; value?: T };
}

// --- settings loading -------------------------------------------------------
// Read ~/.pi/agent/settings.json (global) and ./.pi/settings.json (project).
// Project keys override global keys, per-block (matches Ivan's pattern in
// his supervise-loop). Defaults are
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
  // Per-send WALL-CLOCK timeout (real seconds) before the send is interrupted
  // and a checkpoint handed back to the primary. 0 disables.
  timeoutSeconds?: number;
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
  // Recursion guard: children load this file too. Return before registering in
  // OUR own side-kick children (PI_AGENT_TEAM_CHILD) AND in pi-subagents' children
  // (PI_SUBAGENT_CHILD), so side-kicks never nest and never load inside a subagent.
  if (process.env.PI_AGENT_TEAM_CHILD === "1" || process.env.PI_SUBAGENT_CHILD === "1") return;

  // No background subagent machinery here anymore (that moved to the
  // pi-subagents package). liveRuns stays as a stub so the widget below keeps
  // working unchanged; only side-kicks populate it via liveSidekicks.
  const liveRuns = (): never[] => [];

  // ---- live background-agents widget --------------------------------------
  // Passive, glanceable "what's running" view for busy side-kicks.
  // Poll-driven while anything runs; clears when idle.
  let agentsCtx: any = null;
  let agentsPoll: ReturnType<typeof setInterval> | null = null;
  const liveSidekicks = () => [...sidekicks.values()].filter((e) => e.handle?.status === "running");
  const stopAgentsPoll = () => { if (agentsPoll) { clearInterval(agentsPoll); agentsPoll = null; } };
  const renderAgentsWidget = () => {
    const c = agentsCtx;
    // c.ui access throws on stale ctx after reload (assertActive) — and this
    // runs on a timer, so disarm instead of letting it exit pi.
    let cui: any;
    try {
      cui = c?.ui;
    } catch {
      if (c === agentsCtx) agentsCtx = null;
      stopAgentsPoll();
      return;
    }
    if (!cui?.setWidget) return;
    const runs = liveRuns();
    const sks = liveSidekicks();
    if (runs.length === 0 && sks.length === 0) {
      try { cui.setWidget("live-agents", undefined); } catch {}
      return;
    }
    const now = Date.now();
    try {
      cui.setWidget("live-agents", (_tui: any, theme: any) => ({
        render: () => {
          const head: string[] = [];
          if (runs.length) head.push(`${runs.length} subagent${runs.length > 1 ? "s" : ""}`);
          if (sks.length) head.push(`${sks.length} side-kick${sks.length > 1 ? "s" : ""}`);
          const lines = [`${theme.bold(head.join(", "))} ${theme.fg("dim", "running -- /sidekick to manage")}`];
          for (const r of runs) {
            const secs = Math.round((now - r.startedAt) / 1000);
            lines.push(`  ${theme.fg("accent", ">")} ${r.id} ${theme.fg("dim", `(${secs}s)`)} ${r.label.slice(0, 60)}`);
            const tail = r.preview ? (r.preview.split("\n").pop() || "").slice(0, 80) : "";
            if (tail) lines.push(`      ${theme.fg("dim", tail)}`);
          }
          for (const e of sks) {
            lines.push(`  ${theme.fg("accent", ">")} side-kick ${e.name}${e.model ? theme.fg("dim", ` ${e.model}`) : ""}`);
            const tail = e.streamBuf ? (e.streamBuf.split("\n").pop() || "").slice(0, 80) : "";
            if (tail) lines.push(`      ${theme.fg("dim", tail)}`);
          }
          return lines;
        },
        invalidate: () => {},
      }));
    } catch { /* ui gone */ }
  };
  const startAgentsPoll = () => {
    if (agentsPoll) return;
    agentsPoll = setInterval(() => {
      renderAgentsWidget();
      if (liveRuns().length === 0 && liveSidekicks().length === 0) stopAgentsPoll();
    }, 1500);
    agentsPoll.unref?.();
  };
  const kickAgentsWidget = (ctx?: any) => { if (ctx) agentsCtx = ctx; renderAgentsWidget(); startAgentsPoll(); };

  pi.on("session_start", (_e: any, ctx: any) => { agentsCtx = ctx; });
  pi.on("session_shutdown", () => { stopAgentsPoll(); try { agentsCtx?.ui?.setWidget?.("live-agents", undefined); } catch {} });


  // Deliver an async side-kick reply between turns (followUp + triggerTurn), the
  // same wake-the-primary path subagent/council use. Lets sidekick_send return
  // immediately instead of holding the turn open while awaiting the reply.
  const deliverSidekick = (name: string, ok: boolean, body: string) => {
    try {
      pi.sendMessage(
        {
          customType: SIDEKICK_MSG_TYPE,
          content: `[side-kick ${name}] ${ok ? "replied" : "error"}:\n\n${body}`,
          display: true,
          details: { name, ok },
        },
        { deliverAs: "followUp", triggerTurn: true },
      );
    } catch { /* session gone */ }
  };

  pi.registerMessageRenderer(SIDEKICK_MSG_TYPE, (message: any, _options: any, theme: any) => {
    const d = message.details as { name?: string; ok?: boolean } | undefined;
    const head = d?.ok ? theme.fg("dim", `✓ side-kick ${d?.name ?? ""}`) : theme.fg("error", `✗ side-kick ${d?.name ?? ""}`);
    return new Text(head, 0, 0);
  });

  pi.on("session_shutdown", async () => {
    for (const run of liveRuns()) run.control.abort();
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
          modelRegistry: (ctx as any).modelRegistry,
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
      "Send a message to a side-kick. By DEFAULT this dispatches in the background " +
      "and returns immediately -- the reply arrives as a follow-up that wakes you " +
      "when ready, so you keep the floor (end your turn after sending, like a " +
      "backgrounded shell command). Pass wait:true to block for the reply in this " +
      "turn instead. The side-kick remembers your earlier messages to it (it has " +
      "its own running history). Only the default 'sidekick' is auto-created on " +
      "first use (handy for a quick companion); any other name must be created " +
      "with sidekick_start first, and a side-kick that was explicitly stopped is " +
      "not silently revived (the next send fails once, then a follow-up send " +
      "starts a fresh one). Use sidekick_start when you want a specific role / " +
      "model / tools.",
    parameters: Type.Object({
      message: Type.String({ description: "What to say to the side-kick." }),
      name: Type.Optional(Type.String({ description: "Side-kick name. Default 'sidekick'." })),
      model: Type.Optional(Type.String({ description: "Only used if the side-kick must be auto-created; ignored if it already exists." })),
      tools: Type.Optional(Type.String({ description: "Only used if the side-kick must be auto-created." })),
      wait: Type.Optional(Type.Boolean({ description: "Block for the reply in THIS turn. Default false = dispatch in the background and receive the reply as a follow-up when ready (you keep the floor; end your turn after sending). Use wait:true only for a tight synchronous loop where yielding the floor buys nothing." })),
      timeoutSeconds: Type.Optional(Type.Integer({ minimum: 0, description: "Only applies to wait:true. Wall-clock seconds before the blocking send is interrupted and its partial progress is handed back as a 'justify yourself' checkpoint (the side-kick stays alive so you can send 'continue' or sidekick_stop). Default 180 (env PI_SIDEKICK_TIMEOUT / settings.sidekick.timeoutSeconds); 0 = block until done. Ignored in the default async mode -- the side-kick's health timeout guards hangs there." })),
    }),
    async execute(_id, params, signal, onUpdate, ctx) {
      const name = (params.name ?? DEFAULT_SIDEKICK_NAME).trim() || DEFAULT_SIDEKICK_NAME;
      let entry = sidekicks.get(name);
      let autoCreated = false;
      if (!entry) {
        const isDefault = name === DEFAULT_SIDEKICK_NAME;
        // Named side-kicks are never auto-created: a non-default name signals
        // you mean a specific, already-configured side-kick, so a typo or a
        // stale reference should fail loudly rather than silently spawn a
        // different (default-configured) agent under that name.
        if (!isDefault) {
          const active = [...sidekicks.keys()];
          return { content: [{ type: "text", text: `No side-kick named '${name}'. Named side-kicks must be created with sidekick_start first (only the default '${DEFAULT_SIDEKICK_NAME}' is auto-created).${active.length ? ` Active: ${active.join(", ")}.` : ""}` }], isError: true };
        }
        // The default side-kick was explicitly stopped: don't silently
        // resurrect it as a fresh, memory-less agent. Fail once (clearing the
        // tombstone) so a deliberate follow-up send starts a clean one.
        if (stoppedSidekicks.has(name)) {
          stoppedSidekicks.delete(name);
          return { content: [{ type: "text", text: `Side-kick '${name}' was stopped — its conversation is gone. Send again to start a fresh one (no prior history), or use sidekick_start to set model/role/tools.` }], isError: true };
        }
        const s = loadSettings(ctx.cwd).sidekick;
        try {
          entry = await startSidekick({
            name,
            role: DEFAULT_SIDEKICK_ROLE,
            model: params.model ?? s.model,
            tools: params.tools ?? s.tools,
            cwd: ctx.cwd,
            healthTimeoutMs: (s.healthTimeoutSeconds ?? DEFAULT_SIDEKICK_HEALTH_SECONDS) * 1000,
            modelRegistry: (ctx as any).modelRegistry,
          });
          autoCreated = true;
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
      entry.thinkTail = "";

      // Default: async dispatch (like a backgrounded shell). Fire the message and
      // return immediately so the primary ends its turn and the human keeps the
      // floor; the reply is delivered as a followUp that wakes the primary. The
      // side-kick's own silence-based health timeout guards a wedged send, and
      // only one send runs at a time (a send while busy is rejected above).
      if (!(params.wait ?? false)) {
        entry.onPreview = undefined;
        const sk = entry;
        void sk.handle.prompt(text)
          .then((res) => {
            sk.firstSendDone = true;
            sk.sends++;
            const body = res.report?.trim() || (res.error ? `(error: ${res.error})` : "(side-kick returned no text)");
            deliverSidekick(name, !!res.ok, body);
          })
          .catch((err: any) => deliverSidekick(name, false, `side-kick send failed: ${err?.message ?? err}`))
          .finally(() => renderAgentsWidget());
        kickAgentsWidget();
        const banner = autoCreated ? `Auto-started fresh side-kick '${name}' (no prior history). ` : "";
        return {
          content: [{ type: "text", text:
            `${banner}Dispatched to side-kick '${name}' in the background — end your turn; its reply arrives automatically as a follow-up when ready. ` +
            `(A send while it's still working is rejected; reclaim with sidekick_stop. Pass wait:true to block for the reply in this turn instead.)` }],
          details: { name, dispatched: true, created: autoCreated },
        };
      }

      // wait:true -- block for the reply in THIS turn, bounded by a wall-clock
      // checkpoint. Only for a tight synchronous loop where yielding buys nothing.
      entry.onPreview = (t) => onUpdate?.({ content: [{ type: "text", text: t }] });
      const onAbort = () => { void entry!.handle.abort(); };
      signal?.addEventListener("abort", onAbort);
      // Wall-clock interrupt (graceful, NOT a kill): the silence-based health
      // timeout never trips a side-kick that keeps thinking, so bound the send
      // in real time. On timeout we STEER a checkpoint into the running turn
      // ("what are you working on? pause and wait"), let it report and pause
      // WITHOUT discarding its context, and hand continue-vs-stop to the
      // primary. Abort is only a last resort if it refuses to pause.
      const skSettings = loadSettings(ctx.cwd).sidekick;
      const timeoutSeconds = params.timeoutSeconds ?? skSettings.timeoutSeconds ?? DEFAULT_SIDEKICK_TIMEOUT_SECONDS;
      const graceSeconds = Math.max(20, Math.min(60, Math.round(timeoutSeconds / 4)));
      let interrupted = false;
      let hadToAbort = false;
      try {
        const promptP = entry.handle.prompt(text);
        let res: { ok: boolean; report: string; error?: string };
        if (timeoutSeconds > 0) {
          const first = await raceWithTimeout(promptP, timeoutSeconds * 1000);
          if (first.timedOut) {
            interrupted = true;
            // Ask what it's doing + tell it to pause. Does NOT kill the turn.
            try { await entry.handle.steer(SIDEKICK_CHECKPOINT_MSG); } catch {}
            const second = await raceWithTimeout(promptP, graceSeconds * 1000);
            if (second.timedOut) {
              // It didn't pause when asked — reclaim control as a last resort.
              // The side-kick (session + memory) survives; only this turn ends.
              hadToAbort = true;
              void entry.handle.abort();
              res = await promptP.catch((e: any) => ({ ok: false, report: entry.streamBuf, error: String(e?.message ?? e) }));
            } else {
              res = second.value!;
            }
          } else {
            res = first.value!;
          }
        } else {
          res = await promptP;
        }
        entry.firstSendDone = true;
        entry.sends++;
        if (interrupted) {
          const status = (res.report?.trim()) || "";
          const prog = [
            status ? `[what it says it's working on]\n${status}` : "",
            !status && entry.streamBuf.trim() ? entry.streamBuf.trim() : "",
            entry.thinkTail.trim() ? `[latest thinking]\n${entry.thinkTail.trim()}` : "",
          ].filter(Boolean).join("\n\n");
          const abortNote = hadToAbort
            ? `\n\n(It did not pause within ${graceSeconds}s of being asked, so I ended its current turn to hand control back — its memory/context is intact, so "continue" still works.)`
            : "";
          const body =
            `⏸ CHECKPOINT after ${timeoutSeconds}s — I paused the side-kick and asked what it's working on (it is NOT killed; it keeps all its context).\n\n` +
            `${prog || "(it produced no status yet)"}${abortNote}\n\n` +
            `YOU decide: sidekick_send({ name: "${name}", message: "continue" }) to let it resume, or sidekick_stop({ name: "${name}" }) if it's done / off-track.`;
          return {
            content: [{ type: "text", text: body }],
            isError: false,
            details: { name, sends: entry.sends, status: entry.handle.status, interrupted: true, aborted: hadToAbort, timeoutSeconds },
          };
        }
        // Make implicit creation visible: a caller expecting an established
        // companion should be able to tell it just got a blank-slate one.
        const banner = autoCreated ? `(auto-started fresh side-kick '${name}' — no prior history)\n\n` : "";
        const body = banner + (res.report?.trim() || "(side-kick returned no text)");
        return {
          content: [{ type: "text", text: body }],
          isError: !res.ok,
          details: { name, sends: entry.sends, status: entry.handle.status, created: autoCreated, error: res.error },
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

function match(text: string, re: RegExp): string | null {
  const m = re.exec(text);
  return m ? m[1].toUpperCase() : null;
}
function tail(s: string, maxChars: number): string {
  if (s.length <= maxChars) return s;
  return `[truncated leading ${s.length - maxChars} chars]\n${s.slice(-maxChars)}`;
}
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
  // Reuse the PARENT session's authenticated registry. Critical at Meta: auth
  // flows through the AI Gateway via a runtime API key the parent fetched
  // (auth.json is empty, ANTHROPIC_API_KEY is a placeholder). We seed that key
  // into the child's ModelRuntime via setRuntimeApiKey (see createSdkAgent),
  // else every model call 401s ("invalid x-api-key"). Pass ctx.modelRegistry.
  modelRegistry?: any;
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

// A bare, unprefixed Claude id (or family alias) resolves against ALL providers
// when handed to `pi --model`, and on this host that can land on a provider with
// no working key (amazon-bedrock / cloudflare-ai-gateway) -> an instant 401. Pin
// the common Claude case to the gateway-authed `anthropic` provider. Anything
// already provider-qualified (has a "/") or non-Claude is left untouched.
const CLAUDE_BARE_RE = /^(claude|sonnet|opus|haiku)[\w.\-]*$/i;
function normalizeModelSpec(spec: string | undefined): string | undefined {
  if (!spec) return spec;
  const s = spec.trim();
  if (!s || s.includes("/")) return spec; // empty or already provider-qualified
  const { id } = splitModelSpec(s); // id = spec minus any :thinking suffix
  return CLAUDE_BARE_RE.test(id) ? `anthropic/${s}` : spec;
}

// Resolve a model string to a Model object via the registry. Returns
// undefined when unspecified OR unresolvable — caller then omits `model`
// and createAgentSession falls back to the settings default.
async function resolveModelSpec(registry: any, spec: string | undefined): Promise<any | undefined> {
  if (!spec) return undefined;
  const { provider, id } = splitModelSpec(normalizeModelSpec(spec) ?? spec);
  try {
    if (provider) {
      const found = registry.find?.(provider, id);
      if (found) return found;
      // Fall through: an explicit provider that didn't resolve still gets the
      // avail scan below, which is bounded to models that have a key (no no-key
      // provider), so it can't reintroduce the 401 footgun.
    }
    const avail = (await registry.getAvailable?.()) ?? [];
    const lc = id.toLowerCase();
    const idOf = (m: any) => String(m?.id ?? m?.model ?? "").toLowerCase();
    const providerOf = (m: any) => String(m?.provider ?? m?.providerId ?? "");
    // Prefer a provider with configured auth among the matches, so a tie doesn't
    // resolve to a present-but-dead key by array order. Best-effort and sync; if
    // the registry doesn't expose hasConfiguredAuth this no-ops (treats all as ok).
    const authed = (m: any) => {
      try { return registry.hasConfiguredAuth?.(providerOf(m)) !== false; } catch { return true; }
    };
    const matches = [
      ...avail.filter((m: any) => idOf(m) === lc),
      ...avail.filter((m: any) => idOf(m).includes(lc)),
      ...avail.filter((m: any) => String(m?.name ?? "").toLowerCase().includes(lc)),
    ];
    const picked = matches.find(authed) ?? matches[0];
    if (!picked) {
      // A given-but-unresolved spec silently falls back to the session default;
      // leave a breadcrumb pointing at the usual fix.
      console.warn(
        `[subagent] model '${spec}' did not resolve to an available model; using ` +
          `the session default. Pin it with an explicit provider, e.g. anthropic/${id}.`,
      );
    }
    return picked;
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
  // pi 0.84 replaced createAgentSession's authStorage/modelRegistry options with an
  // async modelRuntime (AuthStorage is no longer exported -- calling it was the
  // "AuthStorage.create internal fault" that broke the side-kick). We still resolve
  // the model against the parent's ctx.modelRegistry, then seed the parent's runtime
  // KEY into a fresh ModelRuntime so the in-process child shares the gateway
  // credential (see CreateSdkAgentOpts note). Best-effort: a missing key surfaces
  // later as a caught prompt error, never a hard crash at setup.
  const registry = opts.modelRegistry;
  const model = await resolveModelSpec(registry, opts.model);
  const tools = parseToolsCsv(opts.tools);

  const modelRuntime = await ModelRuntime.create();
  // A fresh ModelRuntime only has the built-in (unauthenticated) model catalogue.
  // At Meta the working auth is NOT an API key (auth.json is empty, ANTHROPIC_API_KEY
  // is a placeholder) -- it's the AI-Gateway config (baseUrl + X-Meta-AI-Gateway-*
  // headers) held in the PARENT's registered providers. Copy each registered provider
  // config from ctx.modelRegistry onto the child runtime so it inherits the gateway
  // credentials, then rebuild + refresh availability. Best-effort: if this fails the
  // child still starts and a bad-auth call surfaces as a caught prompt error, not a
  // crash. (registerNativeProvider is unusable here -- getRegisteredNativeProvider
  // returns undefined -- so we use the provider CONFIG + registerProvider.)
  try {
    for (const id of (registry?.getRegisteredProviderIds?.() ?? [])) {
      const cfg = registry?.getRegisteredProviderConfig?.(id);
      if (cfg) (modelRuntime as any).registerProvider(cfg);
    }
    (modelRuntime as any).rebuildProviders?.();
    await (modelRuntime as any).refresh?.();
  } catch { /* see note: child still starts; bad auth surfaces as a caught prompt error */ }

  const { session } = await withAgentChildEnv(async () => {
    const resourceLoader = new DefaultResourceLoader({ cwd: opts.cwd, agentDir: getAgentDir() });
    await resourceLoader.reload();
    return await createAgentSession({
      cwd: opts.cwd,
      modelRuntime,
      ...(model ? { model } : {}),
      ...(tools ? { tools } : {}),
      resourceLoader,
      sessionManager: SessionManager.inMemory(opts.cwd),
    } as any);
  });

  let status: SdkAgentStatus = "idle";
  let latestReport = "";
  // Provider errors (e.g. a 401 from the gateway) are not thrown by
  // session.prompt(); the SDK records them on the assistant message as
  // stopReason=="error" with an errorMessage and resolves "successfully" with
  // empty content. Capture that so prompt() can surface it instead of the
  // misleading "(side-kick returned no text)".
  let lastError: string | undefined;
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
    if ((event.type === "message_end" || event.type === "turn_end") && event.message?.role === "assistant") {
      const t = sdkMessageText(event.message).trim();
      if (t) latestReport = t;
      if (event.message.stopReason === "error" && event.message.errorMessage) {
        lastError = String(event.message.errorMessage);
      }
    }
  });

  return {
    tag: opts.tag,
    get status() { return status; },
    get latestReport() { return latestReport; },
    async prompt(prompt: string) {
      status = "running";
      // Reset per-send capture: the handle is reused across sends (side-kick),
      // so a new prompt must not inherit the previous reply or a stale error.
      latestReport = "";
      lastError = undefined;
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
        // Provider errors are swallowed into the assistant message rather than
        // thrown, so an empty report + captured error means the call failed.
        if (!latestReport && lastError) {
          status = "error";
          emit({ type: "error", text: lastError, isError: true });
          return { ok: false, report: "", error: lastError };
        }
        status = "done";
        emit({ type: "status", text: `done @${opts.tag}` });
        return { ok: true, report: latestReport, error: lastError };
      } catch (err: any) {
        clearInterval(timer);
        status = "error";
        const error = healthTimedOut ? "health timeout" : (err?.message ?? String(err) ?? lastError);
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
  // Parent's authenticated registry (resolves the runtime gateway API key via
  // getProviderAuth), so in-process role agents seed the parent's credential into
  // their ModelRuntime instead of coming up unauthenticated. See createSdkAgent.
  modelRegistry?: any;
}

// early-returns in child sessions), so children never populate this.
const sidekicks = new Map<string, SidekickEntry>();

// Names explicitly stopped via sidekick_stop / disposeSidekick. Makes a
// send-after-stop fail loudly once, instead of silently spawning a fresh,
// amnesiac side-kick that masquerades as the original. Cleared when a
// side-kick of that name is (re)created.
const stoppedSidekicks = new Set<string>();

async function startSidekick(opts: {
  name: string;
  role: string;
  model?: string;
  tools?: string;
  cwd: string;
  healthTimeoutMs: number;
  // Parent's authenticated registry (carries the runtime gateway API key).
  modelRegistry?: any;
  authStorage?: any;
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
    thinkTail: "",
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
    modelRegistry: opts.modelRegistry,
    authStorage: opts.authStorage,
    onEvent: (e) => {
      const t = e.text ?? "";
      if (e.type === "text") {
        entry.streamBuf += t;
        entry.onPreview?.(entry.streamBuf);
      } else if (e.type === "thinking") {
        entry.thinkTail = (entry.thinkTail + t).slice(-1200);
      } else if (e.type === "tool-call" || e.type === "tool-result") {
        entry.streamBuf += `\n${t}\n`;
        entry.onPreview?.(entry.streamBuf);
      }
    },
  });
  sidekicks.set(opts.name, entry);
  stoppedSidekicks.delete(opts.name);
  return entry;
}

function disposeSidekick(name: string): boolean {
  const entry = sidekicks.get(name);
  if (!entry) return false;
  try { entry.handle.dispose(); } catch {}
  sidekicks.delete(name);
  stoppedSidekicks.add(name);
  return true;
}

function sidekickSummaryLine(e: SidekickEntry): string {
  const age = Math.round((Date.now() - e.createdAt) / 1000);
  return `${e.name} [${e.handle.status}] model=${e.model ?? "(default)"} sends=${e.sends} age=${age}s`;
}
