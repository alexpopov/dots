<!-- WIZARD: process law. Fill every {{KNOB}}, delete these guidance comments.
     CLAUDE.md = domain/architecture law; MANIFESTO.md = process law. -->

# MANIFESTO — how work proceeds on {{PROJECT_NAME}}

Process law. Architecture/domain law lives in `CLAUDE.md`. When the two conflict,
`CLAUDE.md` wins on *what the code must be*; this file wins on *how work flows*.

## Operating mode: {{AUTONOMY_MODE}}

Plan, build, commit, and log continuously. **Escalate to the user first only when
a choice is (a) big or expensive, (b) hard to reverse, or (c) a creative-direction
call** — e.g. {{CREATIVE_EXAMPLES}}. Everything else proceeds and is logged.

Hard overrides that always apply, no matter the mode:
- Never kill processes (`kill`/`killall`/`pkill`) without explicit instruction.
- Never install packages (`brew`, global npm, etc.) without permission.
- Never paste secrets into the conversation; route them via files, out-of-band.
- Confirm before outward-facing or hard-to-reverse actions (push, publish, delete).
{{EXTRA_OVERRIDES}}

## Model routing & effort

The budget goes into design and review, not typing. Cheap models grind
well-specified work; expensive models plan and review.

| Task | Model | Effort |
|---|---|---|
{{MODEL_ROUTING_ROWS}}

`max` effort is reserved for: {{MAX_EFFORT_TRIGGER}}.

## Where work is tracked — the single source of truth

> **{{TRACKER_LOCATION}}**

This is the ONE place. A task is not done until its entry here is updated — and
that is the orchestrator's job as part of the same unit of work, not an
afterthought. Delegates do not touch the tracker; they report back and the
orchestrator records. Attach visual evidence (screenshots) to the entry, not to
chat scrollback.

## Landing policy

{{LANDING_POLICY}}

No unreviewed delegated code lands. Never auto-merge to the main branch.

## Delegation protocol

{{DELEGATION_STANCE}}

When delegating implementation, every brief follows `agent-orchestra-wizard/
templates/delegation-brief.md`: role + cage, tooling rule (absolute paths), project rules
restated, the exact API surface pre-digested, enumerated tests with the expected
baseline, the verify command, commit constraints (branch + forbidden paths), and
a structured report format. The orchestrator reads the code first and embeds the
API surface so the delegate spends zero tokens on discovery and can't drift.

Isolation: {{WORKTREE_POLICY}}

## Verification protocol

**Success check (mechanical):** {{SUCCESS_CHECK}} — see `CLAUDE.md` for the exact
command and baseline. An agent may not claim done without running it.

**Two-verifier gate before anything lands:**
- **Canary** (`templates/canary.md`) — facts only. Runs tests/build/captures and
  pastes raw output. Forbidden from opinions, edits, merges.
- **Reviewer** (`templates/reviewer.md`) — findings only, on a *different model*
  than the implementer, given the ticket's acceptance criteria and the original
  bug. Tags each finding `[BLOCKING]` or `[NIT]`; emits the exact sentinel
  `CLEAN — no blocking findings.` when nothing blocks, so the orchestrator can
  branch on it mechanically. `[BLOCKING]` → fix cycle.

## Persona

{{PERSONA_POLICY}}

## Steering habits

- `/goal` at session start pins the objective; its last clause often asks for the
  next parallelization batch.
- `/effort` dialed to match stakes (per the ladder above).
- Long work (builds, runs, long scripts) goes to **background tasks** so the
  conversation never blocks; push notifications on so review can happen from a
  phone.
- Multi-agent workflows are opt-in and gated on the keyword **"ultracode"** — do
  not fan out to a fleet without it.

## Project memory

Durable gotchas and decisions live in ONE place: {{MEMORY_LOCATION}}.
