---
name: dev-task
description: >-
  Use when implementing one named feature, known bug fix, or focused code change
  interactively in the current repo, especially when a teammate needs guided approval
  gates. Do not use for a sprint or backlog batch, open-ended design, standalone
  review, or diagnosis before a cause is known.
allowed-tools: "Bash Read Write Edit Skill"
---

# PM — Dev Task

Guide ONE person through ONE development task, foreground and interactive, the Studio
Moser way. Stop at the approval gates. PM owns the development workflow and submits
bounded execution and review work to Harness; it never resolves the concrete runtime.

**REQUIRED SUB-SKILL:** Use pm:house-rules for branch, commit, PR, test, and security
conventions. Do not restate them here.

Name the change class first. Polish uses its one-line class declaration as the plan and
runs its suite, review, and commit at the checkpoint. Small and Feature changes use the
gates below.

## 1. Frame

- If a memory MCP is connected, recall relevant project context. Otherwise continue.
- Read the repository's `CLAUDE.md` or `AGENTS.md`.
- Load `references/work-readiness.md`. It is the source of truth for whether the
  delivery slice is assignable and for the `Outcome`, `Blockers`, `Testing Seam`, and
  `Proof` fields.
- Restate the task and its four delivery-slice fields from the approved item or spec.
- Stop when a blocker is unresolved. State the evidence needed to resume.
- Name material unknowns and risks. Use superpowers:brainstorming before planning only
  when the request remains genuinely ambiguous or large.

## 2. Plan — GATE

Write a concise 5–10 bullet plan with files and edge cases. For a multi-step Feature,
use superpowers:writing-plans. Show the delivery slice before the steps:

```text
Outcome: {bounded observable result}
Blockers: {resolved prerequisites or none}
Testing Seam: {procedure and expected result}
Proof: {current proof; normally unproven}
```

Stop and wait for explicit approval. Do not branch or edit before approval.

## 3. Branch

Create or verify the branch/worktree per pm:house-rules. Never implement on the default
branch.

## 4. Execute through Harness

Use `harness:execute` with `operation: execute`. Choose only the semantic altitude PM
knows: `route: bulk` for clear-spec or mechanical work, `route: quick` only for a short
latency-sensitive step, and `route: taste` for user-facing design, copy, or public API
work. Harness owns all concrete routing and execution decisions.

Submit a complete Harness Request shaped like this, replacing every placeholder with
the approved slice's actual values:

```yaml
operation: execute
route: {bulk | quick | taste}
outcome: {Outcome}
context:
  project: {canonical project identifier when known}
  mode: fresh
  state: {approved plan, change class, current Proof, and repository state}
  files: [{repository-relative implementation and test paths}]
authority:
  working_directory: {absolute repository root or approved worktree}
  allowed_paths: [{paths approved by the plan}]
  tools: [{repository tools needed to edit, test, and commit}]
  approvals: []
constraints:
  - "Blockers: {resolved Blockers or none}"
  - {approved acceptance criteria and negative constraints}
  - {pm:house-rules implementation and security constraints}
  - {commit actions authorized by the approved plan; PM opens the PR after acceptance}
verification:
  seam: {Testing Seam procedure}
  expected: {Testing Seam expected result}
```

The implementation request carries the approved delivery slice verbatim, including
its blockers and testing seam. Discovered work stays out of scope and is reported to
PM instead of being fixed inline.

Consume the returned Harness Result. Keep a `blocked`, `failed`, or `abandoned` result
visible with its blockers; do not reinterpret it as delivered. Inspect the returned
artifacts and evidence before continuing.

## 5. Review

Load `references/review-proof.md`. Self-review the fixed work against pm:house-rules,
then submit a read-only `harness:review` request with `operation: review`. Ordinary
review uses `route: review`. A fresh-context adversarial review uses
`route: independent` only after the user explicitly approves its cost.

```yaml
operation: review
route: {review | independent}
outcome: Report whether the fixed target satisfies the approved delivery slice
context:
  project: {canonical project identifier when known}
  mode: fresh
  state: {approved requirements and current Testing Seam Proof}
  files: [{changed and review-relevant repository paths}]
authority:
  working_directory: {absolute repository root or worktree}
  allowed_paths: [{read-only review scope}]
  tools: [{read-only inspection and verification tools}]
  approvals: []
constraints:
  - Apply PM's Quality, Spec Fidelity, and Blast Radius axes from references/review-proof.md
  - Report each finding with severity, file, line, failure mode, and fix direction
  - Do not modify the target
verification:
  seam: {Testing Seam procedure plus applicable blast-radius checks}
  expected: {approved acceptance result and no unresolved review blocker}
  fixed_target: {commit SHA or immutable snapshot digest}
```

Treat the returned report as a claim under the Harness contract. Reproduce the relevant
check, confirm the fixed target is unchanged, and address or evidence-dispute every
blocker. Any fix creates a new fixed target and requires a new Harness review request.

## 6. Verify — GATE

Use superpowers:verification-before-completion. Run the full repository tests/build/
lint and reproduce the named Testing Seam against the returned artifact. Record the
actual command or procedure and result in `Proof`. The slice is incomplete while its
Outcome is missing, its Harness evidence is unproven, or a PM review blocker remains.

## 7. PR

Open the PR per pm:house-rules with What, Why, and Testing, then share the URL.

## 8. Wrap

Summarize what shipped and what stayed out of scope. Use
superpowers:finishing-a-development-branch for the merge/PR/cleanup choice. If a PM
tracker is configured, offer to update the item. Save reusable project learning when a
memory MCP is available.

## Stop conditions

- An approval gate is still open.
- A blocker makes the delivery slice unassignable.
- The Harness Result is not accepted with current proof.
- The fixed target changed after review.
- The proposed action is outside the approved delivery slice or authority.
