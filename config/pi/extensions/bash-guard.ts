import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// bash-guard — bash command guards for agent footguns:
//   1. Block rewriting a commit MESSAGE via `git commit --amend` (drops the
//      `Differential Revision:` trailer -> next submit creates a duplicate diff).
//   2. Block self-matching `pgrep -f`, `pkill -f`, and `ps | grep` patterns
//      that lack the `[x]` bracket idiom (pi runs `/bin/bash -c "<cmd>"`, whose
//      own argv contains the literal pattern -> `pgrep -f` always reports
//      running and `pkill -f` kills the agent's own subshell with exit 137).
//
// Rationale: when the agent amends the commit MESSAGE, it tends to drop the
// `Differential Revision:` trailer. With that trailer gone, the next
// `jf submit` / `arc diff` creates a BRAND-NEW diff on Phabricator instead of
// updating the existing one — silently orphaning the original. So the policy
// is: edit a diff's title / summary / test plan via the `meta` CLI (updates
// Phabricator in place, keeps the link), never via `git commit --amend`.
// Amending only the CONTENT is fine because it leaves the message — and thus
// the trailer — intact.
//   git commit --amend --no-edit     → ALLOWED (content amend, message kept)
//   git commit --amend               → BLOCKED (opens editor = message change)
//   git commit --amend -m "..."      → BLOCKED (new message; drops trailer)
//   git commit --amend -F file       → BLOCKED (message from file)
//   git commit --amend -C <commit>   → BLOCKED (reuse another message)
//
// Implemented via the `tool_call` hook, which fires before a tool runs and
// can veto it with { block, reason }. Applies to the bash tool only; hg is
// untouched (that workflow allows `hg amend`).
//
// Active in child sessions (subagents / side-kicks) too — deliberately NOT
// recursion-guarded, since the point is to enforce the rule everywhere.
//
// Set PI_BASH_GUARD=0 to disable.

// Returns a block reason, or null to allow. Pure + unit-tested logic:
// scan each shell segment; only a real `git ... commit ... --amend` invocation
// is considered, and it's allowed only when --no-edit is present and no
// message-supplying flag contradicts it.
export function amendBlockReason(command: string): string | null {
  // Over-split on shell operators (;, newline, |, &). Over-splitting is safe:
  // we only need each candidate git invocation to land in its own segment.
  for (const raw of command.split(/[;\n|&]+/)) {
    const seg = raw.trim();
    // `git` must be the command word (allow leading VAR=val and a path prefix),
    // so `echo "git commit --amend"` is not matched.
    if (!/^(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:\S*\/)?git\b/.test(seg)) continue;
    if (!/\bcommit\b/.test(seg)) continue;
    if (!/\s--amend\b/.test(seg)) continue;

    const hasNoEdit = /(?:^|\s)--no-edit\b/.test(seg);
    const hasMessageFlag =
      /(?:^|\s)-[a-z]*m\b/i.test(seg) ||            // -m, -am, ...
      /(?:^|\s)--message\b/.test(seg) ||
      /(?:^|\s)(?:-F|--file|--reuse-message|--reedit-message|-C)\b/.test(seg);

    if (!hasNoEdit || hasMessageFlag) {
      return (
        "Blocked by bash-guard: do NOT rewrite the commit message with `git commit --amend`. " +
        "Amending the message drops the `Differential Revision:` trailer, so the next submit " +
        "creates a brand-new diff instead of updating the existing one. " +
        "To change the title / summary / test plan, edit the diff with the `meta` CLI (updates " +
        "Phabricator in place and keeps the link). " +
        "To amend only the CONTENT of the last commit, use `git commit --amend --no-edit` " +
        "(leaves the message and trailer intact). " +
        "(Set PI_BASH_GUARD=0 to disable this guard.)"
      );
    }
  }
  return null;
}

// Returns a block reason when `pgrep -f`, `pkill -f`, or `ps | grep` uses a
// literal pattern that will match the parent `/bin/bash -c "<command>"` wrapper
// spawned by pi. Using a bracket class (`[f]oo`) prevents the regex from
// matching its own source text in `/bin/bash -c`.
export function procSelfMatchBlockReason(command: string): string | null {
  // Command-position prefix: env assignments / wrappers, plus shell control
  // openers. The openers matter — the recurring agent footgun is a wait loop
  // (`while pgrep -f "foo"; do sleep 60; done`), where `while`/`until`/`do`/
  // `if` precedes the pgrep and a start-anchored match alone sails past it,
  // so the loop self-matches its own `bash -c` argv and never exits.
  const cmdPrefix =
    /^(?:(?:[A-Za-z_][A-Za-z0-9_]*=\S*|sudo|timeout\s+\S+|time|command|while|until|if|elif|then|do|else|!|\(|\{|\$\()\s*)*(?:\S*\/)?/;

  for (const raw of command.split(/[;\n|&]+/)) {
    const seg = raw.trim();
    const m = new RegExp(`^${cmdPrefix.source}(pgrep|pkill)\\b(.*)$`).exec(seg);
    if (!m) continue;
    const [, tool, rest] = m;
    const hasFullFlag = /(?:^|\s)(?:-[a-zA-Z0-9]*f[a-zA-Z0-9]*|--full)\b/.test(rest);
    const hasScopedParent = /(?:^|\s)(?:-[a-zA-Z0-9]*P|--parent)\b/.test(rest);
    if (hasFullFlag && !hasScopedParent && !/\[[^\]\s]+\]/.test(rest)) {
      return (
        `Blocked by bash-guard: \`${tool} -f\` without a \`[x]\` bracket pattern matches the ` +
        `parent \`/bin/bash -c "..."\` shell that pi spawned to run this command ` +
        (tool === "pkill"
          ? "(killing your own subshell with exit 137). "
          : "(always matching itself and reporting the process as running even after it exited). ") +
        `Use a character class on one literal character so the regex does not match its own command line, ` +
        `e.g. \`${tool} -f "[f]oo"\` instead of \`${tool} -f "foo"\` (or drop \`-f\` if matching the 15-char process name is enough).`
      );
    }
  }

  // Also check `ps ... | grep <pat>` pipelines without `[x]` or `grep -v`.
  for (const stmt of command.split(/[;\n&]+/)) {
    const stages = stmt.split("|").map((s) => s.trim());
    if (stages.length < 2) continue;
    const psIdx = stages.findIndex((s) => new RegExp(`^${cmdPrefix.source}ps\\b`).test(s));
    if (psIdx === -1) continue;
    const tail = stages.slice(psIdx + 1);
    const hasGrepV = tail.some((s) => /\b(?:e?grep)\b.*(?:^|\s)-[a-zA-Z]*v/.test(s));
    if (hasGrepV) continue;
    for (const stage of tail) {
      const gm = new RegExp(`^${cmdPrefix.source}(e?grep)\\b(.*)$`).exec(stage);
      if (!gm) continue;
      if (!/\[[^\]\s]+\]/.test(gm[2])) {
        return (
          "Blocked by bash-guard: `ps ... | grep <pat>` without a `[x]` bracket pattern matches " +
          "both `grep` itself and the parent `/bin/bash -c` command line. " +
          "Use `ps ... | grep \"[f]oo\"` or `pgrep -af \"[f]oo\"`."
        );
      }
    }
  }

  return null;
}

export default function (pi: ExtensionAPI) {
  if (process.env.PI_BASH_GUARD === "0") return;

  pi.on("tool_call", async (event: any) => {
    if (event.toolName !== "bash" && event.toolName !== "bash_background") return;
    const command = event.input?.command;
    if (typeof command !== "string") return;
    const reason = amendBlockReason(command) ?? procSelfMatchBlockReason(command);
    if (reason) return { block: true, reason };
  });
}

if (process.argv[1]?.endsWith("bash-guard.ts")) {
  const check = (cond: unknown, msg: string) => {
    if (!cond) throw new Error(`Assertion failed: ${msg}`);
  };
  // Real self-matching commands from session transcripts:
  check(procSelfMatchBlockReason(`pkill -9 -f "platform-tools/fastboot" 2>/dev/null; sleep 2`), "pkill -f");
  check(procSelfMatchBlockReason(`date +%H:%M:%S; pgrep -af "stanley-mainline" | head -2`), "pgrep -af");
  check(procSelfMatchBlockReason(`pgrep -f "lunch stanley-mainline" >/dev/null && echo RUNNING || echo DONE`), "pgrep -f");
  check(procSelfMatchBlockReason(`ps aux | grep "stanley-mainline" | head -3`), "ps | grep");
  // Wait-loop shapes (session 01a17c8b: `while pgrep -f` self-matched for 17h):
  check(procSelfMatchBlockReason(`while pgrep -f "soong_ui --build-mode" >/dev/null; do sleep 60; done; ./run_tests.sh`), "while pgrep -f");
  check(procSelfMatchBlockReason(`until pgrep -f "ninja" >/dev/null; do sleep 5; done`), "until pgrep -f");
  check(procSelfMatchBlockReason(`if pgrep -f "soong_ui"; then echo busy; fi`), "if pgrep -f");
  check(procSelfMatchBlockReason(`while true; do pgrep -f "soong_ui" || break; sleep 5; done`), "do pgrep -f");
  check(procSelfMatchBlockReason(`(pgrep -f "soong_ui") && echo busy`), "(pgrep -f");
  check(procSelfMatchBlockReason(`while pgrep -f "[s]oong_ui --build-mode" >/dev/null; do sleep 60; done`) === null, "while pgrep [x]");
  // Safe / bracketed forms:
  check(procSelfMatchBlockReason(`pgrep -f "lunch stanley-main[user]debug" >/dev/null && echo RUNNING || echo DONE`) === null, "pgrep [x]");
  check(procSelfMatchBlockReason(`pkill -9 -f "[p]latform-tools/fastboot"`) === null, "pkill [x]");
  check(procSelfMatchBlockReason(`ps aux | grep "[c]lang\\|[n]inja\\|[r]be" | head -3`) === null, "ps | grep [x]");
  check(procSelfMatchBlockReason(`ps aux | grep fastboot | grep -v grep`) === null, "grep -v grep");
  check(procSelfMatchBlockReason(`pgrep ninja`) === null, "pgrep no -f");
  check(procSelfMatchBlockReason(`pgrep -P 12345 -f foo`) === null, "pgrep -P");
  check(amendBlockReason(`git commit --amend --no-edit`) === null, "amend --no-edit");
  check(amendBlockReason(`git commit --amend -m "bad"`), "amend -m");
  console.log("bash-guard: all checks passed");
}
