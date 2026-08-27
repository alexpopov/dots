import { type ExtensionAPI, isToolCallEventType } from "@earendil-works/pi-coding-agent";

// git-guard — block rewriting a commit MESSAGE via `git commit --amend`,
// while still allowing content-only amends.
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
// Set PI_GIT_AMEND_GUARD=0 to disable.

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
        "Blocked by git-guard: do NOT rewrite the commit message with `git commit --amend`. " +
        "Amending the message drops the `Differential Revision:` trailer, so the next submit " +
        "creates a brand-new diff instead of updating the existing one. " +
        "To change the title / summary / test plan, edit the diff with the `meta` CLI (updates " +
        "Phabricator in place and keeps the link). " +
        "To amend only the CONTENT of the last commit, use `git commit --amend --no-edit` " +
        "(leaves the message and trailer intact). " +
        "(Set PI_GIT_AMEND_GUARD=0 to disable this guard.)"
      );
    }
  }
  return null;
}

export default function (pi: ExtensionAPI) {
  if (process.env.PI_GIT_AMEND_GUARD === "0") return;

  pi.on("tool_call", async (event: any) => {
    if (!isToolCallEventType("bash", event)) return;
    const command = event.input?.command;
    if (typeof command !== "string") return;
    const reason = amendBlockReason(command);
    if (reason) return { block: true, reason };
  });
}
