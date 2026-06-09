import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  createBashTool,
  createEditTool,
  createLsTool,
  createReadTool,
  createWriteTool,
} from "@earendil-works/pi-coding-agent";

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

  pi.on("agent_start", (_event: any, ctx: any) => {
    counts = new Map();
    errorList = [];
    ctx.ui.setWidget(WIDGET_KEY, undefined);
  });

  pi.on("tool_execution_end", (event: any, ctx: any) => {
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
      errorList.push({ tool: event.toolName, text: firstLine || "(no output)" });
    } else {
      c.ok++;
    }
    counts.set(event.toolName, c);
    renderWidget(ctx);
  });

  function renderWidget(ctx: any) {
    const summary = formatSummary(counts);
    const errors = [...errorList]; // snapshot for closure
    ctx.ui.setWidget(WIDGET_KEY, (_tui: any, theme: any) => ({
      render: () => {
        const lines = [`${theme.bold("$")} ${summary}`];
        for (const e of errors) {
          lines.push(
            `  ${theme.fg("error", "✗")} ${theme.fg("error", e.tool)}: ${e.text}`,
          );
        }
        return lines;
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
  const content = msgOrResult?.content;
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .filter((c: any) => c.type === "text" && c.text)
    .map((c: any) => c.text)
    .join("\n");
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
