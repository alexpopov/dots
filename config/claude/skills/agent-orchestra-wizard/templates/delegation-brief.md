<!-- WIZARD/ORCHESTRATOR: fill and hand to a delegate subagent. The orchestrator
     reads the code FIRST and embeds the real API surface so the delegate does
     zero discovery and can't drift. Keep sections in this order. -->

You are {{ROLE_SENTENCE}}. Work ONLY {{CAGE}}
<!-- CAGE examples:
     in the git worktree at C:/…/proj-wt-<ticket> — you are on branch feat/<ticket>-<slug>.
     in <absolute path>. Do NOT edit anything outside it. -->

TOOLING RULE: Use ONLY {{ALLOWED_TOOLS}} with ABSOLUTE paths under {{ROOT}}.
{{TOOLING_CAVEATS}}
<!-- e.g. "Do NOT use the code-graph MCP here — it indexes a different checkout,
     stale. Read files before editing." -->

PROJECT RULES (non-negotiable):
- {{GOLDEN_RULE}}
- {{STYLE_AND_DEP_RULES}}
- Calibrated strictness: {{STRICTNESS_NOTE}}
<!-- Name the stakes explicitly, e.g.:
     "This is a DATA-INTEGRITY feature: do NOT be lazy about correctness."
     next to "no speculative abstractions, no one-impl interfaces." -->

FEATURE — {{TICKET_ID}}: {{FEATURE_SUMMARY}}

Study the model first (read the real files):
{{API_SURFACE}}
<!-- The orchestrator pastes exact class names, ctor signatures, which fields are
     derived vs authoritative, which setter is internal-but-accessible, etc.
     This is the load-bearing section — the more precise, the less the delegate drifts. -->

IMPLEMENT:
{{IMPLEMENTATION_STEPS}}
<!-- Exact files, namespaces, method signatures, and decisions already made. -->

TESTS (add to {{TEST_LOCATION}}):
{{ENUMERATED_TESTS}}
<!-- List each required case. Flag the load-bearing one ("the important one").
     Always end with: "ALL existing tests must still pass." -->

VERIFY: {{VERIFY_COMMAND}} until green ({{EXPECTED_BASELINE}}). Report the total.
<!-- Baseline catches silent test-drops, e.g. "110 existing + your new tests." -->

COMMIT to {{BRANCH}} with a clear message. Touch NOTHING under {{FORBIDDEN_PATHS}}.
Do not merge or push.

REPORT: {{REPORT_FORMAT}}
<!-- What to send back — a structured summary, not a transcript. E.g.:
     files changed/added, new test count, the schema + an example, and confirm
     the load-bearing test proves what it's meant to. -->
