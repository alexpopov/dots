/**
 * /goal — keep pi working toward a completion condition across turns.
 *
 * Port of Claude Code's /goal. After each agent turn (agent_end), a model
 * checks whether the condition holds against what's in the conversation. If
 * not, pi starts another turn with the evaluator's reason as guidance. The
 * goal clears automatically once the condition is met.
 *
 *   /goal <condition>   set a goal and start working (condition is the directive)
 *   /goal               show status (condition, turns, elapsed, last reason)
 *   /goal clear         clear an active goal (aliases: stop off reset none cancel)
 *
 * Config (env, optional):
 *   PI_GOAL_MODEL=provider/id   evaluator model (default: current session model)
 *   PI_GOAL_MAX_TURNS=50        hard safety cap on turns
 */

import { complete, getModel, type Message } from "@earendil-works/pi-ai/compat";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { type Entry, parseVerdict, serialize } from "./parse.ts";

const CLEAR_ALIASES = new Set(["clear", "stop", "off", "reset", "none", "cancel"]);
// Hard safety cap. Clamp to a finite positive int so Infinity/negatives/garbage
// can't disable the bound (the only way to make the goal loop run forever).
const MAX_TURNS = (() => {
	const n = Number(process.env.PI_GOAL_MAX_TURNS);
	return Number.isFinite(n) && n > 0 ? Math.floor(n) : 50;
})();
const MAX_CONDITION = 4000;

const EVAL_SYSTEM = [
	"You are a strict goal-completion evaluator for a coding agent.",
	"You are given a COMPLETION CONDITION and the recent CONVERSATION (including tool output).",
	"Decide whether the condition is demonstrably satisfied by EVIDENCE ALREADY IN THE CONVERSATION.",
	"You cannot run commands or read files yourself. If the agent has not shown proof",
	"(a passing test run, a clean build exit, an empty queue, etc.), the condition is NOT met.",
	'Respond with ONE line of JSON and nothing else: {"met": true|false, "reason": "<one concise sentence>"}',
].join(" ");

type Goal = {
	condition: string;
	startedAt: number;
	turns: number;
	lastReason?: string;
	achieved?: boolean;
};

// ---- extension ----------------------------------------------------------

export default function (pi: ExtensionAPI) {
	let goal: Goal | null = null;
	let evaluating = false;

	const persist = () => pi.appendEntry("goal-state", goal ?? { cleared: true });

	const fmtElapsed = (ms: number) => {
		const s = Math.floor(ms / 1000);
		return `${Math.floor(s / 60)}m${String(s % 60).padStart(2, "0")}s`;
	};

	const showStatus = (ctx: ExtensionContext) => {
		if (!ctx.hasUI || !goal) return;
		const badge = goal.achieved ? "✓ goal achieved" : "◎ goal active";
		ctx.ui.setStatus("goal", `${badge} (${goal.turns}t, ${fmtElapsed(Date.now() - goal.startedAt)})`);
	};

	const clearGoal = (ctx: ExtensionContext) => {
		goal = null;
		persist();
		if (ctx.hasUI) ctx.ui.setStatus("goal", "");
	};

	// Restore an active goal on resume/reload (condition carries over; timer/turns reset).
	pi.on("session_start", (event, _ctx) => {
		goal = null;
		if (event.reason !== "resume" && event.reason !== "reload") return;
		for (const e of _ctx.sessionManager.getEntries() as Array<Entry & { customType?: string; data?: unknown }>) {
			if (e.type === "custom" && e.customType === "goal-state") {
				const d = e.data as (Goal & { cleared?: boolean }) | undefined;
				goal = d && !d.cleared && !d.achieved ? { ...d, startedAt: Date.now(), turns: 0 } : null;
			}
		}
		showStatus(_ctx);
	});

	pi.registerCommand("goal", {
		description: "Keep working toward a condition until a model confirms it's met",
		handler: async (args, ctx) => {
			const arg = args.trim();

			// Status
			if (!arg) {
				if (!goal) return ctx.ui.notify("No goal active. Usage: /goal <condition>", "info");
				const reason = goal.lastReason ? `\nlast: ${goal.lastReason}` : "";
				const state = goal.achieved ? "achieved" : "active";
				ctx.ui.notify(
					`Goal (${state}): ${goal.condition}\n${goal.turns} turns, ${fmtElapsed(Date.now() - goal.startedAt)}${reason}`,
					"info",
				);
				return;
			}

			// Clear
			if (CLEAR_ALIASES.has(arg.toLowerCase())) {
				if (!goal || goal.achieved) return ctx.ui.notify("No active goal to clear", "info");
				clearGoal(ctx);
				return ctx.ui.notify("Goal cleared", "info");
			}

			// Set
			if (arg.length > MAX_CONDITION)
				return ctx.ui.notify(`Condition too long (max ${MAX_CONDITION} chars)`, "warning");
			goal = { condition: arg, startedAt: Date.now(), turns: 0 };
			persist();
			showStatus(ctx);
			ctx.ui.notify("Goal set — working toward it", "info");
			if (ctx.isIdle()) pi.sendUserMessage(arg);
			else pi.sendUserMessage(arg, { deliverAs: "followUp" });
		},
	});

	// The evaluator: pi's per-prompt stop point. Claude's "after each turn".
	pi.on("agent_end", async (_event, ctx) => {
		if (!goal || goal.achieved || evaluating) return;

		goal.turns += 1;
		showStatus(ctx);

		if (goal.turns > MAX_TURNS) {
			goal.lastReason = `stopped after ${MAX_TURNS} turns (safety cap)`;
			ctx.ui.notify(`Goal: ${goal.lastReason}`, "warning");
			clearGoal(ctx);
			return;
		}

		const model =
			(process.env.PI_GOAL_MODEL &&
				getModel(...(process.env.PI_GOAL_MODEL.split("/", 2) as [string, string]))) ||
			ctx.model;
		if (!model) return; // no model to evaluate with; leave goal set, try next turn
		const auth = await ctx.modelRegistry.getApiKeyAndHeaders(model);
		if (!auth.ok || !auth.apiKey) {
			ctx.ui.notify(auth.ok ? `No API key for ${model.provider}` : auth.error, "warning");
			return;
		}

		evaluating = true;
		try {
			const user: Message = {
				role: "user",
				content: [
					{
						type: "text",
						text: `COMPLETION CONDITION:\n${goal.condition}\n\nCONVERSATION:\n${serialize(
							ctx.sessionManager.getBranch() as Entry[],
						)}`,
					},
				],
				timestamp: Date.now(),
			};
			const res = await complete(
				model,
				{ systemPrompt: EVAL_SYSTEM, messages: [user] },
				{ apiKey: auth.apiKey, headers: auth.headers, env: auth.env, signal: ctx.signal },
			);
			if (res.stopReason === "aborted") return;

			const verdict = parseVerdict(
				res.content
					.filter((c): c is { type: "text"; text: string } => c.type === "text")
					.map((c) => c.text)
					.join(""),
			);
			goal.lastReason = verdict.reason;

			if (verdict.met) {
				goal.achieved = true;
				persist();
				showStatus(ctx);
				ctx.ui.notify(`✓ Goal achieved: ${verdict.reason}`, "info");
			} else {
				persist();
				pi.sendUserMessage(
					`Goal not yet met. Evaluator: ${verdict.reason}\n\nKeep working toward the goal, and show how it is verified: ${goal.condition}`,
					{ deliverAs: "followUp" },
				);
			}
		} catch (err) {
			ctx.ui.notify(`Goal evaluation failed: ${(err as Error).message}`, "warning");
		} finally {
			evaluating = false;
		}
	});
}
