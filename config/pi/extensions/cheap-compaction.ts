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
// prompt (measured: 9.1M of 17.3M chars on a real session), and a summary needs
// decisions and actions, not the chain of thought that produced them. Tool
// results are already capped at 2000 chars by pi's serializeConversation, so
// this is the one big lever left on compaction latency.
// ponytail: drops thinking entirely; truncate instead if summaries lose rationale.
export function stripThinking<T>(messages: T[]): T[] {
  return messages.map((m: any) => {
    if (m?.role !== "assistant" || !Array.isArray(m.content)) return m;
    const content = m.content.filter((b: any) => b?.type !== "thinking");
    return content.length === m.content.length ? m : { ...m, content };
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
        stripThinking(messages),
        model,
        preparation.settings.reserveTokens,
        auth.auth.apiKey,
        auth.auth.headers,
        signal,
        customInstructions,
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
