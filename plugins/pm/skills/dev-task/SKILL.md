---
name: dev-task
description: "Use when one large, multi-file Feature-class change needs the managed, approval-gated workflow, or the user asks for it. Never for Polish or Small work."
allowed-tools: "Bash Read Write Edit Skill"
---

# PM — Dev Task

Guide one person through one development task with visible plan and approval gates.
This is **manual only**. The current agent implements by default; routing a child is a
separate, risk-gated decision.

Use `pm:house-rules` for branch, commit, PR, test, and security conventions. Name the
change class first. Polish uses its one-line declaration as the plan and runs its
checkpoint gates. Small and Feature changes use the workflow below.

## 1. Frame

Read repository instructions and `references/work-readiness.md`. Record the approved
slice without adding fields:

```text
Outcome: {bounded observable result}
Blockers: {resolved prerequisites or none}
Testing Seam: {procedure and expected result}
Proof: {current proof, normally unproven}
```

Stop for an unresolved blocker. Load `harness:risk-gate` and record its mode, matched
triggers, testing seam, delegation decision, and review decision. Use brainstorming
only when the request remains materially ambiguous.

## 2. Plan — GATE

Write the smallest plan that makes files, behavior, edge cases, and proof reviewable.
Use a longer written plan only for a multi-step Feature. Stop and wait for explicit
approval before branching or editing.

## 3. Branch

Create or verify the branch/worktree per `pm:house-rules`. Never implement on the
default branch.

## 4. Execute

The current agent implements by default. Keep the approved slice in context, use
test-driven development for behavior changes, and stay inside the approved authority.

Delegate only when the risk gate identifies one independently useful substantial track
with its own outcome and verification seam. Then invoke `harness:delegate` with
`operation: execute` and the appropriate semantic route. Include the gate's
`max_children`, `max_depth`, and `token_budget` in the request:

```yaml
operation: execute
route: {bulk | quick | taste}
outcome: {Outcome}
context:
  project: {canonical project identifier when known}
  mode: fresh
  state: {approved plan, change class, and current Proof}
  files: [{relevant repository-relative paths}]
  memory:
    enabled: {true when project memory is configured; otherwise false}
    recall: Relevant project constraints, decisions, and known failure modes
    capture: []
authority:
  working_directory: {absolute repository root or approved worktree}
  allowed_paths: [{approved paths}]
  tools: [{required tools}]
  approvals: []
constraints:
  - "Blockers: {resolved Blockers or none}"
  - {approved acceptance criteria and negative constraints}
delegation:
  max_children: {risk-gate limit}
  max_depth: {risk-gate limit}
  token_budget: {bounded amount for this track}
verification:
  seam: {Testing Seam procedure}
  expected: {Testing Seam expected result}
```

Inspect the returned artifacts and evidence. Keep a `blocked`, `failed`, or `abandoned`
Harness Result visible; do not reinterpret it as delivery. Discovered work stays out
of scope.

## 5. Review

Self-review the fixed work against the approved slice and the loaded house rules.
Load `references/review-proof.md` for its Quality, Spec Fidelity, and Blast Radius
axes.

Request a separate review only when the risk gate says **independent review** or the
user explicitly asks for one. Ordinary structured work uses the current agent's
self-review. A provider-separated `route: independent` still requires explicit cost
approval. When review is required, submit a fixed-target `harness:delegate` request:

```yaml
operation: review
route: review
outcome: Report whether the fixed target satisfies the approved delivery slice
context:
  mode: fresh
  state: {approved requirements and current Testing Seam Proof}
  files: [{changed and review-relevant paths}]
authority:
  working_directory: {absolute repository root or worktree}
  allowed_paths: [{read-only review scope}]
  tools: [{read-only inspection and verification tools}]
  approvals: []
constraints:
  - |
    Quality: inspect correctness, regressions, security, edge cases, error handling,
    performance, maintainability, and adequate tests.
    Spec Fidelity: report missing or partial requirements, unrequested behavior, and
    mismatch with the approved requirement.
    Blast Radius: for Persisted data, schema, or migration behavior; Public API,
    protocol, wire format, or serialization behavior; Authentication, authorization,
    permissions, or another security boundary; or Shared runtime, dependency, build,
    deployment, or configuration behavior, name the central safety assumption and
    require a focused check. Otherwise record Blast Radius as not applicable.
  - Report each finding with severity, file, line, failure mode, and fix direction
  - Do not modify the target
verification:
  seam: {Testing Seam plus applicable Blast Radius checks}
  expected: {approved result and no unresolved review blocker}
  fixed_target: {commit SHA or immutable snapshot digest}
```

Any fix creates a new fixed target and, when separate review remains required, a new
Harness review request. Run at most two fix/review rounds; report residual blockers
instead of starting a third round.

## 6. Verify — GATE

Run one verification pass at the highest stable testing seam required by the change
class and risk gate. The pass may contain the repository's build, test, lint, or
targeted commands, but do not rerun the same proof merely because a worker or reviewer
also reported it. Reproduce external evidence only when the target changed, the proof
is stale, or the gate requires independent confirmation. Record actual output in
`Proof`. The slice remains incomplete while its Outcome or required proof is missing.

## 7. Demonstrate on request

For a user-visible web feature, offer a recorded walkthrough in one line after
verification. Only when the user explicitly asks to see or record the result, or
accepts the offer, invoke `pm:feature-walkthrough`. Pass the approved Outcome, Testing Seam,
feature test paths, requested devices, and destination. This optional demonstration
does not gate completion.

## 8. PR

Open the PR per `pm:house-rules` with What, Why, and Testing, then share the URL.

## 9. Wrap

Summarize what shipped and what stayed out of scope. Offer the configured tracker
update when applicable.

## Stop conditions

- An approval gate is open.
- A blocker makes the slice unassignable.
- Required evidence is missing or stale.
- A reviewed fixed target changed.
- The next action exceeds the approved slice, authority, or delegation limits.
