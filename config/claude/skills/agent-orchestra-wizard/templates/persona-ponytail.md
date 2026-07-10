<!-- WIZARD: only wire this when the persona knob = ON. Two ways to install; pick one. -->

# Persona: anti-overengineering (ponytail-style)

An enforced "lazy senior dev" ruleset. The clever part is that it must survive
delegation — a persona that only loads in the main session leaks out of every
subagent. So it's installed as a **SessionStart + SubagentStart hook pair**.

Core ruleset (the seven-rung ladder — climb only as far as needed):
1. Does it need to exist at all?
2. Is it already in the codebase?
3. Standard library?
4. Platform feature?
5. An existing dependency?
6. One line?
7. The minimum new code.

Plus: fix root causes, not symptoms. And mark every deliberate simplification
with a `ponytail:` comment naming the ceiling you stopped at and the upgrade path.

**Strictness for this project: {{PERSONA_STRICTNESS}}**
<!-- strict for infra/AOSP; loose for a project where premature minimalism would
     cost future modularity (e.g. a game core). -->

The canonical ruleset text lives at `../ponytail/ruleset.txt` (this skill) — one
source of truth shared by every wiring option below. Edit it there.

## Option A — the `claude-with` launcher toggle (already wired)

Alp's `dots/bin/scripts/claude-with` offers **`[persona] ponytail`** as an
opt-in item in its session picker. Selecting it passes an extra `--settings`
file that registers `SessionStart` + `SubagentStart` hooks which `cat` the
ruleset. Nothing to install; per-session; survives delegation. This is the quick
global opt-in.

> **Gotcha:** `/hooks` will show "No hooks configured" even when this is active —
> that command only lists hooks from on-disk settings files, not ones supplied at
> launch via `--settings`. The hooks still fire (verified: SessionStart stdout
> reaches the model). To confirm it loaded, just ask the session to recite its
> ponytail rules.

## Option B — commit the hooks into a project (persistent per-repo)

Add to the project's `.claude/settings.json` a `SessionStart` hook AND a
`SubagentStart` hook that both `cat` the ruleset (absolute path). The
SubagentStart half is what makes it survive delegation. For per-project
strictness `{{PERSONA_STRICTNESS}}`, copy the ruleset into the repo and tune it.

```json
{ "hooks": {
  "SessionStart":  [ { "hooks": [ { "type": "command", "command": "cat /abs/path/ruleset.txt" } ] } ],
  "SubagentStart": [ { "hooks": [ { "type": "command", "command": "cat /abs/path/ruleset.txt" } ] } ]
} }
```

## Option C — the third-party plugin (unverified marketplace)

```
/plugin marketplace add DietrichGebert/ponytail
/plugin install ponytail@ponytail
```
