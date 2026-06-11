/**
 * cron.ts — scheduled tasks for pi (a port of Claude Code's CronCreate / /loop).
 *
 * Lets the LLM (and you) schedule prompts to run on a cron schedule, on a relative
 * delay, or once. When a task is due it injects its prompt as a user message with
 * `deliverAs: "followUp"` — i.e. it fires *between turns*, never mid-response, and
 * waits if the agent is busy. This mirrors Claude's session-scoped scheduler.
 *
 * Model-facing tools:  cron_create, cron_list, cron_delete, cron_reschedule
 * Human commands:      /cron [list|add <expr> <prompt>|rm <id>|help],  /loop [<interval>] [<prompt>]
 *
 * Semantics (matching the reference doc):
 *  - 1s tick; a task fires at most once per matched minute (no catch-up for missed fires).
 *  - Fires only while pi is running AND idle (followUp delivery handles the "waits if busy").
 *  - Deterministic sub-minute jitter from the task id spreads load.
 *  - Recurring tasks auto-expire 7 days after creation (one final fire, then deleted).
 *  - State persists via appendEntry and is restored on --resume (one-shots whose time
 *    already passed, and recurring tasks older than 7d, are pruned on restore).
 *  - Max 50 tasks. Disable entirely with PI_DISABLE_CRON=1.
 *
 * Cron grammar (5 fields: min hour dom month dow): *  5  *​/15  1-5  1,15,30 . Day-of-week
 * 0 or 7 = Sunday. vixie-cron DOM/DOW "either matches" semantics. No L/W/? or name aliases.
 */

import { promises as fs } from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const MAX_TASKS = 50;
const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;
const LOOP_MD_MAX_BYTES = 25_000;
const DEFAULT_LOOP_CRON = "*/15 * * * *";
const ENTRY_TYPE = "cron-tasks";

type DeliverAs = "followUp" | "steer" | "nextTurn";

interface Task {
	id: string; // 8-char
	prompt: string;
	cron?: string; // 5-field cron expression (recurring or fixed one-shot)
	fireAt?: number; // epoch ms (relative one-shot); mutually exclusive with cron
	once: boolean; // delete after first fire
	createdAt: number; // epoch ms
	deliverAs: DeliverAs;
}

// ---------------------------------------------------------------------------
// Cron parsing / matching
// ---------------------------------------------------------------------------

/** Parse one cron field into a Set of allowed values, or null for "*" (matches all). */
function parseField(field: string, lo: number, hi: number): Set<number> | null {
	if (field === "*") return null;
	const out = new Set<number>();
	for (const part of field.split(",")) {
		const [rangeRaw, stepRaw] = part.split("/");
		const step = stepRaw === undefined ? 1 : Number.parseInt(stepRaw, 10);
		if (!Number.isInteger(step) || step < 1) throw new Error(`invalid step in "${field}"`);
		let a: number;
		let b: number;
		if (rangeRaw === "*") {
			a = lo;
			b = hi;
		} else if (rangeRaw.includes("-")) {
			const [x, y] = rangeRaw.split("-");
			a = Number.parseInt(x, 10);
			b = Number.parseInt(y, 10);
		} else {
			a = Number.parseInt(rangeRaw, 10);
			b = a;
		}
		if (!Number.isInteger(a) || !Number.isInteger(b)) throw new Error(`invalid value in "${field}"`);
		if (a < lo || b > hi || a > b) throw new Error(`"${field}" out of range ${lo}-${hi}`);
		for (let v = a; v <= b; v += step) out.add(v);
	}
	return out;
}

interface ParsedCron {
	min: Set<number> | null;
	hour: Set<number> | null;
	dom: Set<number> | null;
	mon: Set<number> | null;
	dow: Set<number> | null;
}

/** Parse + validate a 5-field cron expression. Throws on malformed input. */
function parseCron(expr: string): ParsedCron {
	const parts = expr.trim().split(/\s+/);
	if (parts.length !== 5) throw new Error(`expected 5 cron fields, got ${parts.length}: "${expr}"`);
	const [m, h, dom, mon, dowRaw] = parts;
	const dow = parseField(dowRaw, 0, 7);
	if (dow?.has(7)) dow.add(0); // normalize Sunday
	return {
		min: parseField(m, 0, 59),
		hour: parseField(h, 0, 23),
		dom: parseField(dom, 1, 31),
		mon: parseField(mon, 1, 12),
		dow,
	};
}

/** Does a parsed cron match the given local Date (to the minute)? */
function cronMatches(c: ParsedCron, d: Date): boolean {
	const minMatch = !c.min || c.min.has(d.getMinutes());
	const hourMatch = !c.hour || c.hour.has(d.getHours());
	const monMatch = !c.mon || c.mon.has(d.getMonth() + 1);
	const domMatch = !c.dom || c.dom.has(d.getDate());
	const dowMatch = !c.dow || c.dow.has(d.getDay());
	// vixie-cron: when BOTH day fields are restricted, match if EITHER matches.
	const dayMatch = c.dom && c.dow ? domMatch || dowMatch : domMatch && dowMatch;
	return minMatch && hourMatch && monMatch && dayMatch;
}

/** Convert a human interval token ("30s","5m","2h","1d") to a cron expression, or null. */
function intervalToCron(token: string): string | null {
	const m = /^(\d+)\s*([smhd])$/i.exec(token.trim());
	if (!m) return null;
	let n = Number.parseInt(m[1], 10);
	const unit = m[2].toLowerCase();
	if (n < 1) return null;
	if (unit === "s") n = Math.max(1, Math.ceil(n / 60)); // seconds round up to whole minutes
	if (unit === "s" || unit === "m") {
		if (n >= 60) {
			const h = Math.round(n / 60);
			return h <= 23 ? `0 */${h} * * *` : "0 0 * * *";
		}
		const clean = nearestMinuteDivisor(n);
		return clean === 1 ? "* * * * *" : `*/${clean} * * * *`;
	}
	if (unit === "h") {
		if (n <= 23) return `0 */${n} * * *`;
		const d = Math.max(1, Math.round(n / 24));
		return d <= 31 ? `0 0 */${d} * *` : "0 0 1 * *";
	}
	// days
	return n <= 31 ? `0 0 */${n} * *` : "0 0 1 * *";
}

/** Round a minute interval to the nearest value that divides 60 cleanly (cron-friendly). */
function nearestMinuteDivisor(n: number): number {
	const divisors = [1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30];
	let best = divisors[0];
	for (const d of divisors) if (Math.abs(d - n) < Math.abs(best - n)) best = d;
	return best;
}

// ---------------------------------------------------------------------------
// Misc helpers
// ---------------------------------------------------------------------------

function newId(): string {
	let s = "";
	const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789";
	for (let i = 0; i < 8; i++) s += alphabet[Math.floor(Math.random() * alphabet.length)];
	return s;
}

/** Deterministic 0-59s jitter derived from the task id. */
function jitterSeconds(id: string): number {
	let hash = 0;
	for (let i = 0; i < id.length; i++) hash = (hash * 31 + id.charCodeAt(i)) | 0;
	return Math.abs(hash) % 60;
}

function minuteKey(d: Date): string {
	return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}-${d.getHours()}-${d.getMinutes()}`;
}

function describe(t: Task): string {
	const when = t.cron ? t.cron : t.fireAt ? `at ${new Date(t.fireAt).toLocaleString()}` : "?";
	const kind = t.once ? "once" : "recurring";
	return `[${t.id}] ${when} (${kind}) → ${t.prompt}`;
}

// ---------------------------------------------------------------------------
// Extension
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
	if (process.env.PI_DISABLE_CRON === "1") return;

	let tasks: Task[] = [];
	const parsedCache = new Map<string, ParsedCron>(); // cron string -> parsed
	const lastFireMinute = new Map<string, string>(); // task id -> minute key (transient)
	const pending = new Map<string, boolean>(); // task id -> has an undelivered tick queued (transient)
	let timer: ReturnType<typeof setInterval> | null = null;
	let lastCtx: ExtensionContext | null = null;

	const persist = () => pi.appendEntry(ENTRY_TYPE, { tasks });

	const getParsed = (cron: string): ParsedCron => {
		let p = parsedCache.get(cron);
		if (!p) {
			p = parseCron(cron);
			parsedCache.set(cron, p);
		}
		return p;
	};

	const notify = (msg: string, level: "info" | "error" = "info") => {
		try {
			lastCtx?.ui.notify(msg, level);
		} catch {
			/* no UI (print mode) */
		}
	};

	/** Restore tasks from the most recent persisted snapshot; prune stale ones. */
	const restore = (ctx: ExtensionContext) => {
		lastCtx = ctx;
		let snapshot: Task[] | null = null;
		for (const entry of ctx.sessionManager.getEntries()) {
			if (entry.type === "custom" && entry.customType === ENTRY_TYPE) {
				const data = entry.data as { tasks?: Task[] } | undefined;
				if (data?.tasks) snapshot = data.tasks; // last one wins
			}
		}
		const now = Date.now();
		tasks = (snapshot ?? []).filter((t) => {
			if (t.fireAt && t.fireAt < now) return false; // one-shot whose time already passed
			if (t.cron && !t.once && now - t.createdAt > SEVEN_DAYS_MS) return false; // expired recurring
			return true;
		});
		lastFireMinute.clear();
		pending.clear();
		parsedCache.clear();
	};

	const fire = (t: Task) => {
		// followUp = deliver only when the agent has no more tool calls (fires between turns).
		// When idle, sendUserMessage triggers a new turn immediately. Slash-command prompts work too.
		pi.sendUserMessage(t.prompt, { deliverAs: t.deliverAs });
	};

	const tick = () => {
		if (tasks.length === 0) return;
		const now = new Date();
		const nowMs = now.getTime();
		const key = minuteKey(now);
		const toDelete: string[] = [];

		for (const t of tasks) {
			try {
				if (t.fireAt) {
					if (nowMs >= t.fireAt) {
						fire(t);
						toDelete.push(t.id);
					}
					continue;
				}
				if (!t.cron) continue;
				if (lastFireMinute.get(t.id) === key) continue; // already fired this minute
				if (now.getSeconds() < jitterSeconds(t.id)) continue; // wait out jitter offset
				if (!cronMatches(getParsed(t.cron), now)) continue;

				lastFireMinute.set(t.id, key);
				const expired = !t.once && nowMs - t.createdAt > SEVEN_DAYS_MS;
				// Coalesce missed fires: if an earlier tick for this recurring task is still queued
				// and undelivered (the agent was busy), absorb this boundary instead of stacking
				// another message. One-shots and the final expiry fire always proceed.
				if (!t.once && !expired && pending.get(t.id)) continue;
				pending.set(t.id, true);
				fire(t); // recurring fires one final time on expiry, then is removed
				if (t.once || expired) toDelete.push(t.id);
			} catch (err) {
				notify(`cron task ${t.id} error: ${(err as Error).message}`, "error");
			}
		}

		if (toDelete.length) {
			tasks = tasks.filter((t) => !toDelete.includes(t.id));
			for (const id of toDelete) {
				lastFireMinute.delete(id);
				pending.delete(id);
			}
			persist();
		}
	};

	const ensureTimer = () => {
		if (timer) clearInterval(timer);
		timer = setInterval(() => {
			try {
				tick();
			} catch {
				/* never let a tick crash the loop */
			}
		}, 1000);
		// Don't keep the process alive solely for the scheduler.
		(timer as unknown as { unref?: () => void }).unref?.();
	};

	pi.on("session_start", async (_e, ctx) => {
		restore(ctx);
		ensureTimer();
	});
	pi.on("session_tree", async (_e, ctx) => restore(ctx));
	// agent_start fires once when the agent picks up a delivered message (a new agent run), i.e.
	// the queued tick has been consumed. Clearing here caps outstanding ticks at one per task, so a
	// long busy run collapses to a single delivery (no pile-up / no catch-up storm). We deliberately
	// do NOT clear on turn_start, which fires per tool-call cycle within one busy run and would let
	// ticks re-queue mid-run.
	pi.on("agent_start", async () => pending.clear());
	pi.on("session_shutdown", async () => {
		if (timer) clearInterval(timer);
		timer = null;
	});

	// --- shared create logic -------------------------------------------------
	const createTask = (input: {
		prompt: string;
		schedule?: string;
		inSeconds?: number;
		recurs?: boolean;
		deliverAs?: DeliverAs;
	}): { ok: true; task: Task } | { ok: false; error: string } => {
		if (!input.prompt?.trim()) return { ok: false, error: "prompt is required" };
		if (tasks.length >= MAX_TASKS) return { ok: false, error: `task limit reached (${MAX_TASKS})` };

		const id = newId();
		const deliverAs = input.deliverAs ?? "followUp";
		let task: Task;
		if (input.inSeconds !== undefined) {
			if (!(input.inSeconds > 0)) return { ok: false, error: "inSeconds must be > 0" };
			task = { id, prompt: input.prompt, fireAt: Date.now() + input.inSeconds * 1000, once: true, createdAt: Date.now(), deliverAs };
		} else if (input.schedule) {
			try {
				getParsed(input.schedule); // validate
			} catch (err) {
				return { ok: false, error: `invalid cron: ${(err as Error).message}` };
			}
			task = { id, prompt: input.prompt, cron: input.schedule.trim(), once: input.recurs === false, createdAt: Date.now(), deliverAs };
		} else {
			return { ok: false, error: "provide either `schedule` (cron) or `inSeconds`" };
		}
		tasks.push(task);
		persist();
		ensureTimer();
		return { ok: true, task };
	};

	const deleteTask = (id: string): boolean => {
		const before = tasks.length;
		tasks = tasks.filter((t) => t.id !== id);
		lastFireMinute.delete(id);
		pending.delete(id);
		if (tasks.length !== before) {
			persist();
			return true;
		}
		return false;
	};

	// --- model-facing tools --------------------------------------------------
	pi.registerTool({
		name: "cron_create",
		label: "Schedule task",
		description:
			"Schedule a prompt to run later. Use `schedule` (5-field cron, e.g. '*/5 * * * *') for recurring or fixed-time runs, or `inSeconds` for a one-shot relative reminder (e.g. 2700 = 45 min). Set recurs=false for a one-time cron fire. The prompt runs between turns when the agent is idle. Returns the 8-char task id.",
		promptGuidelines: [
			"Use cron_create when the user asks to schedule, repeat, poll, loop, or be reminded of a prompt (e.g. 'every 5 minutes', 'at 9am', 'in 45 minutes', 'remind me to ...').",
			"For relative reminders use cron_create with inSeconds; for recurring or clock-time use a cron `schedule`. All times are local.",
		],
		parameters: Type.Object({
			prompt: Type.String({ description: "The prompt (or /command) to run when the task fires." }),
			schedule: Type.Optional(Type.String({ description: "5-field cron expression: min hour day-of-month month day-of-week." })),
			inSeconds: Type.Optional(Type.Number({ description: "Relative one-shot delay in seconds. Mutually exclusive with schedule." })),
			recurs: Type.Optional(Type.Boolean({ description: "For a cron schedule: true (default) repeats; false fires once at the next match." })),
		}),
		async execute(_id, params) {
			const r = createTask(params as Parameters<typeof createTask>[0]);
			if (!r.ok) return { content: [{ type: "text", text: `Error: ${r.error}` }], details: { error: r.error } };
			notify(`⏰ scheduled ${r.task.id}`);
			return { content: [{ type: "text", text: `Scheduled: ${describe(r.task)}` }], details: { task: r.task } };
		},
	});

	pi.registerTool({
		name: "cron_list",
		label: "List scheduled tasks",
		description: "List all scheduled tasks with their ids, schedules, and prompts.",
		parameters: Type.Object({}),
		async execute() {
			const text = tasks.length ? tasks.map(describe).join("\n") : "No scheduled tasks.";
			return { content: [{ type: "text", text }], details: { tasks } };
		},
	});

	pi.registerTool({
		name: "cron_delete",
		label: "Cancel scheduled task",
		description: "Cancel a scheduled task by its 8-char id.",
		parameters: Type.Object({ id: Type.String({ description: "The task id from cron_create/cron_list." }) }),
		async execute(_id, params) {
			const ok = deleteTask((params as { id: string }).id);
			return { content: [{ type: "text", text: ok ? `Cancelled ${(params as { id: string }).id}` : `No task ${(params as { id: string }).id}` }], details: { ok } };
		},
	});

	pi.registerTool({
		name: "cron_reschedule",
		label: "Reschedule task",
		description:
			"Re-arm an existing task to fire again after a relative delay (enables self-paced loops: at the end of a loop iteration, call this to choose the next interval, or omit to let the loop end).",
		parameters: Type.Object({
			id: Type.String({ description: "Existing task id." }),
			inSeconds: Type.Number({ description: "Delay until the next fire, in seconds." }),
		}),
		async execute(_id, params) {
			const p = params as { id: string; inSeconds: number };
			const existing = tasks.find((t) => t.id === p.id);
			if (!existing) return { content: [{ type: "text", text: `No task ${p.id}` }], details: { ok: false } };
			if (!(p.inSeconds > 0)) return { content: [{ type: "text", text: "inSeconds must be > 0" }], details: { ok: false } };
			existing.cron = undefined;
			existing.once = true;
			existing.fireAt = Date.now() + p.inSeconds * 1000;
			lastFireMinute.delete(p.id);
			pending.delete(p.id);
			persist();
			return { content: [{ type: "text", text: `Rescheduled ${p.id} in ${p.inSeconds}s` }], details: { ok: true } };
		},
	});

	// --- human commands ------------------------------------------------------
	pi.registerCommand("cron", {
		description: "Manage scheduled tasks: /cron [list | add <cron expr> <prompt> | rm <id> | help]",
		handler: async (args, ctx) => {
			lastCtx = ctx;
			const trimmed = (args ?? "").trim();
			const [sub, ...rest] = trimmed.split(/\s+/);
			if (!sub || sub === "list") {
				notify(tasks.length ? tasks.map(describe).join("\n") : "No scheduled tasks.");
				return;
			}
			if (sub === "help") {
				notify("/cron add '<min hour dom mon dow>' <prompt>  ·  /cron rm <id>  ·  /cron list   |   /loop <30s|5m|2h|1d> <prompt>");
				return;
			}
			if (sub === "rm" || sub === "cancel" || sub === "delete") {
				notify(deleteTask(rest[0]) ? `Cancelled ${rest[0]}` : `No task ${rest[0]}`, rest[0] ? "info" : "error");
				return;
			}
			if (sub === "add") {
				// First 5 tokens are the cron expression; the remainder is the prompt.
				const tokens = trimmed.slice(sub.length).trim().split(/\s+/);
				if (tokens.length < 6) {
					notify("usage: /cron add <min> <hour> <dom> <mon> <dow> <prompt>", "error");
					return;
				}
				const schedule = tokens.slice(0, 5).join(" ");
				const prompt = tokens.slice(5).join(" ");
				const r = createTask({ prompt, schedule });
				notify(r.ok ? `⏰ scheduled ${r.task.id}: ${describe(r.task)}` : `Error: ${r.error}`, r.ok ? "info" : "error");
				return;
			}
			notify(`unknown subcommand "${sub}" — try /cron help`, "error");
		},
	});

	pi.registerCommand("loop", {
		description: "Run a prompt on a repeat: /loop <interval> <prompt>  (interval like 30s, 5m, 2h, 1d). Bare /loop runs loop.md or a maintenance prompt every 15m.",
		handler: async (args, ctx) => {
			lastCtx = ctx;
			const trimmed = (args ?? "").trim();
			const firstTok = trimmed.split(/\s+/)[0] ?? "";
			const cronFromInterval = intervalToCron(firstTok);

			let schedule = DEFAULT_LOOP_CRON;
			let prompt = trimmed;
			if (cronFromInterval) {
				schedule = cronFromInterval;
				prompt = trimmed.slice(firstTok.length).trim();
			}
			if (!prompt) prompt = await loadLoopPrompt(ctx);

			const r = createTask({ prompt, schedule });
			notify(r.ok ? `⏰ loop ${r.task.id} every "${schedule}"` : `Error: ${r.error}`, r.ok ? "info" : "error");
		},
	});
}

/** Read .pi/loop.md (project) then ~/.pi/loop.md (user); fall back to a built-in maintenance prompt. */
async function loadLoopPrompt(ctx: ExtensionContext): Promise<string> {
	const candidates = [path.join(ctx.cwd, ".pi", "loop.md"), path.join(os.homedir(), ".pi", "loop.md")];
	for (const file of candidates) {
		try {
			const raw = await fs.readFile(file, "utf-8");
			const text = raw.slice(0, LOOP_MD_MAX_BYTES).trim();
			if (text) return text;
		} catch {
			/* not found */
		}
	}
	return "Continue any unfinished work from the conversation; tend to the current branch's PR (review comments, failed CI, merge conflicts); otherwise do a small cleanup pass. Do not start new initiatives or take irreversible actions unless the transcript already authorized them. If everything is green and quiet, say so in one line.";
}
