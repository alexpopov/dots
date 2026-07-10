<!-- WIZARD: domain/architecture law. Fill every {{KNOB}}, delete guidance comments.
     If a CLAUDE.md already exists, MERGE these sections in — do not clobber. -->

# {{PROJECT_NAME}}

{{ONE_LINE_IDENTITY}}

Process law (autonomy, model routing, delegation, review) lives in `MANIFESTO.md`.

## Golden rule

**{{GOLDEN_RULE}}**

{{ADDITIONAL_RULES}}

## Don'ts

{{DONTS}}

## Project map

{{PROJECT_MAP}}

## Tooling

{{TOOLING_RULES}}
<!-- e.g. which MCPs are live and for what; "delegates use absolute paths only";
     "the code-graph is stale inside worktrees — don't use it there". -->

## Where work is tracked

> **{{TRACKER_LOCATION}}**

The single source of truth. A task isn't done until its entry here is updated.
(Must be identical to the line in `MANIFESTO.md`.)

## How to verify success

Run this to prove a change works — never claim done without it:

```
{{SUCCESS_CHECK_COMMAND}}
```

Expected baseline: {{SUCCESS_BASELINE}}.
{{SUCCESS_NOTES}}

## Project memory

Durable decisions and gotchas: {{MEMORY_LOCATION}}.
