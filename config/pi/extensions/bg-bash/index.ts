/**
 * bg-bash — background shell jobs for pi (a port of Claude Code's
 * `Bash(run_in_background: true)` + `TaskOutput` / `TaskStop`).
 *
 * pi ships no background bash on purpose ("build it as an extension" —
 * docs/usage.md). This is that extension: start a long command detached, get
 * an id back immediately, and let the *process exit* wake the agent instead of
 * the agent polling for it. On exit the job's report is pushed into the session
 * with `deliverAs: "followUp"` + `triggerTurn`, i.e. between turns, never
 * mid-response.
 *
 * Tools:  bash_background, bash_jobs, bash_output, bash_kill
 *
 * Rendering follows the house convention from tool-aggregator.ts /
 * subagent.ts: tool calls render nothing inline (the aggregator widget counts
 * them like any other tool), and the completion report is a custom message
 * that the LLM reads but that renders as *nothing* for a clean exit. Only
 * failures get a line, because a build that died silently is worth a line.
 *
 * Config (env, optional):
 *   PI_DISABLE_BG_BASH=1   don't register anything
 *   PI_BG_SHELL=/bin/zsh   shell used for `-c` (default /bin/bash)
 *   PI_BG_KEEP_ON_EXIT=1   leave jobs running when pi exits (default: kill them)
 *   PI_BG_SHOW_DONE=1      also render a one-line notice on successful exit
 *
 * ponytail: jobs are children of pi and die with it — no cross-restart resume.
 * Add a detached spawner + on-disk job registry if surviving `pi` exit matters.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { createManager, describeJob, type Job, jobStatus, tailFile } from "./manager.ts";

const MAX_OUTPUT_LINES = 500;
const MESSAGE_TYPE = "bg-bash";

// Opt out of the default boxed per-call renderer, exactly like subagent.ts.
const EMPTY_COMPONENT = { render: () => [], invalidate: () => {} };
const renderEmpty = () => EMPTY_COMPONENT;

function renderResultEmptyOrError(toolName: string) {
	return (result: any, _options: any, theme: any) => {
		if (!result.isError) return EMPTY_COMPONENT;
		const content = result.content;
		const text = Array.isArray(content)
			? content
					.filter((c: any) => c.type === "text")
					.map((c: any) => c.text)
					.join("\n")
			: String(content ?? "");
		return new Text(theme.fg("error", `${toolName} error: `) + (text || "(no detail)"), 0, 0);
	};
}

export default function (pi: ExtensionAPI) {
	if (process.env.PI_DISABLE_BG_BASH === "1") return;

	const manager = createManager({
		announce: (report, job) => {
			// A custom message: the LLM gets the full report, the human gets
			// whatever registerMessageRenderer below decides to show (usually
			// nothing). triggerTurn wakes the agent when it is idle; followUp
			// holds the report until it is between turns when it is busy.
			try {
				pi.sendMessage(
					{
						customType: MESSAGE_TYPE,
						content: report,
						display: true,
						details: { id: job.id, ok: job.exitCode === 0 && !job.signal, status: jobStatus(job), command: job.command },
					},
					{ deliverAs: "followUp", triggerTurn: true },
				);
			} catch {
				/* session gone */
			}
		},
	});

	pi.registerMessageRenderer(MESSAGE_TYPE, (message: any, _options: any, theme: any) => {
		const d = message.details as { ok?: boolean; id?: string; status?: string; command?: string } | undefined;
		if (d?.ok !== false) {
			if (process.env.PI_BG_SHOW_DONE !== "1") return EMPTY_COMPONENT;
			return new Text(theme.fg("dim", `✓ background ${d?.id ?? ""} ${d?.status ?? ""}`), 0, 0);
		}
		const cmd = (d.command ?? "").split("\n")[0].slice(0, 80);
		return new Text(theme.fg("error", `✗ background ${d.id} ${d.status}: `) + cmd, 0, 0);
	});

	pi.on("session_shutdown", async () => {
		// Default matches Claude Code: jobs are session-scoped, so quitting pi
		// doesn't leave an orphan build burning a devserver. Set
		// PI_BG_KEEP_ON_EXIT=1 to let long builds outlive the session instead
		// (you lose the exit notification — check the log file by hand).
		if (process.env.PI_BG_KEEP_ON_EXIT !== "1") manager.killAll();
	});

	const text = (t: string, details: Record<string, unknown> = {}) => ({ content: [{ type: "text" as const, text: t }], details });
	const quiet = (toolName: string) => ({
		renderShell: "self" as const,
		renderCall: renderEmpty,
		renderResult: renderResultEmptyOrError(toolName),
	});

	pi.registerTool({
		name: "bash_background",
		label: "Run in background",
		description:
			"Start a shell command detached and return immediately with an 8-char job id. The command keeps running across turns; when it exits you are automatically notified with its exit code and the tail of its output. Use for anything long-running (builds, test suites, syncs, flashes, waits). Read output any time with bash_output, stop it with bash_kill.",
		promptGuidelines: [
			"Prefer bash_background over a foreground bash call for any command expected to take more than a minute or two.",
			"After starting a job, do NOT poll it and do NOT sleep waiting for it — the exit notification wakes you. Do other work, or end the turn.",
			'If a remote job only exposes a status command, keep the polling in the shell so it costs no context: bash_background("until <status-check>; do sleep 70; done").',
			"Chain the follow-up into the command itself when it is cheap (e.g. `<build> && <smoke test>`) rather than waking up twice.",
			"The job id, pid, and log path are for you, not the user — don't relay them unless asked.",
		],
		parameters: Type.Object({
			command: Type.String({ description: "Shell command to run (executed with `$SHELL -c`)." }),
			cwd: Type.Optional(Type.String({ description: "Working directory. Defaults to the session cwd." })),
			label: Type.Optional(Type.String({ description: "Short human label shown in bash_jobs, e.g. 'aosp stanley build'." })),
		}),
		async execute(_id, params) {
			const p = params as { command: string; cwd?: string; label?: string };
			const r = manager.start(p.command, { cwd: p.cwd, label: p.label });
			if (!r.ok) return text(`Error: ${r.error}`, { error: r.error });
			return text(
				`Started background job ${r.job.id} (pid ${r.job.pid}).\nlog: ${r.job.log}\nYou will be notified when it exits — do not poll it.`,
				{ job: { id: r.job.id, pid: r.job.pid, log: r.job.log } },
			);
		},
		...quiet("bash_background"),
	});

	pi.registerTool({
		name: "bash_jobs",
		label: "List background jobs",
		description: "List background jobs started this session with their id, status, elapsed time, and command.",
		parameters: Type.Object({}),
		async execute() {
			const jobs = manager.list();
			return text(jobs.length ? jobs.map(describeJob).join("\n") : "No background jobs.", { jobs });
		},
		...quiet("bash_jobs"),
	});

	pi.registerTool({
		name: "bash_output",
		label: "Read background job output",
		description:
			"Read the tail of a background job's output. Works while it is still running. Only use this when you actually need the output — completion alone is reported to you automatically.",
		parameters: Type.Object({
			id: Type.String({ description: "Job id from bash_background." }),
			lines: Type.Optional(Type.Number({ description: `Lines from the end (default 50, max ${MAX_OUTPUT_LINES}).` })),
		}),
		async execute(_id, params) {
			const p = params as { id: string; lines?: number };
			const job: Job | undefined = manager.get(p.id);
			if (!job) return text(`Error: no job ${p.id}`, { error: "not found" });
			const lines = Math.min(Math.max(1, Math.floor(p.lines ?? 50)), MAX_OUTPUT_LINES);
			return text(`[${job.id}] ${jobStatus(job)} — ${job.log}\n${tailFile(job.log, lines, 20_000)}`, { status: jobStatus(job) });
		},
		...quiet("bash_output"),
	});

	pi.registerTool({
		name: "bash_kill",
		label: "Stop background job",
		description: "Stop a running background job (SIGTERM to its process group, SIGKILL after 5s).",
		parameters: Type.Object({ id: Type.String({ description: "Job id from bash_background." }) }),
		async execute(_id, params) {
			const p = params as { id: string };
			const r = manager.kill(p.id);
			return text(r.ok ? `Sent SIGTERM to job ${p.id}` : `Error: ${r.error}`, { ok: r.ok });
		},
		...quiet("bash_kill"),
	});
}
