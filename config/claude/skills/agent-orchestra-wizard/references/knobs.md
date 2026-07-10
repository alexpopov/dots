# Knob catalog

Every per-project decision the wizard tunes. The spine (autonomy contract, model
routing, delegation protocol, two-verifier gate, single-source-of-truth rule,
mechanical success) is invariant — only these knobs change.

| # | Knob | Question | Options | Changes |
|---|------|----------|---------|---------|
| 1 | **Placement** | Can you commit files to the repo root? | in-repo · external-workspace (symlink) | where CLAUDE.md/MANIFESTO/tracker are written; launch dir |
| 2 | **Golden rule** | The one architectural law agents must never break | free text | `CLAUDE.md` top + every delegation brief |
| 3 | **Tracker** | Where is the ONE place work is recorded? | GitHub Issues · Phabricator/Tasks · Things · in-repo TASKS.md · Notion | tracker line in CLAUDE.md + MANIFESTO; seed action |
| 4 | **Landing policy** | How does work land? | commit-to-branch · PR ≤ N · Phab diff | MANIFESTO landing section; never auto-merge |
| 5 | **Parallelism** | Do you delegate to concurrent agents here? | yes · no | whether delegation-brief + two-verifier are active |
| 6 | **Worktrees** | Isolated checkout per delegate? | on · off (AOSP unsupported; Unity costly) | isolation line; point to project worktree skill if any |
| 7 | **Delegate tooling** | Which tools may delegates use? | tool list + caveats | delegation-brief TOOLING RULE |
| 8 | **Success check** | How does an agent prove pass/fail? | test+baseline · build gate · headless sentinel · lint | CLAUDE.md "verify success"; canary steps |
| 9 | **Persona** | Enforce anti-overengineering? | off · on+loose · on+strict | persona hooks; strictness text |
| 10 | **Memory** | Where do durable decisions live? | Claude file-memory · in-repo docs/decisions · PARA | CLAUDE.md memory line |
| 11 | **Model routing** | task → model → effort, + what earns `max` | table | MANIFESTO routing table |
| 12 | **Greenfield** | Is this from zero? | yes → define-the-epic pass first · no | Step 10; seeds tracker |

## Defaults by detected stack

- **Empty dir** → greenfield=yes, tracker=in-repo TASKS.md, placement=in-repo.
- **Unity project** (`ProjectSettings/`) → worktrees=off (or point to existing
  skill), success=EditMode tests, persona=off/loose.
- **AOSP** (`Android.bp`/`build/soong`) → placement=external-workspace,
  worktrees=off, persona=on+strict.
- **GitHub repo** → tracker=GitHub Issues, landing=PR ≤ N.
- **Renders anything** (game, shader, UI) → success should include a headless
  self-capture sentinel; prefer it over an integration MCP.
