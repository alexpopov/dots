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

## Option A — the `/ponytail` slash command (on demand, easiest)

`dots/config/claude/commands/ponytail.md` (symlinked into `~/.claude/commands/`
by bootstrap) defines `/ponytail`. Type it in any session and the persona loads
into the main conversation for the rest of that session — no launch-time setup.
It also asks Claude to fold the rules into any subagent briefs it writes, but
that propagation is best-effort (soft). For guaranteed enforcement across every
delegate, use Option B.

## Option B — commit the hooks into a project (persistent, survives delegation)

Add to the project's `.claude/settings.json` a `SessionStart` hook AND a
`SubagentStart` hook that both `cat` the ruleset (absolute path). The
SubagentStart half is what deterministically carries the persona into delegates
(what the soft `/ponytail` propagation can't guarantee). For per-project
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
