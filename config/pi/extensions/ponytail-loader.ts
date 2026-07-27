import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

// Dynamic, self-guarding loader for the third-party `ponytail` pi extension.
//
// Why a loader instead of a `packages: [...]` entry in settings.json:
//   ponytail is vendored under ~/dotfiles/ponytail (work-synced via dotsync2),
//   NOT in ~/dots. But this file lives in ~/dots (cross-platform: symlinked into
//   ~/.pi/agent/extensions on the devserver, bundled to OD by pack-pi-config).
//   A hard `~/dotfiles/ponytail` package path in settings.json would (a) resolve
//   wrong through the dots symlink on the devserver — pi resolves relative
//   package paths against the settings file, which deref's to ~/dots — and
//   (b) dangle on any box with no ~/dotfiles (e.g. a personal Mac). This loader
//   sidesteps both: it ships everywhere ~/dots goes, but only wires ponytail up
//   where its vendored copy actually exists — absent -> silent no-op. It also
//   replaces the WORK_PI_PACKAGES injection in pack-pi-config.sh: one mechanism,
//   all environments.
//
// Env:
//   PONYTAIL_PI_DISABLE=1   -- skip loading even if ponytail is present.
//   PONYTAIL_PI_DIR=<path>  -- explicit ponytail repo root override.

// First existing candidate wins. The vendored (synced) copy is canonical; the
// raw dev clone is a convenience fallback for local iteration.
const CANDIDATES = ["dotfiles/ponytail", "dev/ponytail"];

export default async function ponytailLoader(pi: ExtensionAPI) {
  if (process.env.PONYTAIL_PI_DISABLE === "1") return;

  const roots = process.env.PONYTAIL_PI_DIR
    ? [process.env.PONYTAIL_PI_DIR]
    : CANDIDATES.map((p) => join(homedir(), p));

  const entry = roots
    .map((r) => join(r, "pi-extension", "index.js"))
    .find((p) => existsSync(p));
  if (!entry) return; // ponytail not installed on this box -> nothing to do.

  const mod = await import(pathToFileURL(entry).href);
  // Hand ponytail the real pi API; its factory registers /ponytail, the
  // /ponytail-* skill aliases, the status bar, and the persona injection hook.
  await mod.default(pi);
}
