import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { basename, join } from "node:path";

// subagent-log-analysis — export a root pi session plus the artifacts of any
// supervise run it spawned into ONE combined JSONL (+ a Markdown summary), so
// the whole thing can be handed to another AI session to answer "why did this
// supervise loop behave this way?".
//
// This is a from-our-conventions port of Ivan Gromov's analysis-log.ts.
// Structure and
// logic are ported; the imports are @earendil-works/pi-coding-agent (NOT
// @mariozechner), the command-dispatch + getArgumentCompletions shape mirrors
// our projects.ts, and the run-dir layout it folds in is the one written by
// our config/pi/extensions/subagent.ts `makeRunDir` / supervise loop:
//
//   <root>/<iso>-<slug>-<id>/
//     dispatcher-initial.md
//     dispatcher-feedback-<ts>.md
//     dispatcher-iteration-<n>.md
//     execution-iteration-<n>.md
//     supervisor-iteration-<n>.md
//     user-approved-plan.md
//     user-response-iteration-<n>.md
//     summary.md
//     oracle/oracle.sh
//     oracle/runs/oracle-iteration-<n>.{sh,txt}
//     oracle/state/...
//     evidence/attempt-<n>-status.txt
//     evidence/attempt-<n>-diff.patch
//     sessions/*.jsonl          (child sessions, if a future run writes them)
//
//   where <root> is <cwd>/.pi/supervise-runs (project-local, preferred) or
//   ~/.pi/agent/supervise-runs (user-scoped fallback) — exactly the two roots
//   makeRunDir() chooses between.
//
// Commands:
//   /subagent-log-analysis status     → root session id/path + #run dirs found
//   /subagent-log-analysis export     → write <cwd>/.pi/subagent-log-analysis/<id>.jsonl
//   /subagent-log-analysis summarize  → export JSONL + a .md companion summary
//   /subagent-log-analysis open       → print the JSONL + MD paths
//   (no arg)                          → behaves like status

const COMMAND = "subagent-log-analysis";
const LOG_DIR = join(".pi", "subagent-log-analysis");

// Truncate any single text field longer than this, leaving a marker. Mirrors
// Ivan's per-field caps but with one shared limit for simplicity.
const MAX_FIELD_CHARS = 20_000;

// Interesting artifact files (top-level of a run dir). Anything not matched
// here is skipped to keep the export focused.
const TOP_LEVEL_ARTIFACT_RE =
  /^(dispatcher-.*\.md|execution-iteration-.*\.md|supervisor-iteration-.*\.md|summary\.md|user-approved-plan\.md|user-response-iteration-.*\.md)$/;

// ---------------------------------------------------------------------------
// small helpers (Node fs/path only)
// ---------------------------------------------------------------------------

function nowIso(): string {
  return new Date().toISOString();
}

// truncate/tail helper (Ivan has one) — keep the HEAD of oversize text and
// append a marker noting how many chars were dropped.
function truncate(text: string, maxChars: number = MAX_FIELD_CHARS): string {
  if (typeof text !== "string") return text;
  if (text.length <= maxChars) return text;
  const dropped = text.length - maxChars;
  return `${text.slice(0, maxChars)}\n[truncated ${dropped} chars]`;
}

// Deep-ish copy of an entry that truncates any string field over the cap.
// Defensive against cycles via a seen-set; non-plain values pass through.
function truncateDeep(value: any, seen: WeakSet<object> = new WeakSet()): any {
  if (typeof value === "string") return truncate(value);
  if (value === null || typeof value !== "object") return value;
  if (seen.has(value)) return "[circular]";
  seen.add(value);
  if (Array.isArray(value)) return value.map((v) => truncateDeep(v, seen));
  const out: Record<string, any> = {};
  for (const [k, v] of Object.entries(value)) out[k] = truncateDeep(v, seen);
  return out;
}

// --- message normalization (Ivan's normalizeMessage, adapted) --------------
// Flatten a message's content into readable text: plain text, [thinking], and
// [toolCall name {...}] inline. Returns the (truncated) text plus how much was
// dropped, so the analyst knows when a message was clipped.
interface TextBlob {
  text: string;
  truncated: boolean;
  originalChars: number;
}

function textBlob(content: any, maxChars: number = MAX_FIELD_CHARS): TextBlob {
  let s = "";
  if (typeof content === "string") {
    s = content;
  } else if (Array.isArray(content)) {
    const parts: string[] = [];
    for (const p of content) {
      if (p?.type === "text") parts.push(p.text ?? "");
      else if (p?.type === "thinking") parts.push(`[thinking]\n${p.thinking ?? ""}`);
      else if (p?.type === "toolCall") parts.push(`[toolCall ${p.name ?? "?"}] ${JSON.stringify(p.arguments ?? {})}`);
    }
    s = parts.join("\n");
  }
  if (s.length <= maxChars) return { text: s, truncated: false, originalChars: s.length };
  return { text: `${s.slice(0, maxChars)}\n[truncated ${s.length - maxChars} chars]`, truncated: true, originalChars: s.length };
}

function toolCallsFrom(content: any): Array<{ id?: string; name: string; arguments: unknown }> {
  if (!Array.isArray(content)) return [];
  const out: Array<{ id?: string; name: string; arguments: unknown }> = [];
  for (const p of content) {
    if (p?.type === "toolCall") out.push({ id: p.id, name: p.name ?? "?", arguments: p.arguments ?? {} });
  }
  return out;
}

// Turn one raw session entry into a compact, flat, analyzable event. Known types
// (message / custom_message / custom / compaction / branch_summary) get a
// purpose-built shape; anything unrecognized falls back to the lossless
// raw-truncated form so nothing is silently dropped. `source` is root | child.
function normalizeEntry(entry: any, source: "root" | "child"): Record<string, unknown> {
  const t = entry?.type;
  const base = { source, entryId: entry?.id, parentId: entry?.parentId, timestamp: entry?.timestamp };
  if (t === "custom_message") {
    return { kind: "custom_message", ...base, customType: entry.customType, content: textBlob(entry.content), display: entry.display, details: truncateDeep(entry.details) };
  }
  if (t === "custom") {
    return { kind: "custom", ...base, customType: entry.customType, data: truncateDeep(entry.data) };
  }
  if (t === "compaction") {
    return { kind: "compaction", ...base, firstKeptEntryId: entry.firstKeptEntryId, tokensBefore: entry.tokensBefore, summary: truncate(String(entry.summary ?? "")), details: truncateDeep(entry.details) };
  }
  if (t === "branch_summary") {
    return { kind: "branch_summary", ...base, fromId: entry.fromId, summary: truncate(String(entry.summary ?? "")), details: truncateDeep(entry.details) };
  }
  if (t === "message") {
    const m = entry.message ?? {};
    return {
      kind: "message",
      ...base,
      role: m.role,
      model: m.model,
      provider: m.provider,
      stopReason: m.stopReason,
      errorMessage: m.errorMessage,
      usage: m.usage,
      toolName: m.toolName,
      toolCallId: m.toolCallId,
      isError: m.isError,
      content: textBlob(m.content),
      toolCalls: toolCallsFrom(m.content),
      details: m.role === "toolResult" ? truncateDeep(m.details) : undefined,
    };
  }
  // Unknown type: keep it, lossless-ish.
  return { kind: "entry", source, type: t, ...truncateDeep(entry) };
}

function safeRead(filePath: string): string {
  return readFileSync(filePath, "utf8");
}

function listDirNames(dir: string): string[] {
  try {
    return readdirSync(dir, { withFileTypes: true })
      .filter((e) => e.isDirectory())
      .map((e) => e.name)
      .sort();
  } catch {
    return [];
  }
}

function listFileNames(dir: string): string[] {
  try {
    return readdirSync(dir, { withFileTypes: true })
      .filter((e) => e.isFile())
      .map((e) => e.name)
      .sort();
  } catch {
    return [];
  }
}

// The two roots makeRunDir() can write supervise runs into, for this cwd.
function superviseRunRoots(cwd: string): string[] {
  return [
    join(cwd, ".pi", "supervise-runs"),
    join(homedir(), ".pi", "agent", "supervise-runs"),
  ];
}

// Run dirs the SESSION itself points at: `details.runDir` on any entry, and any
// `Artifacts: <path>` string in message text. (Ivan's idea — catches runs that
// live outside the standard roots: a custom artifactRoot, or a run from a
// different cwd — which a root-glob alone would miss.)
function runDirsFromSession(ctx: any): string[] {
  const out = new Set<string>();
  let branch: any[] = [];
  try {
    branch = ctx.sessionManager?.getBranch?.() ?? [];
  } catch {
    branch = [];
  }
  for (const e of branch) {
    const details = (e as any)?.message?.details ?? (e as any)?.details;
    if (typeof details?.runDir === "string") out.add(details.runDir);
    const content = (e as any)?.message?.content ?? (e as any)?.content;
    let text = "";
    if (typeof content === "string") text = content;
    else if (Array.isArray(content)) text = content.map((p: any) => p?.text ?? "").join("\n");
    for (const m of text.matchAll(/Artifacts:\s*(\S+)/g)) out.add(m[1]);
  }
  return [...out];
}

// Discover every supervise run dir reachable for this session: the two standard
// roots for this cwd (immediate child dirs) UNION anything the session points
// at (runDirsFromSession), filtered to real directories and deduped.
function discoverRunDirs(ctx: any): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  const add = (full: string) => {
    if (!seen.has(full)) {
      seen.add(full);
      out.push(full);
    }
  };
  for (const root of superviseRunRoots(ctx.cwd)) {
    for (const name of listDirNames(root)) add(join(root, name));
  }
  for (const d of runDirsFromSession(ctx)) {
    try {
      if (existsSync(d) && statSync(d).isDirectory()) add(d);
    } catch {
      /* skip unreadable / non-dir */
    }
  }
  return out.sort();
}

function ensureLogDir(cwd: string): string {
  const dir = join(cwd, LOG_DIR);
  mkdirSync(dir, { recursive: true });
  return dir;
}

function rootSessionId(ctx: any): string {
  try {
    // Prefer an explicit session id if the fork exposes one...
    const id = ctx.sessionManager?.getSessionId?.();
    if (id) return String(id);
    // ...otherwise derive a stable id from the session file name (what
    // find-session does), so each session exports to its own file rather
    // than everything colliding on "ephemeral".
    const file = ctx.sessionManager?.getSessionFile?.();
    if (file) return basename(String(file)).replace(/\.jsonl$/i, "");
  } catch {}
  return "ephemeral";
}

function jsonlPath(ctx: any): string {
  return join(ensureLogDir(ctx.cwd), `${rootSessionId(ctx)}.jsonl`);
}

function mdPath(ctx: any): string {
  return join(ensureLogDir(ctx.cwd), `${rootSessionId(ctx)}.md`);
}

// ---------------------------------------------------------------------------
// JSONL line builders — each returns one object to be JSON.stringify'd.
// Every file read is wrapped in try/catch; failures become {kind:"error"}
// lines so a bad file can never throw out of the exporter.
// ---------------------------------------------------------------------------

function pushLine(lines: string[], obj: Record<string, unknown>): void {
  lines.push(JSON.stringify(obj));
}

function pushError(lines: string[], file: string, err: unknown): void {
  pushLine(lines, {
    kind: "error",
    file,
    message: err instanceof Error ? err.message : String(err),
  });
}

// One artifact file → one { kind:"artifact" } line (content truncated).
function appendArtifact(
  lines: string[],
  runDir: string,
  relFile: string,
  absFile: string,
): void {
  let content = "";
  try {
    content = safeRead(absFile);
  } catch (err) {
    pushError(lines, absFile, err);
    return;
  }
  pushLine(lines, {
    kind: "artifact",
    runDir,
    file: relFile,
    contentTruncated: truncate(content),
  });
}

// One child session .jsonl under sessions/ → a { kind:"child-session-start" }
// frame, one normalized event per entry (source:"child", tagged with runDir +
// sessionFile), then a { kind:"child-session-end" } frame. A parse failure on
// one line becomes an {kind:"error"} line and we keep going.
function appendChildSession(
  lines: string[],
  runDir: string,
  relFile: string,
  absFile: string,
): void {
  let raw = "";
  try {
    raw = safeRead(absFile);
  } catch (err) {
    pushError(lines, absFile, err);
    return;
  }
  const entries: any[] = [];
  for (const line of raw.split(/\r?\n/)) {
    if (!line.trim()) continue;
    try {
      entries.push(JSON.parse(line));
    } catch (err) {
      pushLine(lines, {
        kind: "error",
        file: absFile,
        message: `child-session parse error: ${err instanceof Error ? err.message : String(err)}`,
      });
    }
  }
  // Frame the child transcript so the analyst knows which run/session a block of
  // normalized entries belongs to (Ivan's child_session_start/end).
  pushLine(lines, { kind: "child-session-start", runDir, sessionFile: relFile, entries: entries.length });
  for (const entry of entries) {
    pushLine(lines, { ...normalizeEntry(entry, "child"), runDir, sessionFile: relFile });
  }
  pushLine(lines, { kind: "child-session-end", runDir, sessionFile: relFile });
}

// One run dir → a { kind:"run-dir" } header, then one line per interesting
// artifact, then child-session entries for any sessions/*.jsonl.
function appendRunDir(lines: string[], runDir: string): void {
  // Gather the interesting file list defensively.
  const topFiles = listFileNames(runDir).filter((n) => TOP_LEVEL_ARTIFACT_RE.test(n));
  const oracleRunFiles = listFileNames(join(runDir, "oracle", "runs"))
    .filter((n) => n.endsWith(".txt"))
    .map((n) => join("oracle", "runs", n));
  const evidenceFiles = listFileNames(join(runDir, "evidence"))
    .filter((n) => n.endsWith(".txt") || n.endsWith(".patch"))
    .map((n) => join("evidence", n));
  const sessionFiles = listFileNames(join(runDir, "sessions"))
    .filter((n) => n.endsWith(".jsonl"))
    .map((n) => join("sessions", n));

  const allRel = [...topFiles, ...oracleRunFiles, ...evidenceFiles, ...sessionFiles];

  pushLine(lines, { kind: "run-dir", path: runDir, files: allRel });

  for (const rel of [...topFiles, ...oracleRunFiles, ...evidenceFiles]) {
    appendArtifact(lines, runDir, rel, join(runDir, rel));
  }
  for (const rel of sessionFiles) {
    appendChildSession(lines, runDir, rel, join(runDir, rel));
  }
}

// Build the full ordered list of JSONL lines for this session.
function buildExport(ctx: any): { lines: string[]; runDirs: string[] } {
  const lines: string[] = [];
  const sessionId = rootSessionId(ctx);
  let sessionFile: string | null = null;
  try {
    sessionFile = ctx.sessionManager?.getSessionFile?.() ?? null;
  } catch {
    sessionFile = null;
  }

  // 1. header line.
  pushLine(lines, {
    kind: "root-session",
    sessionId,
    sessionFile,
    cwd: ctx.cwd,
    exportedAt: nowIso(),
  });

  // 2. root session branch entries.
  let branch: any[] = [];
  try {
    branch = ctx.sessionManager?.getBranch?.() ?? [];
  } catch (err) {
    pushError(lines, sessionFile ?? "(branch)", err);
  }
  for (const entry of branch) {
    try {
      pushLine(lines, normalizeEntry(entry, "root"));
    } catch (err) {
      pushError(lines, sessionFile ?? "(entry)", err);
    }
  }

  // 3. supervise run dirs + their artifacts (+ child sessions).
  const runDirs = discoverRunDirs(ctx);
  for (const runDir of runDirs) {
    try {
      appendRunDir(lines, runDir);
    } catch (err) {
      pushError(lines, runDir, err);
    }
  }

  return { lines, runDirs };
}

// Write the JSONL and return where + how many lines.
function writeJsonl(ctx: any): { path: string; lines: number; runDirs: string[] } {
  const { lines, runDirs } = buildExport(ctx);
  const outPath = jsonlPath(ctx);
  writeFileSync(outPath, lines.length ? `${lines.join("\n")}\n` : "", "utf8");
  return { path: outPath, lines: lines.length, runDirs };
}

// ---------------------------------------------------------------------------
// Markdown summary
// ---------------------------------------------------------------------------

interface RunDigest {
  path: string;
  decision: string;
  iterations: string;
  oracle: string;
}

// Parse a run dir's summary.md (written by buildSupervisorSummary in
// subagent.ts) for the final decision / iteration count / oracle line. All
// best-effort; missing fields read "(unknown)".
function digestRunDir(runDir: string): RunDigest {
  const digest: RunDigest = {
    path: runDir,
    decision: "(unknown)",
    iterations: "(unknown)",
    oracle: "(unknown)",
  };
  const summaryFile = join(runDir, "summary.md");
  let body = "";
  try {
    if (existsSync(summaryFile)) body = safeRead(summaryFile);
  } catch {
    return digest;
  }
  if (!body) return digest;

  const decisionMatch = body.match(/^- final decision:\s*(.+)$/m);
  if (decisionMatch) digest.decision = decisionMatch[1].trim();

  const iterMatch = body.match(/^- iterations:\s*(.+)$/m);
  if (iterMatch) digest.iterations = iterMatch[1].trim();

  // "- oracle: exit=0 assertions=-1"  (assertions may be -1 when disabled)
  const oracleMatch = body.match(/^- oracle:\s*(.+)$/m);
  if (oracleMatch) {
    const o = oracleMatch[1].trim();
    const exitMatch = o.match(/exit=(-?\d+)/);
    if (exitMatch) {
      digest.oracle = exitMatch[1] === "0" ? `pass (${o})` : `fail (${o})`;
    } else {
      digest.oracle = o;
    }
  }
  return digest;
}

// Broad net for the failure shortlist (Ivan's regex): matches benign mentions
// too, on purpose — it's a starting point for the analyst, not a verdict.
const FAILURE_RE = /failed|error|timed out|health check/i;

// Re-read the JSONL we just wrote, as parsed objects (skip unparseable lines).
function readEventObjs(filePath: string): any[] {
  const out: any[] = [];
  let raw = "";
  try {
    raw = readFileSync(filePath, "utf8");
  } catch {
    return out;
  }
  for (const line of raw.split(/\r?\n/)) {
    if (!line.trim()) continue;
    try {
      out.push(JSON.parse(line));
    } catch {
      /* skip */
    }
  }
  return out;
}

// Flatten one normalized event's message text + whether it errored. Reads the
// TextBlob content.text (root and child events share the same normalized shape),
// folding in summaries and errorMessage so the failure net and the analyst both
// see them.
function eventSignal(obj: any): { text: string; isError: boolean } {
  // Normalized events carry content as a TextBlob {text} and flags at top level.
  const c = obj?.content;
  let text = "";
  if (typeof c === "string") text = c;
  else if (c && typeof c.text === "string") text = c.text;
  else if (Array.isArray(c)) text = c.map((p: any) => p?.text ?? p?.thinking ?? "").join("\n");
  if (typeof obj?.summary === "string") text += `\n${obj.summary}`;
  if (typeof obj?.errorMessage === "string") text += `\n${obj.errorMessage}`;
  const isError = obj?.isError === true || obj?.stopReason === "error";
  return { text, isError };
}

function writeMarkdown(ctx: any, jsonlAbsPath: string, lineCount: number): string {
  const sessionId = rootSessionId(ctx);
  let entryCount = 0;
  try {
    entryCount = (ctx.sessionManager?.getBranch?.() ?? []).length;
  } catch {
    entryCount = 0;
  }
  const runDirs = discoverRunDirs(ctx);
  const digests = runDirs.map(digestRunDir);

  // Re-read the JSONL to tally event kinds and net for failures (Ivan's idea:
  // give the analyst — human or AI — a shortlist + counts to start from instead
  // of scanning the whole log).
  const events = readEventObjs(jsonlAbsPath);
  const counts: Record<string, number> = {};
  for (const ev of events) {
    const k = String(ev?.kind ?? "?");
    counts[k] = (counts[k] ?? 0) + 1;
  }
  const FAIL_KINDS = new Set(["message", "custom_message", "compaction", "branch_summary", "entry"]);
  const failures: string[] = [];
  for (const ev of events) {
    if (!FAIL_KINDS.has(String(ev?.kind))) continue;
    const { text, isError } = eventSignal(ev);
    if (!isError && !FAILURE_RE.test(text)) continue;
    const id = ev.entryId ?? ev.id ?? "";
    const src = ev.source === "child" ? `child ${basename(String(ev.sessionFile ?? ""))}` : "root";
    failures.push(`- ${src} ${ev.kind}${id ? ` ${id}` : ""}: ${text.replace(/\s+/g, " ").slice(0, 300)}`);
  }

  const lines: string[] = [];
  lines.push(`# Subagent log analysis — ${sessionId}`);
  lines.push("");
  lines.push(`- cwd: ${ctx.cwd}`);
  lines.push(`- root session entries: ${entryCount}`);
  lines.push(`- supervise run dirs: ${runDirs.length}`);
  lines.push(`- JSONL: ${jsonlAbsPath} (${lineCount} lines)`);
  lines.push("");
  lines.push("## Event counts");
  lines.push("");
  const countKeys = Object.keys(counts).sort();
  if (countKeys.length === 0) lines.push("_(no events)_");
  else for (const k of countKeys) lines.push(`- ${k}: ${counts[k]}`);
  lines.push("");
  lines.push("## Potential failures / errors");
  lines.push("");
  lines.push(
    "_Broad net: any entry with isError / stopReason=error, or whose text " +
      "matches failed|error|timed out|health check. Includes benign mentions._",
  );
  lines.push("");
  if (failures.length === 0) {
    lines.push("(none detected)");
  } else {
    for (const f of failures.slice(0, 50)) lines.push(f);
    if (failures.length > 50) lines.push(`- … and ${failures.length - 50} more`);
  }
  lines.push("");
  lines.push("## Supervise runs");
  lines.push("");
  if (digests.length === 0) {
    lines.push("_No supervise run dirs found for this session._");
  } else {
    for (const d of digests) {
      lines.push(`### ${basename(d.path)}`);
      lines.push(`- path: ${d.path}`);
      lines.push(`- final decision: ${d.decision}`);
      lines.push(`- iterations: ${d.iterations}`);
      lines.push(`- oracle: ${d.oracle}`);
      lines.push("");
    }
  }
  lines.push("## How to analyze");
  lines.push("");
  lines.push(
    "Feed the JSONL above to another AI session. Each line is one object " +
      "tagged by `kind` (root-session, message, custom_message, custom, " +
      "compaction, branch_summary, run-dir, artifact, child-session-start, " +
      "child-session-end, error). Messages carry flattened content.text (text + " +
      "[thinking] + [toolCall]) and a toolCalls[]. Trace the supervise loop: " +
      "dispatcher plan → user-approved-plan " +
      "→ executor reports → oracle runs → supervisor verdicts → summary, and " +
      "correlate decisions with the evidence patches.",
  );
  lines.push("");
  lines.push("## Suggested analysis prompt");
  lines.push("");
  lines.push(
    "Analyze the JSONL log referenced above. Focus on why child executor / " +
      "subagent agents underperformed compared with interactive root-agent " +
      "work. Compare prompt packets, inherited context, tool usage, steering, " +
      "supervisor feedback, health/timeout events, oracle evidence, and " +
      "workspace diffs. Call out where the orchestration leaked — lost context, " +
      "missing tools, premature reaping, or a child that never got the fast path.",
  );
  lines.push("");

  const outPath = mdPath(ctx);
  writeFileSync(outPath, lines.join("\n"), "utf8");
  return outPath;
}

// ---------------------------------------------------------------------------
// extension factory
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
  // Recursion guard: children load this file too, but the env var makes them
  // return before registering. (Same pattern as subagent.ts.)
  if (process.env.PI_AGENT_TEAM_CHILD === "1") return;

  pi.registerCommand(COMMAND, {
    description:
      "Export this root session + its supervise run artifacts (and any child " +
      "sessions) to one JSONL (+ optional .md summary) for AI analysis. " +
      "Sub-actions: status | export | summarize | open.",

    getArgumentCompletions: (prefix: string) => {
      const subs = [
        { value: "status", label: "status", description: "Root session id + #run dirs found" },
        { value: "export", label: "export", description: "Write the combined JSONL" },
        { value: "summarize", label: "summarize", description: "JSONL + Markdown summary" },
        { value: "open", label: "open", description: "Print the JSONL + MD paths" },
      ];
      const filtered = subs.filter((s) => s.value.startsWith(prefix.toLowerCase()));
      return filtered.length > 0 ? filtered : null;
    },

    handler: async (rawArgs: string, ctx: any) => {
      const args = (rawArgs ?? "").trim();
      const sub = (args ? args.split(/\s+/)[0] : "status").toLowerCase();

      switch (sub) {
        case "status": {
          const sessionId = rootSessionId(ctx);
          let sessionFile = "(ephemeral)";
          try {
            sessionFile = ctx.sessionManager?.getSessionFile?.() ?? "(ephemeral)";
          } catch {
            sessionFile = "(ephemeral)";
          }
          const runDirs = discoverRunDirs(ctx);
          ctx.ui.notify(
            [
              "subagent log analysis",
              `  root session : ${sessionId}`,
              `  session file : ${sessionFile}`,
              `  cwd          : ${ctx.cwd}`,
              `  run dirs found: ${runDirs.length}`,
              "",
              `Run /${COMMAND} export to write the combined JSONL.`,
              `Run /${COMMAND} summarize to also write a Markdown summary.`,
            ].join("\n"),
            "info",
          );
          return;
        }

        case "export": {
          try {
            const r = writeJsonl(ctx);
            ctx.ui.notify(
              `Exported ${r.lines} JSONL lines (${r.runDirs.length} run dir(s)) to:\n${r.path}`,
              "info",
            );
          } catch (err: any) {
            ctx.ui.notify(`Export failed: ${err?.message ?? err}`, "error");
          }
          return;
        }

        case "summarize": {
          try {
            const r = writeJsonl(ctx);
            const md = writeMarkdown(ctx, r.path, r.lines);
            ctx.ui.notify(
              `subagent log analysis wrote:\n${r.path}\n${md}`,
              "info",
            );
          } catch (err: any) {
            ctx.ui.notify(`Summarize failed: ${err?.message ?? err}`, "error");
          }
          return;
        }

        case "open": {
          ctx.ui.notify(
            [
              `JSONL:    ${jsonlPath(ctx)}`,
              `Markdown: ${mdPath(ctx)}`,
            ].join("\n"),
            "info",
          );
          return;
        }

        default:
          ctx.ui.notify(
            `[${COMMAND}] unknown sub-command '${sub}'. Try: status, export, summarize, open`,
            "warning",
          );
      }
    },
  });
}
