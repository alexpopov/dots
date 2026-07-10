<!-- WIZARD: in-repo tracker. Only stamp this when the tracker knob = in-repo TASKS.md.
     This file IS the single source of truth — keep it grep-friendly. -->

# TASKS — {{PROJECT_NAME}}

The single source of truth for work on this project. Agents: read this before
starting, and update the relevant ticket's status + notes as the final step of
any unit of work. One ticket = one shippable unit.

**Ticket format** (grep-friendly — status is a bracketed tag on the title line):

```
## T-<id> [<status>] <title>
Acceptance: <the one testable condition that means this is done>
Branch: <branch name, if any>
Notes: <running log — decisions, blockers, links, screenshot paths>
```

Statuses: `TODO` · `DOING` · `BLOCKED` · `REVIEW` · `DONE`.
Query examples: `grep '\[DOING\]' TASKS.md` · `grep '\[BLOCKED\]' TASKS.md`.

---

## Backlog

<!-- Greenfield: the wizard seeds the epic's tickets here. -->

## T-001 [TODO] {{FIRST_TICKET_TITLE}}
Acceptance: {{FIRST_TICKET_ACCEPTANCE}}
Branch:
Notes:

---

## Done
