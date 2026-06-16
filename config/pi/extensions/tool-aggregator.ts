import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  createBashTool,
  createEditTool,
  createLsTool,
  createReadTool,
  createWriteTool,
} from "@earendil-works/pi-coding-agent";
import { truncateToWidth } from "@earendil-works/pi-tui";

// Aggregate per-tool render output into a single live widget above the
// editor. The default "box per tool call" is noisy when the agent fires 20
// reads in a row; this collapses the visual to a single counter that updates
// as tools complete. Errors get their own line in the widget rather than
// rendering inline (pi's TUI doesn't reliably call renderResult for errored
// tools when renderShell:"self" is set).
//
// Layers:
//   1. Per-tool: wrap each built-in tool so renderCall/renderResult return
//      nothing visible — both success and error.
//   2. Live widget: pinned above the editor; updated on every
//      tool_execution_end with running counts. Errors get one extra line
//      each, prefixed `  ✗ <tool>: <first line of error>`. Cleared at
//      agent_start of the next prompt. Persists between agents so you can
//      glance at "what just happened" after the assistant answers.
//
// NOT persisted in the conversation stream: pi has no "display-only,
// don't-send-to-LLM" custom message type — all custom messages go to the
// LLM. Tried injecting at agent_end and it triggered an extra (failing) LLM
// call in `-p` mode. If pi later exposes a true display-only message type,
// we can add an end-of-turn persistent record then.
//
// Configurable via env:
//   PI_TOOL_AGG_DISABLE=1  — skip the entire extension. Useful when you
//                            actually want pi's default per-tool rendering.

const WIDGET_KEY = "tool-aggregator";
// Show in-flight tool output only after this elapsed time. Fast commands
// (<30s) get header-only; long commands graduate to "live" mode.
const LIVE_AFTER_MS = Number(process.env.PI_TOOL_AGG_LIVE_AFTER_MS) || 30_000;
// Hard cap on tail lines per live tool; further capped to terminalRows/3.
const LIVE_MAX_LINES = Number(process.env.PI_TOOL_AGG_LIVE_MAX_LINES) || 10;
// How often to re-render while at least one tool is in-flight. Drives the
// "elapsed > 30s → switch to live mode" transition without needing a new
// tool_execution_update event to land first.
const LIVE_POLL_MS = Number(process.env.PI_TOOL_AGG_LIVE_POLL_MS) || 2_000;

interface Counts {
  ok: number;
  err: number;
}

const EMPTY = { render: () => [], invalidate: () => {} };

export default function (pi: ExtensionAPI) {
  if (process.env.PI_TOOL_AGG_DISABLE === "1") return;

  const cwd = process.cwd();

  // (1) Per-tool: wrap each built-in to suppress all rendering. Errors are
  // surfaced via the widget instead (cleaner: one place for tool info).
  //
  // TODO: dedupe identical errors in the widget. When N parallel tools fail
  // with the same message (e.g. `sl status` outside a repo, all returning
  // "not a repo"), we currently show N lines. A small per-error-hash map
  // would collapse dupes to `✗ sl: not in a repo (×N)`.
  //
  // Note: `grep` and `find` are owned by Meta's bundled extension at
  // /usr/local/bin/pi_cli/extensions/meta, and pi rejects re-registration
  // across extensions (unlike override-of-built-ins). Skip them; the
  // widget still tracks them via tool_execution_end, but each call still
  // renders with Meta's upstream renderer. Same applies to anything else
  // a Meta bundled extension claims later.
  const builtins: Array<{ name: string; create: (cwd: string) => any }> = [
    { name: "read", create: createReadTool },
    { name: "bash", create: createBashTool },
    { name: "edit", create: createEditTool },
    { name: "write", create: createWriteTool },
    { name: "ls", create: createLsTool },
  ];

  for (const { name, create } of builtins) {
    const original = create(cwd);
    pi.registerTool({
      name,
      label: name,
      description: original.description,
      parameters: original.parameters,
      async execute(toolCallId: string, params: any, signal: any, onUpdate: any, ctx: any) {
        return original.execute(toolCallId, params, signal, onUpdate, ctx);
      },
      renderShell: "self",
      renderCall: () => EMPTY,
      // Errors are surfaced via the widget (tool_execution_end hook), not
      // inline — testing showed renderResult isn't reliably called for
      // errored tools in our renderShell:"self" setup. Putting the error
      // in the widget is also more consistent: one place for all tool info.
      renderResult: () => EMPTY,
    });
  }

  // (2-3) Per-agent (per user prompt) state. Reset on agent_start, updated
  // on tool_execution_end. Widget persists past agent_end until the next
  // user prompt.
  let counts = new Map<string, Counts>();
  let errorList: Array<{ tool: string; text: string }> = [];
  // In-progress tools (alive between tool_execution_start and
  // tool_execution_end). Keyed by toolCallId so concurrent calls don't
  // stomp each other.
  interface InFlight {
    name: string;
    args: any;
    startedAt: number;     // ms epoch; drives the >30s "live" gate
    preview: string[];     // accumulated tail lines from tool_execution_update
  }
  const inFlight = new Map<string, InFlight>();
  // 2s poll while any tool is in-flight, so the "elapsed > 30s" transition
  // fires even if no new tool_execution_update has landed since.
  let pollTimer: NodeJS.Timeout | null = null;
  let lastCtx: any = null;
  const startPolling = () => {
    if (pollTimer || !lastCtx) return;
    pollTimer = setInterval(() => {
      if (lastCtx) renderWidget(lastCtx);
    }, LIVE_POLL_MS);
  };
  const stopPolling = () => {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  };

  pi.on("agent_start", (_event: any, ctx: any) => {
    counts = new Map();
    errorList = [];
    inFlight.clear();
    stopPolling();
    lastCtx = ctx;
    ctx.ui.setWidget(WIDGET_KEY, undefined);
  });

  pi.on("tool_execution_start", (event: any, ctx: any) => {
    lastCtx = ctx;
    inFlight.set(event.toolCallId, {
      name: event.toolName,
      args: event.args,
      startedAt: Date.now(),
      preview: [],
    });
    startPolling();
    renderWidget(ctx);
  });

  pi.on("tool_execution_update", (event: any, ctx: any) => {
    lastCtx = ctx;
    const entry = inFlight.get(event.toolCallId);
    if (!entry) return;
    const partialText = textOf(event.partialResult);
    if (!partialText) return;
    // Stash a generous tail; renderWidget decides how much to actually show.
    entry.preview = tailLines(partialText, LIVE_MAX_LINES);
    renderWidget(ctx);
  });

  pi.on("tool_execution_end", (event: any, ctx: any) => {
    lastCtx = ctx;
    // Grab inflight entry BEFORE deleting so we can use its args to
    // build the display name (especially for bash → real command name).
    const inflight = inFlight.get(event.toolCallId);
    inFlight.delete(event.toolCallId);
    if (inFlight.size === 0) stopPolling();
    const c = counts.get(event.toolName) ?? { ok: 0, err: 0 };
    if (event.isError) {
      c.err++;
      // TODO: when result.content is empty (e.g. `false` exits 1 with no
      // output, current display is "(no output)"), pull from event.result.details
      // to show exit code, signal, etc. — most tools stash structured failure
      // info in details. For now we display "(no output)" which is technically
      // accurate (no stdout/stderr) but unhelpful.
      const text = textOf(event.result);
      const firstLine = text.split("\n")[0]?.trim().slice(0, 200) ?? "error";
      const name = displayName(event.toolName, inflight?.args);
      errorList.push({ tool: name, text: firstLine || "(no output)" });
    } else {
      c.ok++;
    }
    counts.set(event.toolName, c);
    renderWidget(ctx);
  });

  function renderWidget(ctx: any) {
    const summary = formatSummary(counts);
    const errors = [...errorList];
    const running = Array.from(inFlight.values());
    ctx.ui.setWidget(WIDGET_KEY, (_tui: any, theme: any) => ({
      render: () => {
        const runningSuffix = running.length > 0
          ? `  ${theme.fg("accent", `(${running.length} running)`)}`
          : "";
        const lines = [`${theme.bold("$")} ${summary}${runningSuffix}`];
        // In-progress tools: header line, plus a tail of partial output
        // ONLY after the tool has been running >LIVE_AFTER_MS. Fast
        // commands stay header-only; long-runners graduate to live view.
        const now = Date.now();
        const maxLines = liveLineCap();
        for (const r of running) {
          const name = displayName(r.name, r.args);
          const elapsedMs = now - r.startedAt;
          const isLive = elapsedMs >= LIVE_AFTER_MS;
          const suffix = isLive
            ? ` ${theme.fg("dim", `(${Math.floor(elapsedMs / 1000)}s)`)}`
            : "";
          lines.push(
            `  ${theme.fg("accent", "▶")} ${theme.fg("accent", name)}${suffix}`,
          );
          if (isLive) {
            for (const tail of r.preview.slice(-maxLines)) {
              lines.push(`      ${theme.fg("dim", tail)}`);
            }
          }
        }
        // Errors stack below.
        for (const e of errors) {
          lines.push(
            `  ${theme.fg("error", "✗")} ${theme.fg("error", e.tool)}: ${e.text}`,
          );
        }
        // Truncate every line to the current terminal width — pi-tui's
        // truncateToWidth is ANSI-aware so it won't cut mid-escape. Pi
        // crashes hard ("Rendered line N exceeds terminal width") if any
        // single rendered line overflows, so this is a hard requirement
        // for ANY custom widget.
        const termWidth = process.stdout.columns ?? 80;
        return lines.map((l) => truncateToWidth(l, termWidth, "…"));
      },
      invalidate: () => {},
    }));
  }

  // Note: agent_end doesn't clear the widget. We deliberately leave the
  // last-turn summary visible until the next prompt so the user can glance
  // at "what just happened" after the assistant answers.
}

// --- helpers ---------------------------------------------------------------

function textOf(msgOrResult: any): string {
  if (msgOrResult == null) return "";
  // Some tools (notably bash) stream partials as a plain string or as
  // `{output: "..."}` rather than the canonical content-array shape.
  if (typeof msgOrResult === "string") return msgOrResult;
  if (typeof msgOrResult.output === "string") return msgOrResult.output;
  const content = msgOrResult.content;
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .filter((c: any) => c.type === "text" && c.text)
    .map((c: any) => c.text)
    .join("\n");
}

function tailLines(text: string, n: number): string[] {
  const lines = text.split("\n").map((l) => l.trimEnd()).filter((l) => l.length > 0);
  return lines.slice(-n).map((l) => l.slice(0, 200));
}

// Cap the live-preview line count at min(LIVE_MAX_LINES, terminalRows/3).
// process.stdout.rows is undefined when pi is run without a real TTY
// (rpc/json modes); fall back to LIVE_MAX_LINES so we don't accidentally
// emit zero lines.
function liveLineCap(): number {
  const rows = process.stdout.rows;
  if (!rows || rows <= 0) return LIVE_MAX_LINES;
  return Math.max(1, Math.min(LIVE_MAX_LINES, Math.floor(rows / 3)));
}

// Render a tool as { displayName, suffix }. For `bash`, peel off env-var
// prefixes ("DEBUG=1") and use the actual command word ("brew") as the
// displayed name — `bash brew install foo` is less informative than
// `brew install foo` for at-a-glance scanning. Other tools use a tight
// args summary appropriate to the tool.
// Compute the displayed tool name. For bash, parse the command to show
// the actual command (1 or 2 tokens) instead of literal "bash". For other
// tools, just the tool name — paths and other args are deliberately
// suppressed to keep the widget compact.
function displayName(toolName: string, args: any): string {
  if (toolName === "bash" && args && typeof args === "object") {
    const command = String(args.command ?? "").replace(/\s+/g, " ").trim();
    if (command) {
      const extracted = extractBashCommand(command);
      return extracted ? extracted.displayName : "bash";
    }
  }
  return toolName;
}

// Tokenize a bash command and find the real command word. Skips leading
// env-var assignments (`KEY=value`) and bails on shell metachars (`(`,
// `{`, etc.) where parsing gets too complex to be useful.
//
// For chained commands (`cd foo && make`), takes the LAST segment after
// `&&` / `||` / `;` — that's typically the command the user cares about.
// Pipelines (`|`) are left alone since the producer is usually the
// interesting command. Also skips passthrough wrappers like `cd PATH`,
// `pushd PATH`, `timeout DURATION` whose displayed name would otherwise
// shadow the real command.
//
// Returns the display name (which may be two tokens if the second looks
// like a subcommand: `brew install`, `git status`, `kubectl get`,
// `apt-get install`, …) plus the number of tokens consumed so the
// caller can slice everything else into the suffix.
function extractBashCommand(commandStr: string): { displayName: string; consumed: number } | null {
  // Take the LAST segment of `&&` / `||` / `;` chains. `cd /tmp && ls`
  // → `ls`. Pipelines are deliberately not split here.
  const segments = commandStr.split(/\s*(?:&&|\|\||;)\s*/);
  const lastSegment = segments[segments.length - 1].trim();
  if (!lastSegment) return null;

  const tokens = lastSegment.split(/\s+/).filter((t) => t.length > 0);
  let i = 0;
  // Skip leading env-var assignment prefixes.
  while (i < tokens.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(tokens[i])) i++;
  // Skip passthrough prefixes that take a single positional arg (plus
  // any leading flags): `cd PATH`, `pushd PATH`, `timeout DURATION`.
  // Loop in case of unusual chains like `timeout 30 cd /tmp` (rare).
  const PASSTHROUGH_1ARG = new Set(["cd", "pushd", "timeout"]);
  while (i < tokens.length && PASSTHROUGH_1ARG.has(tokens[i])) {
    i++; // the prefix itself
    while (i < tokens.length && tokens[i].startsWith("-")) i++; // its flags
    i++; // its single positional arg
  }
  if (i >= tokens.length) return null;
  const first = tokens[i];
  // Bail on shell metachars — too complex to parse usefully.
  if (/^[({|&;<>]/.test(first)) return null;

  // Promote the second token into the displayed name if it looks like a
  // subcommand (bare word, no flags/paths/punctuation, ≤20 chars).
  const second = tokens[i + 1];
  if (looksLikeSubcommand(second)) {
    return { displayName: `${first} ${second}`, consumed: i + 2 };
  }
  return { displayName: first, consumed: i + 1 };
}

// "git status", "brew install", "kubectl get" → yes
// "ls /tmp", "make -j32", "python script.py", "cat README.md" → no
function looksLikeSubcommand(token: string | undefined): boolean {
  if (!token) return false;
  if (token.length > 20) return false;
  // Letter-led, only alphanumeric + hyphen + underscore. Excludes
  // anything starting with `-` (flag), `/` (path), `.` (path/file),
  // `~` (home), digits (probably an arg), and anything containing a
  // dot, slash, quote, equals, etc.
  return /^[a-zA-Z][a-zA-Z0-9_-]*$/.test(token);
}


function formatSummary(counts: Map<string, Counts>): string {
  // Stable order: most-used first, ties broken alphabetically.
  const entries = Array.from(counts.entries()).sort((a, b) => {
    const aTotal = a[1].ok + a[1].err;
    const bTotal = b[1].ok + b[1].err;
    if (aTotal !== bTotal) return bTotal - aTotal;
    return a[0].localeCompare(b[0]);
  });
  const okParts: string[] = [];
  let totalErr = 0;
  for (const [name, { ok, err }] of entries) {
    if (ok > 0) okParts.push(`${ok} ${pluralize(name, ok)}`);
    totalErr += err;
  }
  let s = okParts.join(" · ") || "(all errors)";
  if (totalErr > 0) {
    s += `  ·  ${totalErr} error${totalErr === 1 ? "" : "s"}`;
  }
  return s;
}

function pluralize(name: string, n: number): string {
  if (n === 1) return name;
  // Tool names like "ls", "bash", "rg" don't pluralize cleanly. Be lazy:
  // any short opaque command name stays as-is, anything that looks like
  // a verb (read/grep/edit/write/find) gets an "s".
  const opaque = new Set(["bash", "ls", "rg"]);
  if (opaque.has(name)) return name;
  if (name.endsWith("s")) return name;
  return name + "s";
}
