/**
 * mcp-bridge — give pi first-class MCP support with ZERO change to how you launch pi.
 *
 * Why this exists: pi's core intentionally ships no built-in MCP ("install it as an
 * extension"). This IS that extension. Because it lives in an auto-discovered
 * extensions dir (~/.pi/agent/extensions or ~/dots/config/pi/extensions), it loads on
 * every plain `pi` — no flags, no wrapper, no changed invocation.
 *
 * What it does: it's an MCP *client* embedded in pi. For a stdio MCP server it spawns
 * the server as a child process, holds the pipe open for the WHOLE pi session, and
 * registers each MCP tool as a native pi tool. Because the one connection stays alive,
 * stateful servers work correctly: e.g. aosp-build-server's `setup_environment` state
 * survives across later `trigger_build` / `get_build_result` calls in the same chat.
 *
 * Config: reads `mcpServers` from ~/.claude.json (the same place Claude Code keeps them —
 * one source of truth for both). Optional ~/.pi/agent/mcp.json can add/override servers,
 * set an `autoConnect` list, and mark servers `agentConnect: true` (allowlist — see below).
 * Server shape (stdio): { command, args?, env?, agentConnect?, hint? }.
 *
 * Usage in chat (human):
 *   /mcp list                  — list configured servers
 *   /mcp connect <name>        — spawn + register a server's tools (persists for the session)
 *   /mcp connect all           — connect every configured server
 *   /mcp status                — show connected servers + tool counts
 *   /mcp disconnect <name>     — kill a server process
 * Tools then appear as `<server>__<tool>` and the model can call them immediately.
 *
 * Agent-driven (lazy, allowlisted): the `mcp_connect` TOOL lets the model itself load a
 * server on demand — but ONLY servers marked `"agentConnect": true` in ~/.pi/agent/mcp.json.
 * This keeps startup fast (nothing spawned until needed) while bounding what the agent can
 * launch. The tool's description lists the allowlisted servers + their `hint`, so the model
 * knows when to reach for them (e.g. EyePatch topic/migration tools).
 *
 * Heavy servers (aosp-build-server, message-passing run `buck2 run …`) can take minutes
 * to spawn the first time, so by default NOTHING auto-connects (fast startup, no breakage
 * from a bad server). Put fast servers in mcp.json `autoConnect` for always-on behavior.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { spawn, type ChildProcess } from "node:child_process";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// Empty render component: suppress all inline TUI output for MCP tool calls
// (humans don't care about raw MCP I/O). The tool-aggregator widget still counts
// every call and surfaces errors via tool_execution_end, like the built-in tools.
const EMPTY_RENDER = { render: () => [], invalidate: () => {} };

interface ServerCfg {
  command: string;
  args?: string[];
  env?: Record<string, string>;
  type?: string; // only "stdio" supported here
  // Allowlist flag: when true, the AGENT may connect this server itself via the
  // `mcp_connect` tool (not just the human via /mcp connect). Off by default so a
  // server is never agent-spawnable unless explicitly blessed.
  agentConnect?: boolean;
  // When true, this server is auto-connected in SUBAGENT children (PI_AGENT_TEAM_CHILD=1)
  // so a fresh subagent comes up with it already available -- e.g. the indexed code-search
  // servers, so subagent-search-guard can block grep and redirect here. Declarative: tag a
  // server once in mcp.json and every subagent gets it, no extension edit per tool.
  subagentConnect?: boolean;
  // One-line summary of what this server's tools are for; shown to the model in the
  // mcp_connect tool description so it knows when to load them.
  hint?: string;
  // Working directory for the server process. Defaults to pi's cwd.
  // This matters for the Meta mux server: its search_files is configured with
  // `use_cwd_as_target_directory` / `use_cwd_relative_paths`, so the repo it searches is
  // decided by the SERVER's cwd. Pinning it here lets one pi session hold several search
  // roots at once (e.g. an A14 and an A16 checkout) regardless of where pi was started.
  cwd?: string;
}

interface BridgeConfig {
  servers: Record<string, ServerCfg>;
  autoConnect: string[];
  subagentConnect: string[];
}

function loadConfig(): BridgeConfig {
  const servers: Record<string, ServerCfg> = {};
  let autoConnect: string[] = [];
  // 1) Claude config — shared source of truth.
  try {
    const c = JSON.parse(readFileSync(join(homedir(), ".claude.json"), "utf8"));
    if (c?.mcpServers) Object.assign(servers, c.mcpServers);
  } catch {
    /* no claude config — fine */
  }
  // 2) pi-specific override / autoConnect list.
  try {
    const p = JSON.parse(readFileSync(join(homedir(), ".pi/agent/mcp.json"), "utf8"));
    if (p?.mcpServers) Object.assign(servers, p.mcpServers);
    if (Array.isArray(p?.autoConnect)) autoConnect = p.autoConnect;
  } catch {
    /* no override — fine */
  }
  // Per-server, declarative: servers tagged `subagentConnect: true` are auto-connected
  // in subagent children. Add a new search tool to mcp.json with this flag and every
  // subagent gets it -- nothing in the extensions needs to change.
  const subagentConnect = Object.entries(servers).filter(([, c]) => c.subagentConnect).map(([n]) => n);
  return { servers, autoConnect, subagentConnect };
}

/** Minimal MCP stdio client: JSON-RPC 2.0, newline-delimited. Validated against real servers. */
class McpClient {
  private proc: ChildProcess | null = null;
  private buf = "";
  private nextId = 1;
  private pending = new Map<number, { resolve: (v: any) => void; reject: (e: any) => void }>();
  tools: Array<{ name: string; description?: string; inputSchema?: any }> = [];

  constructor(
    readonly name: string,
    private cfg: ServerCfg,
  ) {}

  get connected() {
    return this.proc != null;
  }

  async connect(handshakeTimeoutMs = 600_000): Promise<void> {
    if ((this.cfg.type ?? "stdio") !== "stdio") {
      throw new Error(`server "${this.name}": only stdio transport is supported (got ${this.cfg.type})`);
    }
    const env = { ...process.env, ...(this.cfg.env ?? {}) };
    this.proc = spawn(this.cfg.command, this.cfg.args ?? [], {
      env,
      stdio: ["pipe", "pipe", "pipe"],
      ...(this.cfg.cwd ? { cwd: this.cfg.cwd } : {}),
    });
    this.proc.stdout!.setEncoding("utf8");
    this.proc.stdout!.on("data", (d: string) => this.onData(d));
    this.proc.stderr!.setEncoding("utf8");
    this.proc.stderr!.on("data", () => {
      /* server logs to stderr; swallow to keep the TUI clean */
    });
    this.proc.on("exit", () => {
      for (const p of this.pending.values()) p.reject(new Error(`MCP server "${this.name}" exited`));
      this.pending.clear();
      this.proc = null;
    });
    await this.request(
      "initialize",
      {
        protocolVersion: "2024-11-05",
        capabilities: {},
        clientInfo: { name: "pi-mcp-bridge", version: "1.0.0" },
      },
      handshakeTimeoutMs,
    );
    this.send({ jsonrpc: "2.0", method: "notifications/initialized", params: {} });
    const res = await this.request("tools/list", {}, 60_000);
    this.tools = res?.tools ?? [];
  }

  private onData(chunk: string) {
    this.buf += chunk;
    let idx: number;
    while ((idx = this.buf.indexOf("\n")) >= 0) {
      const line = this.buf.slice(0, idx).trim();
      this.buf = this.buf.slice(idx + 1);
      if (!line) continue;
      let msg: any;
      try {
        msg = JSON.parse(line);
      } catch {
        continue; // ignore non-JSON noise
      }
      if (msg.id != null && this.pending.has(msg.id)) {
        const p = this.pending.get(msg.id)!;
        this.pending.delete(msg.id);
        if (msg.error) p.reject(new Error(msg.error.message ?? "MCP error"));
        else p.resolve(msg.result);
      }
      // server-initiated requests/notifications are ignored (we advertise no capabilities)
    }
  }

  private send(obj: any) {
    if (!this.proc?.stdin) throw new Error(`MCP server "${this.name}" not running`);
    this.proc.stdin.write(JSON.stringify(obj) + "\n");
  }

  request(method: string, params: any, timeoutMs = 600_000): Promise<any> {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      try {
        this.send({ jsonrpc: "2.0", id, method, params });
      } catch (e) {
        this.pending.delete(id);
        reject(e);
        return;
      }
      if (timeoutMs > 0) {
        setTimeout(() => {
          if (this.pending.has(id)) {
            this.pending.delete(id);
            reject(new Error(`MCP ${this.name}.${method} timed out after ${timeoutMs}ms`));
          }
        }, timeoutMs).unref?.();
      }
    });
  }

  callTool(name: string, args: any) {
    return this.request("tools/call", { name, arguments: args ?? {} });
  }

  close() {
    try {
      this.proc?.kill();
    } catch {
      /* ignore */
    }
    this.proc = null;
  }
}

// Cap an MCP tool result before it enters the model's context. Some tools
// (e.g. get_phabricator_diff_details) return enormous blobs that flood the
// transcript. Override the limit with PI_MCP_MAX_RESULT (chars).
const MCP_MAX_RESULT = Number(process.env.PI_MCP_MAX_RESULT) || 12000;

export function capContent(content: any[], max: number): any[] {
  if (!Array.isArray(content)) return content;
  let used = 0;
  let truncated = false;
  const out: any[] = [];
  for (const item of content) {
    if (item && item.type === "text" && typeof item.text === "string") {
      if (used >= max) { truncated = true; continue; }
      const room = max - used;
      if (item.text.length > room) { out.push({ ...item, text: item.text.slice(0, room) }); used = max; truncated = true; }
      else { out.push(item); used += item.text.length; }
    } else {
      out.push(item);
    }
  }
  if (truncated) out.push({ type: "text", text: `\n[mcp-bridge: output truncated at ${max} chars — narrow the query or request specific fields; raise PI_MCP_MAX_RESULT to see more.]` });
  return out;
}

export default function mcpBridge(pi: ExtensionAPI) {
  const clients = new Map<string, McpClient>();
  const registered = new Set<string>();
  // Servers the user has connected this session, persisted to the session log so
  // the set survives extension re-init (/reload, /resume, /fork) -- which tears
  // down clients + tool registrations. On session_start we replay this and
  // reconnect, so a connection you made sticks instead of vanishing into a
  // "tool not found". Snapshot-style (full set each write, last wins), like cron.ts.
  const intended = new Set<string>();
  const persistConnected = () => { try { pi.appendEntry("mcp-connected", { servers: [...intended] }); } catch {} };

  const piToolName = (server: string, tool: string) =>
    `${server}__${tool}`.replace(/[^a-zA-Z0-9_]/g, "_").slice(0, 64);

  async function connectServer(name: string, cfg: ServerCfg, remember = true): Promise<string> {
    const existing = clients.get(name);
    if (existing?.connected) return `${name}: already connected (${existing.tools.length} tools)`;
    const client = new McpClient(name, cfg);
    await client.connect();
    clients.set(name, client);
    let added = 0;
    for (const t of client.tools) {
      const toolName = piToolName(name, t.name);
      if (registered.has(toolName)) continue;
      registered.add(toolName);
      added++;
      pi.registerTool({
        name: toolName,
        label: `${name}: ${t.name}`,
        // Cap the registered description: some MCP servers ship multi-paragraph
        // tool docs that otherwise bloat the tool schema on every later turn.
        description: t.description ? String(t.description).slice(0, 500) : `${t.name} (via ${name} MCP server)`,
        promptSnippet: t.description ? String(t.description).split("\n")[0].slice(0, 140) : undefined,
        // MCP inputSchema is plain JSON Schema; Type.Unsafe passes it through to the
        // model unchanged and skips re-validation so args reach the server as-is.
        parameters: Type.Unsafe(t.inputSchema ?? { type: "object", properties: {}, additionalProperties: true }),
        async execute(_id, params) {
          const c = clients.get(name);
          if (!c?.connected) throw new Error(`MCP server "${name}" is not connected (run /mcp connect ${name})`);
          const res = await c.callTool(t.name, params);
          const content = Array.isArray(res?.content)
            ? res.content
            : [{ type: "text", text: typeof res === "string" ? res : JSON.stringify(res) }];
          return { content: capContent(content, MCP_MAX_RESULT), details: { mcpServer: name, mcpTool: t.name, isError: !!res?.isError } };
        },
        // Quiet inline rendering -- humans don't care about raw MCP call/result
        // dumps. Render nothing inline (like the built-in read/bash/etc.); the
        // tool-aggregator widget still counts every call and surfaces errors.
        renderShell: "self",
        renderCall: () => EMPTY_RENDER,
        renderResult: () => EMPTY_RENDER,
      });
    }
    // Remember user-initiated connects so they auto-reconnect after re-init.
    // (autoConnect + session_start restore pass remember=false: config/session
    // already drive them, and we don't want autoConnect bleeding into memory.)
    if (remember && !intended.has(name)) { intended.add(name); persistConnected(); }
    return `${name}: connected, registered ${added} tool(s) as ${name}__*`;
  }

  pi.registerCommand("mcp", {
    description: "MCP servers: /mcp list | connect <name|all> | disconnect <name> | status",
    getArgumentCompletions: (prefix: string) => {
      const { servers } = loadConfig();
      const opts = ["list", "status", "connect all", ...Object.keys(servers).flatMap((s) => [`connect ${s}`, `disconnect ${s}`])];
      const items = opts.map((o) => ({ value: o, label: o })).filter((i) => i.value.startsWith(prefix));
      return items.length ? items : null;
    },
    handler: async (args: string, ctx: any) => {
      const { servers } = loadConfig();
      const [sub, name] = args.trim().split(/\s+/);
      if (!sub || sub === "list") {
        const names = Object.keys(servers);
        ctx.ui.notify(names.length ? `Configured MCP servers:\n- ${names.join("\n- ")}` : "No MCP servers in ~/.claude.json or ~/.pi/agent/mcp.json", "info");
        return;
      }
      if (sub === "status") {
        const lines = [...clients.entries()].filter(([, c]) => c.connected).map(([n, c]) => `${n}: ${c.tools.length} tools`);
        ctx.ui.notify(lines.length ? `Connected:\n- ${lines.join("\n- ")}` : "No MCP servers connected.", "info");
        return;
      }
      if (sub === "disconnect") {
        const c = name && clients.get(name);
        if (c) {
          c.close();
          if (name && intended.delete(name)) persistConnected(); // stop auto-reconnecting it after re-init
          ctx.ui.notify(`Disconnected ${name} (registered tools stay until session reload).`, "info");
        } else ctx.ui.notify(`Not connected: ${name}`, "warning");
        return;
      }
      if (sub === "connect") {
        const targets = name === "all" ? Object.keys(servers) : [name];
        for (const n of targets) {
          if (!n || !servers[n]) {
            ctx.ui.notify(`Unknown server: ${n}`, "warning");
            continue;
          }
          ctx.ui.setStatus("mcp", `Connecting ${n}…`);
          try {
            ctx.ui.notify(await connectServer(n, servers[n]), "info");
          } catch (e: any) {
            ctx.ui.notify(`Failed to connect ${n}: ${e?.message ?? e}`, "error");
          } finally {
            ctx.ui.setStatus("mcp", undefined);
          }
        }
        return;
      }
      ctx.ui.notify("Usage: /mcp list | connect <name|all> | disconnect <name> | status", "info");
    },
  });

  // Agent-driven, allowlisted connect. Register a tool the MODEL can call to load a
  // server on demand (lazy: keeps startup fast, tools appear only when needed). Only
  // servers with `agentConnect: true` in ~/.pi/agent/mcp.json are connectable this way;
  // everything else stays human-only via /mcp connect. Runtime pi.registerTool means the
  // freshly-registered <server>__<tool> tools are callable on the next turn.
  {
    const { servers } = loadConfig();
    const allow = Object.entries(servers).filter(([, c]) => c.agentConnect);
    // One short line per server (first sentence / ~100 chars of the hint) so the
    // mcp_connect description stays small — the full hint bloats the schema.
    const menu = allow.length
      ? allow.map(([n, c]) => `- ${n}${c.hint ? `: ${String(c.hint).split(/[.\n]/)[0].slice(0, 100)}` : ""}`).join("\n")
      : "(none configured — set \"agentConnect\": true on a server in ~/.pi/agent/mcp.json)";
    pi.registerTool({
      name: "mcp_connect",
      label: "Connect MCP server",
      description:
        "Load an allowlisted MCP server on demand. Spawns it and registers its tools as " +
        "`<server>__<tool>`, which become callable immediately (same session). Call this when " +
        "you need one of these tool groups:\n" +
        menu +
        "\nPass the server name. Only allowlisted servers can be connected; anything else is refused.",
      parameters: Type.Object({
        server: Type.String({ description: "Allowlisted MCP server name to connect" }),
      }),
      async execute(_id, params: { server: string }) {
        const server = String(params?.server ?? "").trim();
        const { servers: cur } = loadConfig();
        const cfg = cur[server];
        if (!cfg) {
          const names = Object.entries(cur).filter(([, c]) => c.agentConnect).map(([n]) => n);
          return {
            content: [{ type: "text", text: `Unknown server "${server}". Agent-connectable: ${names.join(", ") || "(none)"}.` }],
            details: { isError: true },
          };
        }
        if (!cfg.agentConnect) {
          return {
            content: [{ type: "text", text: `Server "${server}" is not on the agent allowlist (needs "agentConnect": true in ~/.pi/agent/mcp.json). A human can still connect it with /mcp connect ${server}.` }],
            details: { isError: true },
          };
        }
        const summary = await connectServer(server, cfg);
        return { content: [{ type: "text", text: `${summary}\nThose tools are now callable this session.` }] };
      },
    });
  }

  // On session_start, reconnect: (a) servers in mcp.json "autoConnect" (always-on,
  // config-driven), (b) servers named in $PI_MCP_AUTOCONNECT (env-driven -- how
  // subagent children get code search auto-connected; see subagent.ts), and
  // (c) servers the user had connected before an extension re-init (/reload,
  // /resume, /fork), replayed from the persisted "mcp-connected" snapshot. This
  // is what makes a connection survive re-init instead of dropping to "tool not
  // found". Bad/slow servers are caught so they never block startup.
  pi.on("session_start", async (_e: any, ctx: any) => {
    const { servers, autoConnect, subagentConnect } = loadConfig();
    const envAuto = (process.env.PI_MCP_AUTOCONNECT || "").split(",").map((s) => s.trim()).filter(Boolean);
    // Subagent children get the code-search set declared in mcp.json (no hard-coded list).
    const childAuto = process.env.PI_AGENT_TEAM_CHILD === "1" ? subagentConnect : [];
    let remembered: string[] = [];
    try {
      for (const entry of ctx?.sessionManager?.getEntries?.() ?? []) {
        if (entry?.type === "custom" && entry?.customType === "mcp-connected") {
          const d = entry.data as { servers?: string[] } | undefined;
          if (Array.isArray(d?.servers)) remembered = d.servers; // last write wins
        }
      }
    } catch { /* no session manager / print mode */ }
    for (const n of remembered) intended.add(n); // repopulate memory for future persists
    for (const n of new Set<string>([...autoConnect, ...childAuto, ...envAuto, ...remembered])) {
      if (!servers[n]) continue;
      try { await connectServer(n, servers[n], false); } catch { /* never block startup */ }
    }
  });

  pi.on("session_shutdown", async () => {
    for (const c of clients.values()) c.close();
    clients.clear();
  });
}
