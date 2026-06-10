import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// /rename — alias for the built-in /name command. Pi's setSessionName is
// exposed via the extension API, so this just delegates.
//
// Usage:
//   /rename foo bar baz   — sets session name to "foo bar baz"
//   /rename               — opens an input prompt
//
// Configurable via env:
//   PI_RENAME_ALIAS_DISABLE=1  — skip registering the alias.

export default function (pi: ExtensionAPI) {
  if (process.env.PI_RENAME_ALIAS_DISABLE === "1") return;

  pi.registerCommand("rename", {
    description: "Rename the current session (alias for /name).",
    handler: async (args: string, ctx: any) => {
      let name = (args ?? "").trim();
      if (!name) {
        const input = await ctx.ui.input(
          "Rename session",
          "New name:",
        );
        if (input == null) return; // cancelled
        name = input.trim();
      }
      if (!name) {
        ctx.ui.notify("Empty name; not renaming.", "warning");
        return;
      }
      pi.setSessionName(name);
      ctx.ui.notify(`Renamed to "${name}"`, "info");
    },
  });
}
