import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// /model-switch — switch the model for THIS session only.
//
// The built-in /model (and Ctrl+P cycling) calls setDefaultModelAndProvider(),
// which persists your choice to settings.json (defaultModel). Since settings
// are synced via dots, that changes your default on every machine.
//
// pi.setModel() is different: it only records a model change on the SESSION
// (session.appendModelChange) and never touches settings.json. So this command
// switches just the current session and leaves your committed default alone.
// Use the built-in /model when you *do* want to change your default.

type ModelLike = { provider: string; id: string; name?: string };

// Captured so getArgumentCompletions() (which gets no ctx) can offer models.
let lastRegistry: { getAvailable?: () => ModelLike[] } | undefined;

function label(m: ModelLike): string {
  return m.name ? `${m.provider}/${m.id}  (${m.name})` : `${m.provider}/${m.id}`;
}

export default function (pi: ExtensionAPI) {
  pi.on("session_start", (_event: any, ctx: any) => {
    lastRegistry = ctx.modelRegistry;
  });

  pi.registerCommand("model-switch", {
    description: "Switch model for THIS session only (does not change your default)",

    getArgumentCompletions: (prefix: string) => {
      const models = lastRegistry?.getAvailable?.() ?? [];
      if (models.length === 0) return null;
      const p = prefix.toLowerCase();
      const items = models
        .map((m) => ({ value: `${m.provider}/${m.id}`, label: label(m) }))
        .filter((i) => i.value.toLowerCase().includes(p) || i.label.toLowerCase().includes(p));
      return items.length > 0 ? items : null;
    },

    handler: async (args: string, ctx: any) => {
      lastRegistry = ctx.modelRegistry; // keep completions fresh after /reload
      const available: ModelLike[] = ctx.modelRegistry?.getAvailable?.() ?? [];
      if (available.length === 0) {
        ctx.ui.notify("No models with configured auth. Run /login first.", "error");
        return;
      }

      const q = (args ?? "").trim();
      let target: ModelLike | undefined;

      if (q) {
        const ql = q.toLowerCase();
        target =
          available.find((m) => `${m.provider}/${m.id}` === q) ??
          available.find((m) => m.id === q) ??
          available.find((m) => `${m.provider}/${m.id}`.toLowerCase().includes(ql)) ??
          available.find((m) => label(m).toLowerCase().includes(ql));
        if (!target) {
          ctx.ui.notify(`No model matching "${q}"`, "error");
          return;
        }
      } else {
        const labels = available.map(label);
        const choice = await ctx.ui.select("Switch model (this session only):", labels);
        if (!choice) return; // cancelled
        target = available[labels.indexOf(choice)];
      }
      if (!target) return;

      const ok = await pi.setModel(target);
      if (ok) {
        ctx.ui.notify(`Session model → ${target.provider}/${target.id} · default unchanged`, "info");
      } else {
        ctx.ui.notify(`No API key for ${target.provider}/${target.id}`, "error");
      }
    },
  });
}
