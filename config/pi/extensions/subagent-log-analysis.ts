import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { basename, join } from "node:path";

// subagent-log-analysis — export a root pi session plus the artifacts of any
// supervise run it spawned into ONE combined JSONL (+ a Markdown summary), so
// the whole thing can be handed to another AI session to answer "why did this
// supervise loop behave this way?".
//
// This is a from-our-conventions port of Ivan Gromov's analysis-log.ts
// (fbsource/users/iv/ivangromov/subagent/analysis-log.ts). Structure and
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

// Discover every supervise run dir reachable for this cwd. A run dir is an
// immediate child directory of one of the roots above.
function discoverRunDirs(cwd: string): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  for (const root of superviseRunRoots(cwd)) {
    for (const name of listDirNames(root)) {
      const full = join(root, name);
      if (seen.has(full)) continue;
      seen.add(full);
      out.push(full);
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

// One child session .jsonl under sessions/ → a digest of each entry as a
// { kind:"child-entry" } line. Big fields truncated. A parse failure on one
// line becomes an {kind:"error"} line and we keep going.
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
  for (const line of raw.split(/\r?\n/)) {
    if (!line.trim()) continue;
    let entry: any;
    try {
      entry = JSON.parse(line);
    } catch (err) {
      pushLine(lines, {
        kind: "error",
        file: absFile,
        message: `child-session parse error: ${
          err instanceof Error ? err.message : String(err)
        }`,
      });
      continue;
    }
    pushLine(lines, {
      kind: "child-entry",
      runDir,
      sessionFile: relFile,
      entry: truncateDeep(entry),
    });
  }
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
      pushLine(lines, { kind: "entry", ...truncateDeep(entry) });
    } catch (err) {
      pushError(lines, sessionFile ?? "(entry)", err);
    }
  }

  // 3. supervise run dirs + their artifacts (+ child sessions).
  const runDirs = discoverRunDirs(ctx.cwd);
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

function writeMarkdown(ctx: any, jsonlAbsPath: string, lineCount: number): string {
  const sessionId = rootSessionId(ctx);
  let entryCount = 0;
  try {
    entryCount = (ctx.sessionManager?.getBranch?.() ?? []).length;
  } catch {
    entryCount = 0;
  }
  const runDirs = discoverRunDirs(ctx.cwd);
  const digests = runDirs.map(digestRunDir);

  const lines: string[] = [];
  lines.push(`# Subagent log analysis — ${sessionId}`);
  lines.push("");
  lines.push(`- cwd: ${ctx.cwd}`);
  lines.push(`- root session entries: ${entryCount}`);
  lines.push(`- supervise run dirs: ${runDirs.length}`);
  lines.push(`- JSONL: ${jsonlAbsPath} (${lineCount} lines)`);
  lines.push("");
  lines.push("## Supervise runs");
  lines.push("");
  if (digests.length === 0) {
    lines.push("_No supervise run dirs found for this cwd._");
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
      "tagged by `kind` (root-session, entry, run-dir, artifact, child-entry, " +
      "error). Trace the supervise loop: dispatcher plan → user-approved-plan " +
      "→ executor reports → oracle runs → supervisor verdicts → summary, and " +
      "correlate decisions with the evidence patches.",
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
          const runDirs = discoverRunDirs(ctx.cwd);
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
