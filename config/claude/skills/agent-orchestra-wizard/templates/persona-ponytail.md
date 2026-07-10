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

## Option A — the real plugin (least effort)

```
/plugin marketplace add DietrichGebert/ponytail
/plugin install ponytail@ponytail
```

## Option B — your own hook pair (no external dependency)

Add to the project's `.claude/settings.json` a `SessionStart` hook AND a
`SubagentStart` hook that both inject the ruleset above (as text). The SubagentStart
half is what makes it survive delegation. Statusline can show the active mode.
Adjust the ladder's strictness to `{{PERSONA_STRICTNESS}}` in the injected text.
