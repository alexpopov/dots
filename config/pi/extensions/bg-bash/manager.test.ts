/**
 * Self-check for bg-bash/manager.ts. Spawns real processes.
 *
 *   node --experimental-strip-types manager.test.ts
 */

import assert from "node:assert/strict";
import { createManager, humanDuration, type Job } from "./manager.ts";

/** Collect announcements and let a test await the next one. */
function harness() {
	const announced: string[] = [];
	let wake: (() => void) | null = null;
	const manager = createManager({
		announce: (report, job) => {
			assert.equal(typeof job.id, "string", "announce receives the job");
			assert.notEqual(job.endedAt, undefined, "job is finished when announced");
			announced.push(report);
			wake?.();
		},
	});
	const next = (timeoutMs = 15_000): Promise<string> =>
		new Promise((resolve, reject) => {
			const before = announced.length;
			const timer = setTimeout(() => reject(new Error("no announcement within timeout")), timeoutMs);
			wake = () => {
				if (announced.length <= before) return;
				clearTimeout(timer);
				wake = null;
				resolve(announced.at(-1) as string);
			};
		});
	return { manager, announced, next };
}

async function testExitIsAnnouncedWithOutput() {
	const { manager, next } = harness();
	const r = manager.start("echo hello-stdout; echo hello-stderr >&2; exit 3", { label: "check" });
	assert.ok(r.ok, "start should succeed");
	const job = (r as { job: Job }).job;

	const report = await next();
	assert.match(report, new RegExp(`\\[background job ${job.id}\\]`), "report names the job");
	assert.match(report, /exit 3/, "report carries the exit code");
	assert.match(report, /hello-stdout/, "report tails stdout");
	assert.match(report, /hello-stderr/, "report tails stderr");
	assert.equal(manager.get(job.id)?.exitCode, 3);
	assert.equal(manager.running().length, 0, "finished job is no longer running");
}

async function testKillReachesTheProcessTree() {
	const { manager, next } = harness();
	// Child of a child: only a process-group kill takes both down.
	const r = manager.start("sh -c 'sleep 60' & wait");
	assert.ok(r.ok);
	const job = (r as { job: Job }).job;
	assert.equal(manager.running().length, 1);

	const killed = manager.kill(job.id);
	assert.ok(killed.ok, "kill should be accepted");
	const report = await next();
	assert.match(report, /killed \(SIG/, "report says it was signalled");
	assert.equal(manager.running().length, 0);
	assert.equal(manager.kill(job.id).ok, false, "killing a finished job is an error");
}

async function testGuards() {
	const { manager } = harness();
	assert.equal(manager.start("   ").ok, false, "empty command rejected");
	assert.equal(manager.kill("nope1234").ok, false, "unknown id rejected");
}

function testHumanDuration() {
	assert.equal(humanDuration(0), "0s");
	assert.equal(humanDuration(45_000), "45s");
	assert.equal(humanDuration(125_000), "2m05s");
	assert.equal(humanDuration(3_725_000), "1h02m05s");
}

testHumanDuration();
await testGuards();
await testExitIsAnnouncedWithOutput();
await testKillReachesTheProcessTree();
console.log("bg-bash manager: all checks passed");
