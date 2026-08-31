import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { isToolCallEventType } from "@earendil-works/pi-coding-agent";

// SUBAGENT-ONLY search guard. In a subagent child (PI_AGENT_TEAM_CHILD=1), hard-
// block tree-walking code search in bash -- grep -r / rg / fd / find / git grep
// / meta-rg -- and redirect to the indexed MCP search (a14__/a16__search_files,
// auto-connected via PI_MCP_AUTOCONNECT from subagent.ts).
//
// Why: on an AOSP checkout these walkers -- or meta-rg's filesystem fallback
// when the UCS index is cold -- run for minutes and trip the subagent's silence
// watcher, so the child gets reaped having produced nothing (verified: an Opus
// subagent died on `grep -rln vros_device.mk device/meta/ vendor/meta/`). grep
// is deeply trained-in, so making it merely slow isn't enough: the model keeps
// reaching for it. Blocking it -- with the fast alternative already connected --
// is what makes it switch to the indexed search.
//
// Main-agent-unaffected: this returns immediately unless it's a subagent child.
// Non-recursive grep of a specific file is allowed; only the recursive walkers
// are blocked.

// ponytail: heuristic (command-position walkers), not a shell parser. A false
// positive just nudges the subagent to MCP search (fine); a false negative
// still hits the meta-rg-rewrite, and MCP is connected anyway. Good enough.
const WALKER =
  /(?:^|[|&;(]\s*)(?:sudo\s+|time\s+|xargs\s+)*(?:grep\b[^|&;]*?(?:\s-[a-zA-Z]*[rR][a-zA-Z]*\b|\s--recursive\b)|rg\b|fd\b|find\b|git\s+grep\b|meta-rg\b)/;

export function isTreeSearch(cmd: string): boolean {
  return WALKER.test(cmd);
}

const REASON =
  "Tree-walking search (grep -r / rg / fd / find / git grep / meta-rg) is disabled in " +
  "subagents -- on an AOSP checkout it walks the tree (or meta-rg falls back to a filesystem " +
  "scan when the index is cold), runs for minutes, and gets you silence-reaped with nothing. " +
  "Use the indexed MCP code search instead (already connected): a14__search_files for the " +
  "oculus-14.0 checkout, a16__search_files for oculus-16.0. Example: " +
  "a16__search_files({ pattern: \"crosvm_defaults\", engine: \"STRMATCH\", target_directories: [\"/\"] }). " +
  "For another repo run mcp_connect(\"mux\"). A plain non-recursive grep of a single known file is fine.";

export default function (pi: ExtensionAPI) {
  if (process.env.PI_AGENT_TEAM_CHILD !== "1") return; // main agent unaffected

  pi.on("tool_call", async (event: any) => {
    if (!isToolCallEventType("bash", event)) return;
    const cmd = String(event?.input?.command ?? "");
    if (!isTreeSearch(cmd)) return;
    return { block: true, reason: REASON };
  });
}
