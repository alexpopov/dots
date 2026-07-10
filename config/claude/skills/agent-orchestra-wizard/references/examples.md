# Four worked instantiations

Same spine, four very different knob settings. Pattern-match the target project
against the closest one.

## A · InariRush — long-running Unity game (GitHub)

| Knob | Value |
|---|---|
| Placement | in-repo |
| Golden rule | game logic in a pure-C# core; MonoBehaviours are thin adapters |
| Tracker | GitHub Issues (`Cayleigh/InariRush`) |
| Landing | PR, small |
| Parallelism | yes |
| Worktrees | **use the project's existing worktree skill** (Unity Library goes cold; MCP-per-worktree) |
| Success check | EditMode tests on the rainbowpc runner (advisory) |
| Persona | off / loose — terseness would hurt future modularity |
| Memory | Claude file-memory |
| Routing | Opus orchestrates; Sonnet implements systems; Fable/Opus review |

## B · dots — simple personal repo (no external tracker)

| Knob | Value |
|---|---|
| Placement | in-repo |
| Golden rule | cross-platform; changes must not break bootstrap on any target |
| Tracker | **in-repo `TASKS.md`** |
| Landing | commit to a branch, user merges |
| Parallelism | yes — one orchestrator, a few Sonnet delegates for independent chores |
| Worktrees | off (small repo, cheap file reads) |
| Success check | `./bootstrap.sh` runs clean; changed configs load |
| Persona | off |
| Memory | Claude file-memory |
| Routing | Opus orchestrates; Sonnet/Haiku for mechanical edits |

## C · AOSP — read-only root (external workspace)

| Knob | Value |
|---|---|
| Placement | **external-workspace** — can't write the AOSP root |
| Setup | `~/aosp-agent/` holds CLAUDE.md + MANIFESTO + TASKS.md; `src -> /path/to/android-16.0`; launch `claude` from `~/aosp-agent/` |
| Golden rule | respect AOSP layering/ownership; touch only the intended subtree |
| Tracker | in-repo `TASKS.md` **in the workspace** (or work Tasks) |
| Landing | Phabricator/Gerrit change per unit (Meta laptop later) |
| Worktrees | **off** — not supported here |
| Success check | the relevant `m`/soong build target + module tests |
| Persona | **on + strict** — minimalism is a virtue in a huge shared tree |
| Memory | PARA location |
| Routing | Opus for the gnarly bits; Sonnet for well-scoped module work |

## D · Metal water-caustics screensaver — from zero (greenfield)

| Knob | Value |
|---|---|
| Placement | in-repo (fresh repo) |
| Greenfield | **yes** — run the define-the-epic pass first: interview the vision, decompose into tickets, seed TASKS.md, propose the first parallel batch |
| Golden rule | physically accurate caustics; Metal-only; no external deps |
| Tracker | in-repo `TASKS.md` |
| Landing | commit to branch |
| Worktrees | optional (small at first) |
| Success check | **headless self-capture sentinel** — env var → render one frame → print `SCREENSHOT_SAVED:<path>` → quit; agent greps stdout and inspects the PNG |
| Persona | off — early modularity matters |
| Memory | in-repo `docs/decisions/` |
| Routing | Opus designs the simulation/render model (xhigh); Sonnet implements passes; Fable/Opus review |
