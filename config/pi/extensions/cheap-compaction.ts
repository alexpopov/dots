import {
  generateSummaryWithUsage,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";

// Compaction is one big uncached summarization call; running it on the session
// model (Opus) is slow and pointless. Same prompt as built-in compaction
// (generateSummaryWithUsage), cheaper/faster model. Needs a 1M window —
// haiku-4-5 (200K) cannot hold the transcript.
// Measured, 200k-token transcript, wall clock:
//   gemini-3-flash-preview 12.9s | sonnet-5 17.8/23.5s | gpt-5.4 21.4s | opus-5 21.7/32.4s
const PROVIDER = process.env.PI_COMPACTION_PROVIDER ?? "google";
const MODEL = process.env.PI_COMPACTION_MODEL ?? "gemini-3-flash-preview";

// Thinking blocks are ~half of what gets serialized into the summarization
// prompt (measured: 9.1M of 17.3M chars on a real session; 3240 blocks, median
// 1686 chars, max 25875). Truncate rather than drop, and keep the TAIL: a
// thinking block opens with hypotheses and closes with the verdict, the
// rejected alternative and the next action — which is what a checkpoint is for.
// Blind A/B: 6 summaries of one 500k-token span (thinking full / none / first
// 1000 / last 1000), judged by opus-5 and gpt-5.6-sol without knowing the
// variants. Both ranked last-1000 #1; both ranked a full-thinking run last.
// Same truncation idiom pi uses for tool results (capped at 2000 chars).
const THINKING_CAP = Number(process.env.PI_COMPACTION_THINKING_CAP ?? 1000);

// Blind-judged against claude-sonnet-5 on the same payload: sonnet wrote 4x more
// (1800 vs 460 words, 50 vs 10 identifiers) and both judges ranked it above
// flash — but it took 83s vs 14s. Flash's real defect was not brevity, it was
// reporting the session goal ('achieve boot_completed') without ever saying the
// milestone was REACHED, plus dropping the parent task and the known-expected
// build failure. These instructions fix that at the same length and latency:
// identifiers 9-10 -> 24-32 per summary, and all of boot_completed-as-done,
// T270212415, CheckAbOtaImages, P2468969799, job 81582a3b now survive both runs.
const RESUMABILITY_FOCUS =
  "Prioritise resumable state over history. Always include, when present: " +
  "(a) state transitions actually reached (e.g. \"booted\", \"landed\", \"test passes\"), not just what was attempted; " +
  "(b) work in flight — running job IDs, uncommitted edits and which file/repo they are in, decisions awaiting the user; " +
  "(c) known-expected failures and red herrings, so the next agent does not re-debug them; " +
  "(d) every diff (D…), task (T…) and paste (P…) identifier, file path, device serial and exact error string still relevant; " +
  "(e) pointers to durable records rather than reproducing their contents. " +
  "Do not spend words on questions already answered, mistakes already corrected, or restating the same item in several sections.";

export function capThinking<T>(messages: T[], cap = THINKING_CAP): T[] {
  if (!(cap >= 0)) return messages; // NaN or negative => leave thinking intact
  return messages.map((m: any) => {
    if (m?.role !== "assistant" || !Array.isArray(m.content)) return m;
    let changed = false;
    const content = m.content.map((b: any) => {
      if (b?.type !== "thinking" || typeof b.thinking !== "string") return b;
      if (b.thinking.length <= cap) return b;
      changed = true;
      return { ...b, thinking: `[... ${b.thinking.length - cap} earlier characters truncated]\n${b.thinking.slice(-cap)}` };
    });
    return changed ? { ...m, content } : m;
  });
}

export default function (pi: ExtensionAPI) {
  pi.on("session_before_compact", async (event, ctx) => {
    const { preparation, customInstructions, signal } = event;
    const messages = [
      ...preparation.messagesToSummarize,
      ...preparation.turnPrefixMessages,
    ];
    if (messages.length === 0) return; // let the default path handle it

    const model = ctx.modelRegistry.find(PROVIDER, MODEL);
    const auth = model
      ? await ctx.modelRegistry.getProviderAuth(PROVIDER)
      : undefined;
    if (!model || !auth) return; // fall back to built-in compaction

    try {
      const { text, usage } = await generateSummaryWithUsage(
        capThinking(messages),
        model,
        preparation.settings.reserveTokens,
        auth.auth.apiKey,
        auth.auth.headers,
        signal,
        customInstructions ?? RESUMABILITY_FOCUS,
        preparation.previousSummary,
        "off",
        undefined,
        auth.env,
      );
      return {
        compaction: {
          summary: text,
          firstKeptEntryId: preparation.firstKeptEntryId,
          tokensBefore: preparation.tokensBefore,
          usage,
        },
      };
    } catch (e) {
      ctx.ui.notify(
        `Cheap compaction failed (${e instanceof Error ? e.message : String(e)}); using default model`,
        "warning",
      );
      return; // built-in compaction retries with the session model
    }
  });
}
