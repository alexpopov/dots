/**
 * bg-bash/manager.ts — process bookkeeping for background bash jobs.
 *
 * No pi imports, so it runs (and is testable) under
 * `node --experimental-strip-types`.
 *
 * Self-check:  node --experimental-strip-types manager.test.ts
 */

import { type ChildProcess, spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

const MAX_JOBS = 20;
const TAIL_LINES = 20;
const TAIL_BYTES = 64 * 1024; // never slurp a whole build log into memory
const TAIL_CHARS = 2_000;
const KILL_GRACE_MS = 5_000;
const CMD_ECHO_CHARS = 300;
const SHELL = process.env.PI_BG_SHELL || "/bin/bash";

export interface Job {
	id: string;
	command: string;
	cwd: string;
	label?: string;
	log: string;
	pid?: number;
	startedAt: number;
	endedAt?: number;
	exitCode?: number | null;
	signal?: NodeJS.Signals | null;
	killed: boolean;
}

export interface ManagerHooks {
	/** Push a completion report into the agent's context (wakes it if idle). */
	announce: (report: string, job: Job) => void;
}

export function jobLogDir(): string {
	// pid-scoped: jobs die with pi, so their logs belong to this run.
	return path.join(os.tmpdir(), `pi-bg-${process.pid}`);
}

export function humanDuration(ms: number): string {
	const total = Math.max(0, Math.round(ms / 1000));
	const h = Math.floor(total / 3600);
	const m = Math.floor((total % 3600) / 60);
	const s = total % 60;
	if (h) return `${h}h${String(m).padStart(2, "0")}m${String(s).padStart(2, "0")}s`;
	if (m) return `${m}m${String(s).padStart(2, "0")}s`;
	return `${s}s`;
}

export function jobStatus(job: Job): string {
	if (job.endedAt === undefined) return "running";
	if (job.signal) return `killed (${job.signal})`;
	return `exit ${job.exitCode ?? "?"}`;
}

/** Last `maxLines` lines of a file, reading only the trailing TAIL_BYTES. */
export function tailFile(file: string, maxLines = TAIL_LINES, maxChars = TAIL_CHARS): string {
	let fd: number | undefined;
	try {
		fd = fs.openSync(file, "r");
		const size = fs.fstatSync(fd).size;
		if (size === 0) return "(no output)";
		const start = Math.max(0, size - TAIL_BYTES);
		const buf = Buffer.alloc(size - start);
		fs.readSync(fd, buf, 0, buf.length, start);
		let text = buf.toString("utf8");
		if (start > 0) text = text.slice(text.indexOf("\n") + 1); // drop the partial first line
		const lines = text.split("\n");
		if (lines.at(-1) === "") lines.pop();
		let out = lines.slice(-maxLines).join("\n");
		if (out.length > maxChars) out = `…${out.slice(-maxChars)}`;
		return out || "(no output)";
	} catch (err) {
		return `(no output: ${(err as Error).message})`;
	} finally {
		if (fd !== undefined) fs.closeSync(fd);
	}
}

export function describeJob(job: Job): string {
	const dur = humanDuration((job.endedAt ?? Date.now()) - job.startedAt);
	const cmd = job.command.length > CMD_ECHO_CHARS ? `${job.command.slice(0, CMD_ECHO_CHARS)}…` : job.command;
	return `${job.id}  ${jobStatus(job).padEnd(14)} ${dur.padStart(8)}  ${job.label ? `[${job.label}] ` : ""}${cmd}`;
}

export function createManager(hooks: ManagerHooks) {
	const jobs = new Map<string, Job>();
	const logDir = jobLogDir();

	const running = (): Job[] => [...jobs.values()].filter((j) => j.endedAt === undefined);

	const report = (job: Job): string =>
		[
			`[background job ${job.id}] ${jobStatus(job)} after ${humanDuration((job.endedAt ?? Date.now()) - job.startedAt)}`,
			`command: ${job.command.length > CMD_ECHO_CHARS ? `${job.command.slice(0, CMD_ECHO_CHARS)}…` : job.command}`,
			`cwd: ${job.cwd}`,
			`log: ${job.log}`,
			"last output:",
			tailFile(job.log),
		].join("\n");

	const signalTree = (job: Job, signal: NodeJS.Signals): void => {
		if (!job.pid) return;
		try {
			process.kill(-job.pid, signal); // negative pid = whole process group (spawned detached)
		} catch {
			try {
				process.kill(job.pid, signal);
			} catch {
				/* already gone */
			}
		}
	};

	const start = (command: string, opts: { cwd?: string; label?: string } = {}) => {
		if (!command?.trim()) return { ok: false as const, error: "command is required" };
		if (running().length >= MAX_JOBS) return { ok: false as const, error: `too many running jobs (max ${MAX_JOBS})` };

		const id = randomUUID().slice(0, 8);
		fs.mkdirSync(logDir, { recursive: true });
		const log = path.join(logDir, `${id}.log`);
		const cwd = opts.cwd || process.cwd();
		const fd = fs.openSync(log, "a");
		let child: ChildProcess;
		try {
			child = spawn(SHELL, ["-c", command], {
				cwd,
				env: process.env,
				stdio: ["ignore", fd, fd],
				detached: true,
			});
		} catch (err) {
			fs.closeSync(fd);
			return { ok: false as const, error: (err as Error).message };
		}
		fs.closeSync(fd); // the child dup'd it

		const job: Job = { id, command, cwd, label: opts.label, log, pid: child.pid, startedAt: Date.now(), killed: false };
		jobs.set(id, job);

		const finish = (exitCode: number | null, signal: NodeJS.Signals | null): void => {
			if (job.endedAt !== undefined) return; // exit + error can both fire
			job.endedAt = Date.now();
			job.exitCode = exitCode;
			job.signal = signal;
			hooks.announce(report(job), job);
		};
		child.on("exit", finish);
		child.on("error", (err) => {
			try {
				fs.appendFileSync(log, `\n[bg-bash] spawn error: ${err.message}\n`);
			} catch {
				/* best effort */
			}
			finish(null, null);
		});
		return { ok: true as const, job };
	};

	const kill = (id: string) => {
		const job = jobs.get(id);
		if (!job) return { ok: false as const, error: `no job ${id}` };
		if (job.endedAt !== undefined) return { ok: false as const, error: `job ${id} already finished (${jobStatus(job)})` };
		job.killed = true;
		signalTree(job, "SIGTERM");
		const t = setTimeout(() => {
			if (job.endedAt === undefined) signalTree(job, "SIGKILL");
		}, KILL_GRACE_MS);
		(t as unknown as { unref?: () => void }).unref?.();
		return { ok: true as const, job };
	};

	return {
		start,
		kill,
		get: (id: string) => jobs.get(id),
		list: (): Job[] => [...jobs.values()],
		running,
		killAll: (): number => {
			const live = running();
			for (const j of live) {
				j.killed = true;
				signalTree(j, "SIGTERM");
			}
			return live.length;
		},
		logDir,
	};
}
