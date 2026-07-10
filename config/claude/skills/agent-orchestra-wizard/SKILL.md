---
name: agent-orchestra-wizard
description: >
  Install the agent operating framework into a project — a portable, tuneable
  version of Haydn's orchestrator+delegate system. Use when the user wants to
  "set up agent-orchestra-wizard", "onboard this project", "install the operating framework /
  constitution", "run the setup wizard", or bootstrap autonomous multi-agent work
  in a repo (existing OR greenfield). Interviews the project through a fixed set
  of KNOBS, then stamps out a tuned CLAUDE.md + MANIFESTO.md + tracker + optional
  persona hooks. Works for a long-running project (GitHub/Phabricator tracker,
  worktrees), a simple repo (in-repo TASKS.md, one orchestrator + Sonnet
  delegates), a read-only root like AOSP (external workspace + symlink), or a
  from-zero project (defines the epic first).
---

# agent-orchestra-wizard — the operating-framework install wizard

This skill turns the *description* of one developer's Claude Code setup into a
**generator**. Haydn's system has an invariant spine (how work flows) and a set
of per-project **knobs** (tracker, worktrees, persona, landing policy, …). You,
the agent running this wizard, interview the project through the knobs and stamp
out a tuned instance.

**Golden rule of this wizard: exactly ONE tracker and ONE success-check per
project, both recorded in writing where no future agent can be confused about
where to look.** If you finish the wizard and an agent could not answer "where
do I record work?" or "how do I prove I succeeded?" in one lookup, you failed.

Read `references/knobs.md` for the full knob catalog and `references/examples.md`
for four fully worked instantiations (InariRush, dots, AOSP-external, a
from-zero Metal screensaver) before you start — pattern-match against the closest
one.

---

## Procedure

Run these steps in order. Prefer `AskUserQuestion` for the knob decisions (one
question per genuine fork; pre-select the detected/recommended option first).
Batch related questions. Don't ask what you can detect.

### Step 0 — Detect the ground truth

From the current working directory, establish (with Bash/Read/Glob, don't guess):

- Is it a git repo? (`git rev-parse`) What's the default branch and remote host
  (github.com? a Phabricator/Gerrit remote? none)?
- Build system / stack: `package.json`, `*.csproj` + `ProjectSettings/` (Unity),
  `Android.bp`/`build/soong` (AOSP), `Cargo.toml`, `*.xcodeproj` + `*.metal`,
  `pyproject.toml`, or **empty dir → greenfield**.
- Does a `CLAUDE.md`, `MANIFESTO.md`, or a project skill (e.g. a worktree skill)
  already exist? Never clobber — amend or ask.
- Can you write to the root? (An AOSP checkout root is off-limits — see Step 1.)

Report a one-paragraph read of what you found, with your recommended knob
defaults, before asking anything.

### Step 1 — Placement (where the framework files live)

- **in-repo** (default): `CLAUDE.md`, `MANIFESTO.md`, and (if chosen) `TASKS.md`
  go in the repo root and are committed like normal.
- **external-workspace** (read-only / un-committable roots — AOSP, monorepos you
  can't add files to): create a sibling workspace dir the user launches `claude`
  from; put the constitution + tracker there; symlink the source in:
  ```bash
  mkdir -p "$WORKSPACE"                       # e.g. ~/aosp-agent
  ln -s "$SOURCE_ROOT" "$WORKSPACE/src"       # e.g. -> /path/to/android-16.0
  # CLAUDE.md / MANIFESTO.md / TASKS.md are written INTO $WORKSPACE
  ```
  Tell the user: **launch `claude` from `$WORKSPACE`**, refer to code via `src/…`
  or absolute paths, and never expect a CLAUDE.md inside the read-only root.

### Step 2 — Project identity + golden rule(s)

Interview for: one-sentence identity, the **golden rule** (the single
architectural/domain law agents must never break), and explicit **don'ts**.
Examples: InariRush → "game logic lives in a pure-C# core, engine is a thin
adapter"; AOSP → its layering/ownership rules; screensaver → "physically
accurate, Metal-only, no external deps." This becomes the top of `CLAUDE.md`.

### Step 3 — Tracker (the single source of truth) — REQUIRED

Pick exactly one backend and record its exact location:

| Backend | Where "the place" is | Seed action |
|---|---|---|
| GitHub Issues | `owner/repo` issues | note repo, verify `gh auth status` |
| Phabricator / work Tasks | task tool + project tag | note the tag/queue (Meta laptop later) |
| Things | a specific Things project/area | note its name |
| in-repo `TASKS.md` | file at repo/workspace root | stamp `templates/TASKS.md` |
| Notion | a specific database/page | note the URL/ID |

Write the chosen location into BOTH `CLAUDE.md` and `MANIFESTO.md`, verbatim and
identical. "Done = the tracker is updated" is a hard rule and it's the
orchestrator's job, not the delegate's.

### Step 4 — Landing policy

Default is **never auto-merge to main.** Pick how work lands: commit-to-branch
only (dots-style) · open a PR ≤ N files/lines (GitHub) · Phabricator diff
(Meta). Record the size ceiling if any.

### Step 5 — Delegation & isolation

- Do you parallelize here? If yes, delegates use the brief template
  (`templates/delegation-brief.md`).
- **Worktrees** knob: on (isolated checkout per delegate) / off. Off is correct
  when the platform forbids it (AOSP) or it's costly (Unity: cold Library,
  MCP-per-worktree). If the project already has a worktree skill, point to it
  instead of re-inventing.
- Allowed delegate tooling: which MCPs/tools delegates may use; require absolute
  paths; note any "stale in worktree" caveats.

### Step 6 — Success check (how an agent proves pass/fail) — REQUIRED

An agent must be able to *mechanically* determine success. Capture the exact
command(s) and the expected baseline:

- test suite + baseline count ("`dotnet test …` → 110 existing + your new; report
  total")
- build/compile gate
- **headless self-capture sentinel** — teach the program a capture mode
  (env var → render → print `SCREENSHOT_SAVED:<path>` → quit) so an agent can
  verify visuals from Bash without an MCP. Strongly prefer this over a heavyweight
  integration MCP when the project renders anything.
- lint/format gate.

Write the command + baseline into `CLAUDE.md` under "How to verify success."

### Step 7 — Persona (anti-overengineering) — optional

Ponytail-style "lazy senior dev" ruleset, ON/OFF + strictness. ON + strict for
codebases where terseness is a virtue (AOSP, infra). OFF/loose where premature
minimalism hurts future modularity (your own game). If ON, wire it via
`templates/persona-ponytail.md` (SessionStart + SubagentStart hook pair so it
survives delegation), or the real plugin.

### Step 8 — Project memory

Where durable per-project gotchas/decisions live (ONE place): the user's Claude
file-memory (default, cross-project) · an in-repo `docs/decisions/` or `NOTES.md`
· a PARA location (Meta). Record it in `CLAUDE.md`. (We are NOT using a
code-graph memory backend.)

### Step 9 — Model routing + effort

Fill the routing table in `MANIFESTO.md` from `templates/MANIFESTO.md` — task →
model → effort — sized to this project's task types and the user's budget, and
name what earns `max`. Principle: **budget goes into design & review, not
typing.**

### Step 10 — Greenfield only: define the epic first

If Step 0 found an empty/near-empty project, before stamping run a short
"define the epic" pass: interview the vision, decompose into ticket-sized units,
seed them into the chosen tracker, and end by proposing the first parallel batch.
Then stamp the constitution around that plan.

### Step 11 — Stamp & hand off

1. Read each needed file in `templates/`, substitute every `{{KNOB}}` from the
   interview (you're an LLM — fill intelligently, delete guidance comments), and
   `Write` them to the target (repo root or `$WORKSPACE`).
2. Never overwrite an existing `CLAUDE.md` — merge into it.
3. Print a 4-line summary: **tracker is HERE · success is proven by THIS ·
   landing policy is THIS · start with `/goal <first objective>`.**
4. If in-repo git: stage the new files but let the user commit (respect their
   landing policy — do not push).
