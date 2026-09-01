import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { isToolCallEventType } from "@earendil-works/pi-coding-agent";

// Search guard for ALL agents (main + subagents). Hard-block tree-walking code
// search in bash -- grep -r / rg / fd / find / git grep / meta-rg -- and
// redirect to the indexed MCP search (a14__/a16__search_files, auto-connected
// in subagents via PI_MCP_AUTOCONNECT from subagent.ts).
//
// Why: on an AOSP checkout these walkers -- or meta-rg's filesystem fallback
// when the UCS index is cold -- run for minutes. In a subagent that trips the
// silence watcher and the child gets reaped having produced nothing (verified:
// an Opus subagent died on `grep -rln vros_device.mk device/meta/ vendor/meta/`).
// In the main agent it just burns minutes. grep is deeply trained-in, so making
// it merely slow isn't enough: the model keeps reaching for it. Blocking it --
// with the fast alternative available -- is what makes it switch.
//
// Non-recursive grep of a specific file is allowed; only the walkers are.
// No escape hatch, by design.

// Matches a walker anywhere in the command, NOT only at a command position.
// The old version anchored on command position with a hardcoded list of wrapper
// words (sudo/time/xargs), so anything it hadn't heard of walked straight
// through -- `timeout 300 grep -rn ... .` was the one that got caught in the
// wild. Matching the token anywhere costs a few false positives and has no
// false-negative class.
//
// The lookbehind keeps path components from matching (`/proc/self/fd`,
// `~/dots/find.txt`). The `[^|&;]*?` keeps a recursive flag from binding to a
// grep in a different pipeline stage (`grep foo file | sort -r` is allowed).
// Long flags are matched explicitly so `--color` isn't read as a short -r.
//
// ponytail: regex, not a shell parser, so it can't see quoting --
// `echo "grep -r foo"` is a false positive. Costs one reworded echo; a parser
// costs a dependency this file cannot safely have (extensions only get typebox
// / @earendil-works / node builtins without a local `npm install`, and a
// missing install would silently unload the guard). Upgrade to a lexer only if
// the false positives ever actually bite.
const WALKER =
  /(?<![\w\/.-])(?:meta-rg|rg|fd|find)\b|\bgit\s+grep\b|\bgrep\b[^|&;]*?(?:\s-[a-zA-Z]*[rR]|\s--(?:dereference-)?recursive\b)/;

export function isTreeSearch(cmd: string): boolean {
  return WALKER.test(cmd);
}

const REASON =
  "Tree-walking search (grep -r / rg / fd / find / git grep / meta-rg) is disabled -- on an " +
  "AOSP checkout it walks the tree (or meta-rg falls back to a filesystem scan when the index " +
  "is cold) and runs for minutes. " +
  "Use the indexed MCP code search instead: a14__search_files for the " +
  "oculus-14.0 checkout, a16__search_files for oculus-16.0. Example: " +
  "a16__search_files({ pattern: \"crosvm_defaults\", engine: \"STRMATCH\", target_directories: [\"/\"] }). " +
  "For another repo run mcp_connect(\"mux\"). A plain non-recursive grep of a single known file is fine.";

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event: any) => {
    if (!isToolCallEventType("bash", event)) return;
    const cmd = String(event?.input?.command ?? "");
    if (!isTreeSearch(cmd)) return;
    return { block: true, reason: REASON };
  });
}
