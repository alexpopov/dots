import { DynamicBorder, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Container, type SelectItem, SelectList, Text, truncateToWidth } from "@earendil-works/pi-tui";
import { existsSync, mkdirSync, readFileSync, renameSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join, resolve as pathResolve } from "node:path";
import { randomUUID } from "node:crypto";

// projects — bind a pi session to a named project + knowledge-base directory.
//
// What you get when a project is active:
//   • Footer status `project: <name>`.
//   • Banner row above editor (cleared after first prompt).
//   • System-prompt addendum on every before_agent_start that names the
//     project, points the agent at the KB path, and pins the contents of
//     `<kb>/PROJECT.md` so the agent re-reads the primer on every turn
//     (survives compaction).
//
// State:
//   • Registry JSON at ~/.pi-projects/projects.json (atomic write).
//   • Per-session binding via a custom session entry, so /resume restores
//     the active project without consulting the registry first.
//
// Commands:
//   /projects                 → picker (or /projects switch)
//   /projects new             → wizard (name, optional kbPath, seed PROJECT.md)
//   /projects switch [name]   → switch by name; opens picker if no name
//   /projects info            → print active project
//   /projects list            → print all projects
//   /projects edit-entrypoint → open PROJECT.md in $EDITOR
//   /projects kb              → print KB path
//
// Trimmed port of Ivan Gromov's design at
// fbsource/users/iv/ivangromov/projects/DESIGN.md. v1 deliberately skips:
//   • closed/reopen lifecycle
//   • per-project session list and auto-association
//   • settings.json overrides for registry / kb paths (uses fixed defaults)
//   • /projects edit, /projects delete, /projects reload-entrypoint
// Add these back if the simple version feels limiting.

const REGISTRY_PATH = join(homedir(), ".pi-projects", "projects.json");
const KB_ROOT = join(homedir(), ".pi-projects", "kb");
const ENTRYPOINT_FILENAME = "PROJECT.md";
const BINDING_TYPE = "projects-binding";
const BANNER_KEY = "projects-banner";
const STATUS_KEY = "projects";

interface Project {
  id: string;
  name: string;
  description: string;
  kbPath: string;
  createdAt: string;
  updatedAt: string;
}

interface Registry {
  version: 1;
  projects: Project[];
}

interface BindingData {
  projectId: string;
  projectName: string;
}

function emptyRegistry(): Registry {
  return { version: 1, projects: [] };
}

function loadRegistry(): Registry {
  if (!existsSync(REGISTRY_PATH)) return emptyRegistry();
  try {
    const parsed = JSON.parse(readFileSync(REGISTRY_PATH, "utf-8"));
    if (parsed?.version !== 1 || !Array.isArray(parsed.projects)) return emptyRegistry();
    return parsed as Registry;
  } catch {
    return emptyRegistry();
  }
}

function saveRegistry(reg: Registry): void {
  try {
    mkdirSync(dirname(REGISTRY_PATH), { recursive: true });
    const tmp = `${REGISTRY_PATH}.tmp`;
    writeFileSync(tmp, `${JSON.stringify(reg, null, 2)}\n`, "utf-8");
    renameSync(tmp, REGISTRY_PATH);
  } catch (err) {
    process.stderr.write(`[projects] failed to write registry: ${String(err)}\n`);
  }
}

function nowIso(): string {
  // Use mtime-style stamp so the registry is meaningful even though it's
  // editable by hand.
  try {
    return new Date().toISOString();
  } catch {
    return "";
  }
}

function slugify(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "")
    .slice(0, 60) || "project";
}

function entrypointPath(p: Project): string {
  return join(p.kbPath, ENTRYPOINT_FILENAME);
}

function readEntrypoint(p: Project): { exists: boolean; body: string; absPath: string } {
  const abs = entrypointPath(p);
  try {
    return { exists: true, body: readFileSync(abs, "utf-8"), absPath: abs };
  } catch {
    return { exists: false, body: "", absPath: abs };
  }
}

function defaultEntrypoint(name: string, description: string): string {
  return [
    `# ${name}`,
    "",
    description || "_(no description)_",
    "",
    "## Conventions",
    "",
    "_Project-specific rules the agent should follow (style, dependencies,",
    "files to never touch, etc.)._",
    "",
    "## Current focus",
    "",
    "_What you're working on right now. Update freely — the agent re-reads",
    "this on every turn._",
    "",
    "## TODO",
    "",
    "- [ ] ",
    "",
  ].join("\n");
}

export default function (pi: ExtensionAPI) {
  // Per-session mutable state held in closure. Loaded on session_start.
  let registry: Registry = emptyRegistry();
  let activeProjectId: string | null = null;

  const findById = (id: string): Project | undefined => registry.projects.find((p) => p.id === id);
  const findByName = (name: string): Project | undefined =>
    registry.projects.find((p) => p.name.toLowerCase() === name.toLowerCase());
  const getActive = (): Project | undefined => (activeProjectId ? findById(activeProjectId) : undefined);

  // Walk the current branch oldest → newest; last projects-binding wins.
  // Empty projectId is the "deactivated" sentinel so unbind survives /resume.
  function rebindFromBranch(ctx: any): void {
    const branch = ctx.sessionManager?.getBranch?.() ?? [];
    let latest: BindingData | null = null;
    for (const entry of branch) {
      const e = entry as { type?: string; customType?: string; data?: any };
      if (e.type === "custom" && e.customType === BINDING_TYPE && e.data) {
        latest = e.data as BindingData;
      }
    }
    if (!latest || latest.projectId === "") {
      activeProjectId = null;
      return;
    }
    const p = findById(latest.projectId);
    if (!p) {
      activeProjectId = null;
      try {
        ctx.ui.notify(
          `[projects] session was bound to '${latest.projectName}' (id ${latest.projectId}); not in registry`,
          "warning",
        );
      } catch {}
      return;
    }
    activeProjectId = p.id;
  }

  function refreshUi(ctx: any): void {
    const p = getActive();
    try {
      if (p) {
        ctx.ui.setStatus(STATUS_KEY, `project: ${p.name}`);
        ctx.ui.setWidget(BANNER_KEY, (_tui: any, theme: any) => ({
          render: () => {
            const cols = process.stdout.columns ?? 80;
            const left = `  ${theme.fg("muted", "project")} ${theme.fg("accent", "→")} ${theme.bold(p.name)}`;
            const right = p.kbPath ? `  ${theme.fg("dim", p.kbPath)}` : "";
            return [truncateToWidth(left + right, cols, "…")];
          },
          invalidate: () => {},
        }), { placement: "belowEditor" });
      } else {
        ctx.ui.setStatus(STATUS_KEY, undefined);
        ctx.ui.setWidget(BANNER_KEY, undefined);
      }
    } catch {}
  }

  function activate(ctx: any, project: Project): void {
    activeProjectId = project.id;
    pi.appendEntry(BINDING_TYPE, {
      projectId: project.id,
      projectName: project.name,
    });
    refreshUi(ctx);
    // Inject a visible custom message marking the entrypoint load. Renderer
    // is registered below — it shows a compact header on collapse.
    const ep = readEntrypoint(project);
    if (ep.exists) {
      pi.sendMessage({
        customType: "projects-entrypoint",
        content: ep.body,
        display: true,
        details: {
          projectName: project.name,
          entrypointPath: ep.absPath,
          lines: ep.body.split("\n").length,
        },
      });
    } else {
      ctx.ui.notify(
        `[projects] active: ${project.name}. PROJECT.md missing at ${ep.absPath} — /projects edit-entrypoint to create it.`,
        "warning",
      );
    }
  }

  function deactivate(ctx: any): void {
    pi.appendEntry(BINDING_TYPE, { projectId: "", projectName: "" });
    activeProjectId = null;
    refreshUi(ctx);
  }

  // Build the system-prompt addendum. Returns "" when no project is active
  // or the project has no useful content — caller checks for empty.
  function buildAddendum(): string {
    const p = getActive();
    if (!p) return "";
    const lines: string[] = [];
    lines.push(`## Active project: ${p.name}`);
    if (p.description) {
      lines.push("");
      lines.push(p.description);
    }
    lines.push("");
    lines.push(`Knowledge base: ${p.kbPath}`);
    lines.push("- Markdown notes and python/shell scripts live in this directory.");
    lines.push("- You may `read`, `grep`, `find`, and `ls` inside it on demand.");
    lines.push("- Treat it as authoritative project context. Do not modify");
    lines.push("  files there unless the user explicitly asks.");
    const ep = readEntrypoint(p);
    if (ep.exists) {
      lines.push("");
      lines.push(`### Project entrypoint (${ENTRYPOINT_FILENAME})`);
      lines.push("");
      lines.push(ep.body.trimEnd());
    } else {
      lines.push("");
      lines.push(`Project entrypoint: ${ep.absPath} (missing)`);
    }
    return lines.join("\n");
  }

  // ----- event hooks -------------------------------------------------------

  pi.on("session_start", (_event: any, ctx: any) => {
    registry = loadRegistry();
    rebindFromBranch(ctx);
    refreshUi(ctx);
  });

  pi.on("session_tree", (_event: any, ctx: any) => {
    rebindFromBranch(ctx);
    refreshUi(ctx);
  });

  pi.on("session_shutdown", (_event: any, ctx: any) => {
    try {
      ctx.ui.setStatus(STATUS_KEY, undefined);
      ctx.ui.setWidget(BANNER_KEY, undefined);
    } catch {}
  });

  pi.on("before_agent_start", (event: any, _ctx: any) => {
    const add = buildAddendum();
    if (!add) return;
    return { systemPrompt: `${event.systemPrompt}\n\n${add}` };
  });

  // Compact renderer for the entrypoint-load custom message. Collapsed view
  // shows just a one-line header; expanded view shows the full file body.
  pi.registerMessageRenderer("projects-entrypoint", (message: any, opts: any, theme: any) => {
    const d = (message.details ?? {}) as { projectName?: string; entrypointPath?: string; lines?: number };
    const header =
      theme.fg("accent", `📖 ${ENTRYPOINT_FILENAME}`) +
      ` loaded for ${theme.fg("accent", d.projectName ?? "?")} ` +
      theme.fg("dim", `· ${d.lines ?? 0} lines`);
    if (!opts?.expanded) return new Text(header, 0, 0);
    const body =
      typeof message.content === "string"
        ? message.content
        : Array.isArray(message.content)
          ? message.content.filter((c: any) => c?.type === "text").map((c: any) => c.text).join("")
          : "";
    return new Text(`${header}\n${theme.fg("dim", "---")}\n${body}`, 0, 0);
  });

  // ----- /projects command -------------------------------------------------

  pi.registerCommand("projects", {
    description:
      "Manage projects. `/projects` opens the picker; `/projects new` creates one; " +
      "`/projects switch <name>` jumps; `/projects info` describes the active one.",
    getArgumentCompletions: (prefix: string) => {
      const subs = [
        { value: "new", label: "new", description: "Create a project (wizard)" },
        { value: "switch", label: "switch", description: "Switch by name (picker if no name)" },
        { value: "info", label: "info", description: "Show active project" },
        { value: "list", label: "list", description: "List all projects" },
        { value: "kb", label: "kb", description: "Print KB path" },
        { value: "edit-entrypoint", label: "edit-entrypoint", description: "Edit PROJECT.md" },
      ];
      const m = prefix.match(/^(switch)\s+(.*)$/);
      if (m) {
        const partial = (m[2] ?? "").toLowerCase();
        return registry.projects
          .filter((p) => p.name.toLowerCase().startsWith(partial))
          .map((p) => ({ value: `switch ${p.name}`, label: p.name, description: p.description || "" }));
      }
      const filtered = subs.filter((s) => s.value.startsWith(prefix.toLowerCase()));
      return filtered.length > 0 ? filtered : null;
    },
    handler: async (rawArgs: string, ctx: any) => {
      const args = (rawArgs ?? "").trim();
      if (!args) return doSwitch(ctx, null);
      const space = args.indexOf(" ");
      const sub = (space >= 0 ? args.slice(0, space) : args).toLowerCase();
      const rest = space >= 0 ? args.slice(space + 1).trim() : "";
      switch (sub) {
        case "new": return doNew(ctx);
        case "switch": return doSwitch(ctx, rest || null);
        case "info": return doInfo(ctx);
        case "list": return doList(ctx);
        case "kb": return doKb(ctx);
        case "edit-entrypoint":
        case "edit-ep": return doEditEntrypoint(ctx);
        default:
          ctx.ui.notify(
            `[projects] unknown sub-command '${sub}'. Try: new, switch, info, list, kb, edit-entrypoint`,
            "error",
          );
      }
    },
  });

  // ----- sub-action handlers -----------------------------------------------

  async function doNew(ctx: any): Promise<void> {
    const name = (await ctx.ui.input("Project name:", "e.g. Auth refactor"))?.trim();
    if (!name) {
      ctx.ui.notify("[projects] aborted: empty name", "info");
      return;
    }
    if (findByName(name)) {
      ctx.ui.notify(`[projects] '${name}' already exists`, "error");
      return;
    }
    const description = ((await ctx.ui.input("Description (optional):", "one line, can be empty")) ?? "").trim();
    const defaultKb = join(KB_ROOT, slugify(name));
    const kbInput = (await ctx.ui.input(`KB path (blank = ${defaultKb}):`, defaultKb))?.trim();
    const kbPath = pathResolve(expandHome(kbInput || defaultKb));
    if (!existsSync(kbPath)) {
      const create = await ctx.ui.confirm("Create KB directory?", `${kbPath} does not exist.`);
      if (create) {
        try { mkdirSync(kbPath, { recursive: true }); }
        catch (err) {
          ctx.ui.notify(`[projects] failed to create ${kbPath}: ${String(err)}`, "error");
          return;
        }
      }
    }
    const ep = join(kbPath, ENTRYPOINT_FILENAME);
    if (!existsSync(ep) && existsSync(kbPath)) {
      const seed = await ctx.ui.confirm(`Seed ${ENTRYPOINT_FILENAME}?`, `Write a starter template to ${ep}.`);
      if (seed) {
        try { writeFileSync(ep, defaultEntrypoint(name, description), "utf-8"); }
        catch (err) { ctx.ui.notify(`[projects] failed to seed ${ep}: ${String(err)}`, "warning"); }
      }
    }
    const project: Project = {
      id: randomUUID(),
      name,
      description,
      kbPath,
      createdAt: nowIso(),
      updatedAt: nowIso(),
    };
    registry.projects.push(project);
    saveRegistry(registry);
    activate(ctx, project);
    ctx.ui.notify(`[projects] created '${name}' and made it active.`, "info");
  }

  async function doSwitch(ctx: any, name: string | null): Promise<void> {
    if (name) {
      if (name === "none" || name === "(none)") {
        deactivate(ctx);
        ctx.ui.notify("[projects] cleared active project.", "info");
        return;
      }
      const p = findByName(name);
      if (!p) {
        ctx.ui.notify(`[projects] no project named '${name}'. Try /projects list.`, "error");
        return;
      }
      activate(ctx, p);
      return;
    }
    if (registry.projects.length === 0) {
      ctx.ui.notify("[projects] no projects yet. Run /projects new.", "info");
      return;
    }
    const choice = await showPicker(ctx);
    if (!choice) return;
    if (choice === "__none__") {
      deactivate(ctx);
      ctx.ui.notify("[projects] cleared active project.", "info");
      return;
    }
    if (choice === "__new__") return doNew(ctx);
    const p = findById(choice);
    if (p) activate(ctx, p);
  }

  function doInfo(ctx: any): void {
    const p = getActive();
    if (!p) {
      ctx.ui.notify("[projects] no project active. /projects to pick one.", "info");
      return;
    }
    const ep = readEntrypoint(p);
    const lines = [
      `project: ${p.name}`,
      p.description ? `  ${p.description}` : "  (no description)",
      `  kb       : ${p.kbPath}`,
      `  entrypoint: ${ep.absPath} ${ep.exists ? `(${ep.body.split("\n").length} lines)` : "(missing)"}`,
      `  created  : ${p.createdAt}`,
    ];
    ctx.ui.notify(lines.join("\n"), "info");
  }

  function doList(ctx: any): void {
    if (registry.projects.length === 0) {
      ctx.ui.notify("[projects] (empty). Run /projects new.", "info");
      return;
    }
    const lines = ["projects:"];
    for (const p of registry.projects) {
      const mark = p.id === activeProjectId ? "*" : " ";
      lines.push(`  ${mark} ${p.name.padEnd(24)} ${p.description || ""}`);
    }
    ctx.ui.notify(lines.join("\n"), "info");
  }

  function doKb(ctx: any): void {
    const p = getActive();
    if (!p) {
      ctx.ui.notify("[projects] no project active.", "info");
      return;
    }
    ctx.ui.notify(`kb path: ${p.kbPath}`, "info");
  }

  async function doEditEntrypoint(ctx: any): Promise<void> {
    const p = getActive();
    if (!p) {
      ctx.ui.notify("[projects] no project active. /projects to pick one.", "info");
      return;
    }
    const ep = readEntrypoint(p);
    const prefill = ep.exists ? ep.body : defaultEntrypoint(p.name, p.description);
    const edited = await ctx.ui.editor(`Edit ${ENTRYPOINT_FILENAME} for ${p.name}`, prefill);
    if (edited == null) return;
    try {
      mkdirSync(dirname(ep.absPath), { recursive: true });
      writeFileSync(ep.absPath, edited, "utf-8");
      ctx.ui.notify(`[projects] saved ${ep.absPath}`, "info");
    } catch (err) {
      ctx.ui.notify(`[projects] failed to save ${ep.absPath}: ${String(err)}`, "error");
    }
  }

  async function showPicker(ctx: any): Promise<string | null> {
    return ctx.ui.custom<string | null>(
      (tui: any, theme: any, _kb: any, done: (v: string | null) => void) => {
        const items: SelectItem[] = [];
        items.push({ value: "__none__", label: "(none)", description: "Clear active project" });
        items.push({ value: "__new__", label: "+ new project…", description: "Run the new-project wizard" });
        for (const p of [...registry.projects].sort((a, b) => a.name.localeCompare(b.name))) {
          const active = p.id === activeProjectId;
          items.push({
            value: p.id,
            label: active ? `${p.name} (active)` : p.name,
            description: describeRow(p),
          });
        }
        const container = new Container();
        container.addChild(new DynamicBorder((s: string) => theme.fg("accent", s)));
        container.addChild(new Text(theme.fg("accent", theme.bold("Select project")), 1, 0));
        const visibleCount = Math.min(items.length, 15);
        const select = new SelectList(items, visibleCount, {
          selectedPrefix: (t: string) => theme.fg("accent", t),
          selectedText: (t: string) => theme.fg("accent", t),
          description: (t: string) => theme.fg("muted", t),
          scrollInfo: (t: string) => theme.fg("dim", t),
          noMatch: (t: string) => theme.fg("warning", t),
        });
        select.onSelect = (item: SelectItem) => done(item.value);
        select.onCancel = () => done(null);
        container.addChild(select);
        container.addChild(new Text(
          theme.fg("dim", "↑↓ or jk navigate • enter select • esc cancel"),
          1, 0,
        ));
        container.addChild(new DynamicBorder((s: string) => theme.fg("accent", s)));
        return {
          render: (w: number) => container.render(w),
          invalidate: () => container.invalidate(),
          handleInput: (data: string) => {
            // hjkl ↔ arrows, same convention as find-session / fork-to-tmux
            if (data === "j") data = "\x1b[B";
            else if (data === "k") data = "\x1b[A";
            select.handleInput(data);
            tui.requestRender();
          },
        };
      },
    );
  }

  function describeRow(p: Project): string {
    const ep = readEntrypoint(p);
    const epNote = ep.exists ? `${ENTRYPOINT_FILENAME}` : `${ENTRYPOINT_FILENAME} missing`;
    const desc = p.description ? p.description + " · " : "";
    return `${desc}${epNote}`;
  }
}

function expandHome(p: string): string {
  if (p === "~") return homedir();
  if (p.startsWith("~/")) return join(homedir(), p.slice(2));
  return p;
}

// Reserved for future "last touched" sort; not used by /projects list yet.
// Kept as a private helper so the import is clean if v2 adds sort-by-mtime.
function _projectMtime(p: Project): number {
  try { return statSync(p.kbPath).mtimeMs; } catch { return 0; }
}
void _projectMtime; void basename;
