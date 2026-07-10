/**
 * Pure helpers for the /goal extension: transcript serialization + verdict
 * parsing. No external imports so it runs under `node --experimental-strip-types`.
 *
 * Self-check:  node --experimental-strip-types goal-parse.ts
 */

const TRANSCRIPT_CAP = 40_000; // chars; keep the most recent tail

type Block = { type?: string; text?: string; name?: string; arguments?: unknown };
type Entry = { type: string; message?: { role?: string; content?: unknown } };

function blocks(content: unknown): Block[] {
	if (typeof content === "string") return [{ type: "text", text: content }];
	return Array.isArray(content) ? (content as Block[]) : [];
}

export function serialize(branch: Entry[]): string {
	const lines: string[] = [];
	for (const e of branch) {
		if (e.type !== "message" || !e.message?.role) continue;
		const role = e.message.role;
		const label = role === "user" ? "User" : role === "assistant" ? "Assistant" : "Tool result";
		for (const b of blocks(e.message.content)) {
			if (b.type === "text" && b.text?.trim()) lines.push(`${label}: ${b.text.trim()}`);
			else if (b.type === "toolCall" && b.name)
				lines.push(`Assistant called ${b.name}(${JSON.stringify(b.arguments ?? {})})`);
		}
	}
	const text = lines.join("\n\n");
	return text.length > TRANSCRIPT_CAP ? text.slice(-TRANSCRIPT_CAP) : text;
}

export function parseVerdict(raw: string): { met: boolean; reason: string } {
	const match = raw.match(/\{[\s\S]*\}/);
	if (match) {
		try {
			const v = JSON.parse(match[0]) as { met?: unknown; reason?: unknown };
			return { met: v.met === true, reason: String(v.reason ?? "").trim() || "no reason given" };
		} catch {
			/* fall through */
		}
	}
	// Fallback heuristic if the model didn't return clean JSON.
	const met = /\bmet\b/i.test(raw) && !/\bnot met\b/i.test(raw);
	return { met, reason: raw.trim().slice(0, 200) || "unparseable evaluator output" };
}

export type { Entry };

// ---- self-check ----------------------------------------------------------
if (process.argv[1] && import.meta.url.endsWith(process.argv[1].split("/").pop()!)) {
	const assert = (c: boolean, m: string) => {
		if (!c) throw new Error(`FAIL: ${m}`);
	};

	// clean JSON, met
	let v = parseVerdict('{"met": true, "reason": "npm test exited 0"}');
	assert(v.met && v.reason === "npm test exited 0", "clean met");

	// JSON embedded in prose, not met
	v = parseVerdict('Here is my answer:\n{"met": false, "reason": "tests still failing"}');
	assert(!v.met && v.reason === "tests still failing", "embedded not-met");

	// missing reason
	v = parseVerdict('{"met": true}');
	assert(v.met && v.reason === "no reason given", "missing reason");

	// "met" as a string (not boolean true) must NOT count as met
	v = parseVerdict('{"met": "yes"}');
	assert(!v.met, "non-boolean met is false");

	// garbage output -> fallback heuristic
	v = parseVerdict("The condition is not met because the build failed.");
	assert(!v.met, "fallback not met");
	v = parseVerdict("Condition met.");
	assert(v.met, "fallback met");

	// serialize picks up text, tool calls, and tool results; skips non-message
	const t = serialize([
		{ type: "message", message: { role: "user", content: "run the tests" } },
		{
			type: "message",
			message: {
				role: "assistant",
				content: [
					{ type: "text", text: "running" },
					{ type: "toolCall", name: "bash", arguments: { command: "npm test" } },
				],
			},
		},
		{ type: "message", message: { role: "toolResult", content: [{ type: "text", text: "0 passing" }] } },
		{ type: "custom" },
	]);
	assert(t.includes("User: run the tests"), "user line");
	assert(t.includes("Assistant called bash(") && t.includes("npm test"), "tool call line");
	assert(t.includes("Tool result: 0 passing"), "tool result line");
	assert(!t.includes("custom"), "non-message skipped");

	// transcript cap keeps the tail
	const long = serialize([{ type: "message", message: { role: "user", content: "x".repeat(60_000) } }]);
	assert(long.length === TRANSCRIPT_CAP && long.endsWith("x"), "cap keeps tail");

	console.log("goal-parse self-check: all assertions passed");
}
