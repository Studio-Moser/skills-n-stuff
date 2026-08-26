# Triage — Phase 3: Score

Loaded by `pm:triage` at Phase 3. Backend-independent — scoring reads the item and its
spec. The inline fix loop may persist spec content through the Phase 2 Step 2c path, but
Phase 3 must not write tracker status, owner, or verdict fields; Phase 4 owns those
writes.

Use the already-loaded `references/work-readiness.md` as the readiness source of truth.
Evaluate each item carried forward from Phase 2 against the agent-ready scorecard. Score
XL child items independently; do not score their goal epic.

## Submit the scorecard request

For each item, read `plugins/pm/references/scorecard-evaluator.md` in the PM orchestrator.
Copy its complete evaluation checklist, readiness gate, and output rules into the
request; do not pass the PM-private path to Harness. Then invoke `harness:execute` with
`operation: execute` and `route: bulk`. The request is read-only and evaluates one
delivery slice:

```yaml
operation: execute
route: bulk
outcome: Return the six-criterion PM readiness scorecard and verdict for one item
context:
  project: {canonical project identifier when known}
  mode: fresh
  state: {item title, description, labels, Bug claim value, spec, Established, Unresolved, and the full canonical readiness rules loaded by PM}
  files: [{CONTEXT.md, .pm/out-of-scope entries, configured repo list, and applicable spec paths}]
authority:
  working_directory: {absolute primary repository root}
  allowed_paths: [{read-only context and spec paths}]
  tools: [Read]
  approvals: []
constraints:
  - |
    PM scorecard evaluator system prompt:
    Score each criterion PASS or FAIL with a one-line explanation.
    1. Clear description: require WHAT to build and the desired outcome; prescribing
       HOW without the goal fails.
    2. Explicit acceptance criteria and Testing Seam: require specific testable done
       conditions and apply the supplied canonical Testing Seam selection rule;
       vague criteria fail.
    3. Linked code references: require specific files, modules, or APIs and the target
       repo name in a multi-repo project.
    4. Negative constraints: check the supplied out-of-scope decisions. Missing
       negatives fail only when a related rejection exists.
    5. Bounded scope: require one delivery slice in one repo with explicit Blockers;
       split independent or multi-repo outcomes, and never mark a goal epic ready.
    6. No controlling unknowns: require Established and Unresolved to separate
       evidence from gaps and hypotheses; a controlling unresolved question or causal
       hypothesis fails.
    Apply every applicable completion condition in the supplied canonical readiness
    rules before the numeric verdict. Do not infer evidence or treat a hypothesis as
    a confirmed cause. A failed readiness gate is always needs-info regardless of
    score. When the gate passes, return status/ready + owner/ai for 6/6,
    status/ready + owner/human for 4-5/6, or needs-info for 0-3/6.
    Return Score, Readiness gate with every failed condition, Verdict, per-criterion
    results, and Suggested fixes for every FAIL.
  - Do not write tracker status, owner, verdict, or spec content
verification:
  seam: Validate the returned six criteria, readiness gate, numeric score, and verdict against the embedded PM scorecard and supplied canonical readiness rules
  expected: Every criterion is PASS or FAIL with an explanation and the verdict obeys the readiness gate and thresholds
```

Populate that request with:

- The item's title, description, and spec (if one was written in Phase 2)
- The item's labels and an explicit `Bug claim: yes|no` value, determined from the same
  signals as Phase 2 (`bug` label or a body describing broken behavior)
- The item's persisted `Established` and `Unresolved` notes
- The content of `references/work-readiness.md`
- The project's CONTEXT.md content
- The `.pm/out-of-scope/` directory listing
- The list of configured repos from `pulse-config.yaml`

Accept candidates only from a Harness Result with current proven evidence. The report
artifact returns a per-criterion PASS/FAIL with explanations and a verdict. Preserve a
typed failure or blocker for the user instead of inventing a score.

## Agent-Ready Scorecard

```
Agent-Ready Scorecard:
1. [ ] Clear description (what, not how)
2. [ ] Explicit acceptance criteria and Testing Seam
3. [ ] Linked code references with target repo
4. [ ] Negative constraints (cross-refs .pm/out-of-scope/)
5. [ ] Bounded scope (one delivery slice, one repo, explicit Blockers)
6. [ ] No unresolved question or hypothesis controls the approach
```

## Readiness gate

Before applying a numeric verdict, apply every applicable completion condition from
`references/work-readiness.md` without substituting a local definition. Require the
`Testing Seam` value to satisfy the canonical Testing Seam selection rule in
`references/work-readiness.md`.

If any check fails, the readiness gate is `FAIL` and the verdict is `needs-info`
regardless of the numeric score. A user may supply evidence or fix the spec and rescore,
but a score or ownership override cannot bypass this gate.

## Present results

For each item, show:

```
--- Scorecard: {title} ---
Score: {X}/6
Readiness gate: {PASS|FAIL} — {explanation}

1. {PASS|FAIL} Clear description        — {explanation}
2. {PASS|FAIL} Acceptance criteria/seam  — {selection and explanation}
3. {PASS|FAIL} Code references           — {explanation}
4. {PASS|FAIL} Negative constraints      — {explanation}
5. {PASS|FAIL} Bounded scope             — {explanation}
6. {PASS|FAIL} No controlling unknowns   — {explanation}

Verdict: {status/ready+owner/ai | status/ready+owner/human | needs-info}
```

## Verdict thresholds

| Score | Verdict | Meaning |
|-------|---------|---------|
| 6/6 | `status/ready` + `owner/ai` | Fully specced and readiness gate passes |
| 4-5/6 | `status/ready` + `owner/human` | Minor gaps and readiness gate passes |
| 0-3/6 | `needs-info` (stays as `status/needs-triage`) | Major gaps — not ready for anyone |

A failed readiness gate always yields `needs-info`, including at 4-6/6.

## User decision

For items with a passing readiness gate, recommend `status/ready` + `owner/ai` at
6/6 and `status/ready` + `owner/human` at 4-5/6. Recommend `needs-info` for 0-3/6
or any failed readiness gate.

Ask the user:

```
Accept verdict? (yes / fix / human / info / skip)
```

- **yes** — accept the recommended verdict
- **fix** — fix the failing criteria now. For each FAIL, present the suggested fix from the scorecard evaluator and apply it to the spec inline. After fixing, re-score (loop back through the scorecard for changed criteria only).
- **human** — choose `status/ready` + `owner/human` when the readiness gate passes,
  regardless of numeric score
- **info** — override to `needs-info` (leave as `status/needs-triage` for later)
- **skip** — skip this item, leave unchanged

### Fixing inline

When the user chooses **fix**, iterate through each failing criterion:

```
Fix {criterion name}?
  Current: {what's there now, or "missing"}
  Suggested: {scorecard evaluator's suggestion}

Apply this fix? (yes / edit / skip)
```

- **yes** — apply the suggested fix to the spec
- **edit** — user provides their own text for this criterion
- **skip** — leave this criterion as-is (it will still FAIL)

After all fixes are applied, update the spec in the backend (same write path as Phase 2
Step 2c) without changing tracker status, owner, or verdict fields. Rerun the full
readiness gate and re-evaluate only the fixed score criteria.
