import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth } from "@earendil-works/pi-tui";
import { Type } from "typebox";

// Link Phabricator tasks (T<num>), diffs (D<num>), and SEVs (S<num>) to the
// current chat. Linked IDs show in a dedicated row directly below the input
// editor so you don't have to keep them in the session title or remember
// them manually.
//
// MULTIPLE artifacts can be linked at once — e.g. a task AND its diff. Each
// link_artifact / `/link` call ADDS to the set (it does not replace). Remove
// one with unlink_artifact({id}) / `/link remove <id>`, or clear all with
// unlink_artifact() / `/link clear`.
//
// Stored as a custom session entry (NOT in LLM context — the agent already
// knows what it linked). Each mutation writes a full snapshot of the id list;
// the latest snapshot wins. Restored on session_start so it survives /resume.
//
// Two surfaces:
//   link_artifact / unlink_artifact tools — agent-invocable.
//   /link [<id>... | remove <id>... | clear] — manual.

const WIDGET_KEY = "artifact-link";
const ENTRY_TYPE = "artifact-link";

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

function dedupe(ids: string[]): string[] {
  return [...new Set(ids)];
}

// Walk entries in reverse; the latest snapshot wins. Normalizes legacy
// single-id entries ({id} / {id:null}) written before multi-link support.
function currentIds(entries: any[]): string[] {
  for (let i = entries.length - 1; i >= 0; i--) {
    const e = entries[i];
    if (e?.type === "custom" && e?.customType === ENTRY_TYPE) {
      const d = e.data ?? {};
      if (Array.isArray(d.ids)) return dedupe(d.ids.filter((x: any) => typeof x === "string"));
      return d.id ? [d.id] : []; // legacy
    }
  }
  return [];
}

// Render all linked artifacts on one row below the editor:
//   link  → task: T123
//   links → task: T123 · diff: D456
// Empty list hides the row.
function renderLinks(ctx: any, ids: string[]): void {
  if (ids.length === 0) {
    try { ctx.ui.setWidget(WIDGET_KEY, undefined); } catch {}
    return;
  }
  try {
    ctx.ui.setWidget(WIDGET_KEY, (_tui: any, theme: any) => ({
      render: () => {
        const label = ids.length === 1 ? "link" : "links";
        const body = ids.map((id) => theme.bold(formatStatus(id))).join(theme.fg("muted", " · "));
        const line = `  ${theme.fg("muted", label)} ${theme.fg("accent", "→")} ${body}`;
        // Pi crashes if any rendered line exceeds terminal width; truncate
        // defensively (the list can grow when several artifacts are linked).
        return [truncateToWidth(line, process.stdout.columns ?? 80, "…")];
      },
      invalidate: () => {},
    }), { placement: "belowEditor" });
  } catch {}
}

function summarize(ids: string[]): string {
  return ids.length ? ids.map(formatStatus).join(" · ") : "(none)";
}

export default function (pi: ExtensionAPI) {
  // Persist the new id set AND repaint the row. All mutations go through here.
  const commit = (ctx: any, ids: string[]): string[] => {
    const next = dedupe(ids);
    pi.appendEntry(ENTRY_TYPE, { ids: next });
    renderLinks(ctx, next);
    return next;
  };

  pi.registerTool({
    name: "link_artifact",
    label: "Link Artifact",
    description:
      "Link a Phabricator task (T<num>), diff (D<num>), or SEV (S<num>) to " +
      "this chat. Shows it on a dedicated row below the editor so the user " +
      "can see at a glance which artifacts this conversation is about.\n\n" +
      "ADDITIVE: multiple artifacts can be linked at once (e.g. a task and " +
      "its diff). Each call adds one ID; it does NOT replace existing links. " +
      "Use unlink_artifact to remove one or clear them.",
    promptSnippet:
      "Link a Phabricator task / diff / SEV to the chat (additive; shows below the editor).",
    promptGuidelines: [
      "Whenever YOU create a new Phabricator task (T<num>), diff (D<num>), or " +
      "SEV (S<num>) — via `meta`, `arc diff`, `jf submit`, or any other path — " +
      "immediately call link_artifact with the newly-created ID. This is what " +
      "stops new artifacts from getting lost in chat history. Don't ask first; " +
      "just link as soon as you know the ID. Linking is additive, so if you " +
      "create several (e.g. a task and its diff), link each one — they all " +
      "stay shown.",
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
      const ids = currentIds(ctx.sessionManager.getEntries());
      if (ids.includes(id)) {
        return { content: [{ type: "text", text: `${cls.type} ${id} is already linked. Linked: ${summarize(ids)}.` }] };
      }
      const next = commit(ctx, [...ids, id]);
      return { content: [{ type: "text", text: `Linked ${cls.type} ${id}. Linked: ${summarize(next)}.` }] };
    },
  });

  pi.registerTool({
    name: "unlink_artifact",
    label: "Unlink Artifact",
    description:
      "Remove a linked artifact. Pass an `id` to remove just that one " +
      "(the others stay linked); call with no arguments to clear ALL links. " +
      "Use when you linked the wrong artifact or the work no longer relates " +
      "to it.",
    promptSnippet:
      "Remove one linked Phabricator artifact (by id) or clear all.",
    parameters: Type.Object({
      id: Type.Optional(Type.String({
        description: "Artifact ID to remove (T/D/S<num>). Omit to clear all links.",
      })),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const ids = currentIds(ctx.sessionManager.getEntries());
      const id = params.id?.trim();
      if (id) {
        if (!ids.includes(id)) {
          return { content: [{ type: "text", text: `${id} isn't linked. Linked: ${summarize(ids)}.` }] };
        }
        const next = commit(ctx, ids.filter((x) => x !== id));
        return { content: [{ type: "text", text: `Unlinked ${id}. Linked: ${summarize(next)}.` }] };
      }
      commit(ctx, []);
      return { content: [{ type: "text", text: "Cleared all artifact links." }] };
    },
  });

  pi.registerCommand("link", {
    description:
      "Link artifacts to this chat (additive). /link T123 D456 adds; " +
      "/link remove T123 removes one; /link clear removes all; /link shows current.",
    handler: async (args: string, ctx: any) => {
      const arg = (args ?? "").trim();
      const ids = currentIds(ctx.sessionManager.getEntries());

      if (!arg) {
        ctx.ui.notify(
          ids.length ? `Linked: ${summarize(ids)}` : "No artifacts linked. /link T<num> D<num> S<num> to add.",
          "info",
        );
        return;
      }

      const tokens = arg.split(/\s+/);
      const head = tokens[0].toLowerCase();

      if (head === "clear" || head === "none") {
        const rest = tokens.slice(1);
        if (rest.length === 0) {
          commit(ctx, []);
          ctx.ui.notify("Cleared all artifact links.", "info");
          return;
        }
        const next = commit(ctx, ids.filter((x) => !rest.includes(x)));
        ctx.ui.notify(`Removed ${rest.join(", ")}. Linked: ${summarize(next)}.`, "info");
        return;
      }

      if (head === "remove" || head === "unlink") {
        const rest = tokens.slice(1);
        if (rest.length === 0) {
          ctx.ui.notify("Usage: /link remove <id>... (or /link clear to remove all).", "warning");
          return;
        }
        const next = commit(ctx, ids.filter((x) => !rest.includes(x)));
        ctx.ui.notify(`Removed ${rest.join(", ")}. Linked: ${summarize(next)}.`, "info");
        return;
      }

      // Otherwise: treat every token as an id to add.
      const valid: string[] = [];
      const invalid: string[] = [];
      for (const t of tokens) (classifyId(t).valid ? valid : invalid).push(t);
      if (valid.length === 0) {
        ctx.ui.notify(`Invalid: "${arg}". Expected T<num>, D<num>, or S<num>.`, "warning");
        return;
      }
      const next = commit(ctx, [...ids, ...valid]);
      const note = invalid.length ? ` (ignored: ${invalid.join(", ")})` : "";
      ctx.ui.notify(`Linked ${valid.join(", ")}${note}. Linked: ${summarize(next)}.`, "info");
    },
  });

  // Restore the row on session_start so it persists across /resume, /fork,
  // /new, and full pi restarts.
  pi.on("session_start", (_event: any, ctx: any) => {
    const entries = ctx.sessionManager?.getEntries?.() ?? [];
    renderLinks(ctx, currentIds(entries));
  });

  // Auto-detect: when a tool result looks like an artifact was just CREATED
  // (not merely referenced), add it to the linked set. Belt-and-suspenders
  // for when the LLM forgets to call link_artifact. Additive — a created
  // task then a created diff both get picked up.
  //
  // Gated on a creation/submit signal in the text so browsing or describing
  // existing artifacts (which also print T/D URLs) does NOT auto-link them.
  // Set PI_ARTIFACT_AUTOLINK=0 to disable.
  if (process.env.PI_ARTIFACT_AUTOLINK !== "0") {
    pi.on("tool_execution_end", (event: any, ctx: any) => {
      if (event.isError) return;
      const text = extractResultText(event.result);
      if (!text) return;
      if (!/\bcreat(?:e|ed|ing)\b/i.test(text) && !/\bdifferential\s+revision\b/i.test(text)) return;
      const id = detectCreatedArtifact(text);
      if (!id) return;
      const ids = currentIds(ctx.sessionManager?.getEntries?.() ?? []);
      if (ids.includes(id)) return;
      const next = commit(ctx, [...ids, id]);
      try { ctx.ui.notify(`Auto-linked ${formatStatus(id)} (detected creation). Linked: ${summarize(next)}.`, "info"); } catch {}
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
