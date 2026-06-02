import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { spawn } from "node:child_process";

export default function (pi: ExtensionAPI) {
  // (A) Recursion guard.
  // When the LLM calls our `subagent` tool, we spawn `pi -p ...` with
  // PI_AGENT_TEAM_CHILD=1. The child loads this file too — but the guard
  // makes it return before registering the tool, so the child can't call
  // itself. One env var, one early-return.
  if (process.env.PI_AGENT_TEAM_CHILD === "1") return;

  pi.registerTool({
    name: "subagent",
    label: "Subagent",
    description:
      "Spawn a fresh pi subprocess to handle a focused subtask. " +
      "Returns the subagent's final answer as text. Use for work that " +
      "would pollute the main context, or for parallelizable chunks.",

    // (B) Parameters schema. typebox builds the JSON Schema the LLM sees;
    // pi validates input against it before calling execute(). If the LLM
    // sends a malformed call, you never see it.
    parameters: Type.Object({
      prompt: Type.String({
        description: "Task description handed to the subagent verbatim.",
      }),
    }),

    // (C) The implementation. Signature is fixed by pi:
    //   - toolCallId: opaque id, useful for logging/correlation
    //   - params:     validated against `parameters`
    //   - signal:     fires when the user hits Esc (or the parent aborts)
    //   - onUpdate:   stream partial results back to the TUI mid-execution
    //   - ctx:        ExtensionContext (cwd, sessionManager, ui, etc.)
    async execute(toolCallId, params, signal, onUpdate, ctx) {
      // (D) Spawn pi non-interactively. `-p` = print mode: process the
      // prompt, write the final answer to stdout, exit. No TUI.
      const child = spawn("pi", ["-p", params.prompt], {
        env: { ...process.env, PI_AGENT_TEAM_CHILD: "1" },
        stdio: ["ignore", "pipe", "pipe"],
      });

      // (E) Forward parent abort to the child.
      // pi passes us `signal` for exactly this. Without forwarding, hitting
      // Esc in the parent would leave the child running.
      const onAbort = () => child.kill("SIGTERM");
      signal?.addEventListener("abort", onAbort);

      // (F) Stream output. Collect stdout as we go and call onUpdate so
      // the parent TUI shows progress instead of a frozen tool call.
      let stdout = "";
      let stderr = "";
      child.stdout.on("data", (chunk) => {
        stdout += chunk.toString();
        onUpdate?.({ content: [{ type: "text", text: stdout }] });
      });
      child.stderr.on("data", (chunk) => {
        stderr += chunk.toString();
      });

      // (G) Wait for exit. `close` fires after stdio is fully drained.
      const exitCode: number = await new Promise((resolve) => {
        child.on("close", (code) => resolve(code ?? -1));
      });
      signal?.removeEventListener("abort", onAbort);

      // (H) Return the result. `isError: true` lets the LLM see the
      // failure and decide whether to retry or give up.
      if (exitCode === 0) {
        return {
          content: [{ type: "text", text: stdout.trim() || "(empty)" }],
        };
      }
      return {
        content: [{
          type: "text",
          text: `Subagent failed (exit ${exitCode}).\nstderr:\n${stderr}\nstdout:\n${stdout}`,
        }],
        isError: true,
      };
    },
  });
}
