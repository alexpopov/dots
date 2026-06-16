import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth } from "@earendil-works/pi-tui";
import { Type } from "typebox";

// Link a Phabricator task (T<num>) or diff (D<num>) to the current chat.
// The linked ID shows in a dedicated row directly below the input editor
// so you don't have to keep it in the session title or remember it
// manually.
//
// Stored as a custom session entry (NOT in LLM context — agents don't
// need to re-read it; the agent already knows what it linked). Restored
// on session_start so it survives /resume.
//
// Two surfaces:
//   link_artifact tool      — agent-invocable. Use when the conversation
//                             is about a specific T/D artifact.
//   /link [id|clear]        — manual: `/link T123`, `/link clear`,
//                             `/link` (shows current)

const WIDGET_KEY = "artifact-link";
const ENTRY_TYPE = "artifact-link";

// Show the link as a dedicated row directly below the input editor.
// Style: dim "link →", followed by the type and bold id.
function showLink(ctx: any, id: string): void {
  const text = formatStatus(id);
  try {
    ctx.ui.setWidget(WIDGET_KEY, (_tui: any, theme: any) => ({
      render: () => {
        const line = `  ${theme.fg("muted", "link")} ${theme.fg("accent", "→")} ${theme.bold(text)}`;
        // Pi crashes if any rendered line exceeds terminal width; truncate
        // defensively even though this line is short by construction.
        return [truncateToWidth(line, process.stdout.columns ?? 80, "…")];
      },
      invalidate: () => {},
    }), { placement: "belowEditor" });
  } catch {}
}

function hideLink(ctx: any): void {
  try { ctx.ui.setWidget(WIDGET_KEY, undefined); } catch {}
}

interface Classified {
  type: "task" | "diff" | "sev" | null;
  valid: boolean;
}

function classifyId(id: string): Classified {
  if (/^T\d+$/.test(id)) return { type: "task", valid: true };
  if (/^D\d+$/.test(id)) return { type: "diff", valid: true };
  if (/^S\d+$/.test(id)) return { type: "sev", valid: true };
  return { type: null, valid: false };
}

function formatStatus(id: string): string {
  const { type } = classifyId(id);
  return type ? `${type}: ${id}` : id;
}

function lastArtifactId(entries: any[]): string | null {
  // Walk entries in reverse; latest wins. Treat null as "unlinked"
  // (so /link clear properly stops restoring the previous link).
  for (let i = entries.length - 1; i >= 0; i--) {
    const e = entries[i];
    if (e?.type === "custom" && e?.customType === ENTRY_TYPE) {
      return e.data?.id ?? null;
    }
  }
  return null;
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "link_artifact",
    label: "Link Artifact",
    description:
      "Link a Phabricator task (T<num>), diff (D<num>), or SEV (S<num>) " +
      "to this chat. Shows the ID on a dedicated row below the editor so " +
      "the user can see at a glance which artifact this conversation is " +
      "about. Re-call to swap to a different artifact.",
    promptSnippet:
      "Link a Phabricator task / diff / SEV to the chat (displays below the editor).",
    promptGuidelines: [
      "Whenever YOU create a new Phabricator task (T<num>), diff (D<num>), or " +
      "SEV (S<num>) — via `meta`, `arc diff`, `jf submit`, or any other path — " +
      "immediately call link_artifact with the newly-created ID. This is what " +
      "stops new artifacts from getting lost in chat history. Don't ask first; " +
      "just link as soon as you know the ID. If you create multiple, link the " +
      "one that's now the primary focus.",
    ],
    parameters: Type.Object({
      id: Type.String({
        description: "The artifact ID, e.g. T273746164 or D273746164. " +
          "Must match T<num>, D<num>, or S<num> exactly (no surrounding text).",
      }),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const id = params.id.trim();
      const cls = classifyId(id);
      if (!cls.valid) {
        return {
          content: [{
            type: "text",
            text: `Invalid artifact ID: "${id}". Expected T<num> (task), D<num> (diff), or S<num> (SEV).`,
          }],
          isError: true,
        };
      }
      pi.appendEntry(ENTRY_TYPE, { id });
      showLink(ctx, id);
      return {
        content: [{ type: "text", text: `Linked ${cls.type} ${id} (displayed below the editor).` }],
      };
    },
  });

  pi.registerTool({
    name: "unlink_artifact",
    label: "Unlink Artifact",
    description:
      "Clear the artifact link from this chat. Use when you linked the " +
      "wrong artifact, or when the current work no longer relates to any " +
      "specific task/diff/SEV. After unlinking, the row below the editor " +
      "disappears.",
    promptSnippet:
      "Clear the currently-linked Phabricator artifact from the chat footer.",
    parameters: Type.Object({}),
    async execute(_toolCallId, _params, _signal, _onUpdate, ctx) {
      pi.appendEntry(ENTRY_TYPE, { id: null });
      hideLink(ctx);
      return { content: [{ type: "text", text: "Artifact link cleared." }] };
    },
  });

  pi.registerCommand("link", {
    description:
      "Link an artifact to this chat. /link T123 or /link D456 sets it; " +
      "/link clear unlinks; /link with no arg shows the current link.",
    handler: async (args: string, ctx: any) => {
      const arg = (args ?? "").trim();

      if (!arg) {
        const entries = ctx.sessionManager.getEntries();
        const latest = lastArtifactId(entries);
        if (latest) {
          ctx.ui.notify(`Current link: ${formatStatus(latest)}`, "info");
        } else {
          ctx.ui.notify("No artifact linked. /link T<num>, /link D<num>, /link S<num>.", "info");
        }
        return;
      }

      if (arg === "clear" || arg === "unlink" || arg === "none") {
        pi.appendEntry(ENTRY_TYPE, { id: null });
        hideLink(ctx);
        ctx.ui.notify("Artifact link cleared.", "info");
        return;
      }

      const cls = classifyId(arg);
      if (!cls.valid) {
        ctx.ui.notify(`Invalid: "${arg}". Expected T<num>, D<num>, or S<num>.`, "warning");
        return;
      }
      pi.appendEntry(ENTRY_TYPE, { id: arg });
      showLink(ctx, arg);
      ctx.ui.notify(`Linked ${cls.type} ${arg}`, "info");
    },
  });

  // Restore the chip on session_start so it persists across /resume,
  // /fork, /new, and full pi restarts.
  pi.on("session_start", (_event: any, ctx: any) => {
    const entries = ctx.sessionManager?.getEntries?.() ?? [];
    const latest = lastArtifactId(entries);
    if (latest) showLink(ctx, latest);
    else hideLink(ctx);
  });

  // Auto-detect: when a tool result contains a clear "this artifact was
  // just created" signal, auto-link the new ID. Belt-and-suspenders for
  // when the LLM forgets to call link_artifact after creating something.
  //
  // Only fires when nothing's currently linked — so the LLM's explicit
  // tool calls always win, and we don't flap as the LLM creates a series
  // of artifacts. If the LLM wants to swap, it can explicitly re-link.
  //
  // Set PI_ARTIFACT_AUTOLINK=0 to disable.
  if (process.env.PI_ARTIFACT_AUTOLINK !== "0") {
    pi.on("tool_execution_end", (event: any, ctx: any) => {
      if (event.isError) return;
      const entries = ctx.sessionManager?.getEntries?.() ?? [];
      if (lastArtifactId(entries) !== null) return; // already linked
      const text = extractResultText(event.result);
      if (!text) return;
      const id = detectCreatedArtifact(text);
      if (!id) return;
      pi.appendEntry(ENTRY_TYPE, { id });
      showLink(ctx, id);
      try { ctx.ui.notify(`Auto-linked ${formatStatus(id)} (detected creation)`, "info"); } catch {}
    });
  }
}

function extractResultText(result: any): string {
  if (!result) return "";
  const content = result.content;
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .filter((c: any) => c.type === "text" && typeof c.text === "string")
    .map((c: any) => c.text)
    .join("\n");
}

// Look for creation-signal patterns in tool output and return the new ID.
// Conservative — only matches when the surrounding text strongly implies
// "this was just created", not e.g. "saw a reference to T123".
function detectCreatedArtifact(text: string): string | null {
  // Patterns roughly in priority order. First match wins.
  const patterns: Array<{ re: RegExp; prefix?: "T" | "D" | "S" }> = [
    // "Created task T123", "Created diff D456", "Created revision D789"
    { re: /\bcreated\s+(?:task|diff|revision|sev)[^\n]{0,80}?\b([TDS]\d{4,})\b/i },
    // "Differential Revision: https://.../D123456"  (jf submit, arc diff)
    { re: /\bdifferential\s+revision[^\n]{0,120}?\b(D\d{4,})\b/i },
    // Plain "https://...D123456" or "https://...?t=123456"
    { re: /https?:\/\/[^\s]*?\/(D\d{4,})\b/ },
    { re: /https?:\/\/[^\s]*\bt=(\d{4,})\b/, prefix: "T" },
    { re: /https?:\/\/[^\s]*?\/(S\d{4,})\b/ },
    // "Task T123 created", "Diff D456 created"
    { re: /\b([TDS]\d{4,})\s+(?:was\s+)?created\b/i },
  ];
  for (const { re, prefix } of patterns) {
    const m = re.exec(text);
    if (!m) continue;
    const raw = m[1];
    if (prefix) return prefix + raw;
    return raw;
  }
  return null;
}
