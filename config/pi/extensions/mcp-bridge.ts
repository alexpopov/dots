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
 * one source of truth for both). Optional ~/.pi/agent/mcp.json can add/override servers
 * and set an `autoConnect` list. Server shape (stdio): { command, args?, env? }.
 *
 * Usage in chat:
 *   /mcp list                  — list configured servers
 *   /mcp connect <name>        — spawn + register a server's tools (persists for the session)
 *   /mcp connect all           — connect every configured server
 *   /mcp status                — show connected servers + tool counts
 *   /mcp disconnect <name>     — kill a server process
 * Tools then appear as `<server>__<tool>` and the model can call them immediately.
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

interface ServerCfg {
  command: string;
  args?: string[];
  env?: Record<string, string>;
  type?: string; // only "stdio" supported here
}

interface BridgeConfig {
  servers: Record<string, ServerCfg>;
  autoConnect: string[];
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
  return { servers, autoConnect };
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
    this.proc = spawn(this.cfg.command, this.cfg.args ?? [], { env, stdio: ["pipe", "pipe", "pipe"] });
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

export default function mcpBridge(pi: ExtensionAPI) {
  const clients = new Map<string, McpClient>();
  const registered = new Set<string>();

  const piToolName = (server: string, tool: string) =>
    `${server}__${tool}`.replace(/[^a-zA-Z0-9_]/g, "_").slice(0, 64);

  async function connectServer(name: string, cfg: ServerCfg): Promise<string> {
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
        description: t.description ?? `${t.name} (via ${name} MCP server)`,
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
          return { content, details: { mcpServer: name, mcpTool: t.name, isError: !!res?.isError } };
        },
      });
    }
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

  // Auto-connect servers listed in ~/.pi/agent/mcp.json "autoConnect" (default: none, for fast startup).
  pi.on("session_start", async () => {
    const { servers, autoConnect } = loadConfig();
    for (const n of autoConnect) {
      if (servers[n]) {
        try {
          await connectServer(n, servers[n]);
        } catch {
          /* don't let a bad server break startup */
        }
      }
    }
  });

  pi.on("session_shutdown", async () => {
    for (const c of clients.values()) c.close();
    clients.clear();
  });
}
