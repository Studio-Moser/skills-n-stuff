# PM Work Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate verified claims, testing seams, dependency-aware slices, and evidence-backed review into the existing PM lifecycle.

**Architecture:** Two shared references are the sources of truth. Existing skills load them at the relevant branch, while templates and evaluators require their output fields. Backend-only details move behind existing dispatch boundaries.

**Tech Stack:** Markdown skills and references, Bash, Bats, YAML frontmatter

**Spec:** `docs/superpowers/specs/2026-08-19-pm-work-readiness-design.md`

## Global Constraints

- Preserve PM trackers, labels, approval gates, model routing, and one-reviewer policy.
- Descriptions state invocation conditions only.
- Definitions live in one reference and are not copied into consumers.
- Each behavior change gets a failing contract test or recorded failing pressure scenario first.

---

### Task 1: Restore the baseline suite

**Files:**
- Modify: `plugins/machine/tests/render-codex-agents.bats`
- Modify: `plugins/machine/tests/rubric-audit.bats`

- [ ] Run the PM suite and preserve the assertion-guard failure as RED evidence.
- [ ] Add `|| return 1` to each non-final bare `[[ ... ]]` assertion reported by the guard.
- [ ] Run PM and machine suites and confirm both pass.

### Task 2: Add work-readiness contracts

**Files:**
- Create: `plugins/pm/references/work-readiness.md`
- Create: `plugins/pm/evals/PM Skill Eval.md`
- Modify: `plugins/pm/tests/skill-frontmatter.bats`

- [ ] Record baseline failures for bug triage and sprint collisions in the evaluation file.
- [ ] Add a failing Bats contract requiring the reference and its consumer pointers.
- [ ] Write the reference definitions and checkable completion conditions.
- [ ] Re-run the contract test and confirm it passes.

### Task 3: Integrate readiness into triage and specs

**Files:**
- Modify: `plugins/pm/skills/triage/SKILL.md`
- Modify: `plugins/pm/references/triage-spec-flow.md`
- Modify: `plugins/pm/references/triage-scorecard.md`
- Modify: `plugins/pm/agents/scorecard-evaluator.md`
- Modify: `plugins/pm/templates/spec-template.md`

- [ ] Move bug verification before speccing and add established/unresolved resumption notes.
- [ ] Load work-readiness at the verification/spec branch.
- [ ] Require the approved spec fields without repeating their definitions.
- [ ] Make each agent-ready item one verified slice; split XL work into child slices under an epic.
- [ ] Run the PM suite and the unverified-bug/L-feature/XL evaluation cases.

### Task 4: Integrate readiness into execution

**Files:**
- Modify: `plugins/pm/skills/sprint-dev/SKILL.md`
- Modify: `plugins/pm/skills/dev-task/SKILL.md`
- Modify: `plugins/pm/skills/codex-implementation/SKILL.md`

- [ ] Replace same-file forced grouping with frontier selection and collision scheduling.
- [ ] Replace the numeric batch cap with the delivery-slice completion criterion.
- [ ] Add outcome, blockers, testing seam, and proof to proposals and worker prompts.
- [ ] Run the PM suite and colliding-item evaluation case.

### Task 5: Add review-proof contracts

**Files:**
- Create: `plugins/pm/references/review-proof.md`
- Modify: `plugins/pm/agents/code-reviewer.md`
- Modify: `plugins/pm/skills/codex-review/SKILL.md`
- Modify: `plugins/pm/skills/dev-task/SKILL.md`
- Modify: `plugins/pm/skills/sprint-dev/SKILL.md`

- [ ] Record the schema-review baseline failure in the evaluation file.
- [ ] Add a failing Bats contract requiring the reference and reviewer pointers.
- [ ] Write fixed-point, axes, trigger, evidence, and completion guidance once.
- [ ] Point every reviewer entry path at the reference.
- [ ] Run the PM suite and schema-changing review evaluation.

### Task 6: Sharpen ingestion and progressive disclosure

**Files:**
- Modify: `plugins/pm/skills/ingest/SKILL.md`
- Modify: `plugins/pm/agents/ingestion-analyst.md`
- Create: `plugins/pm/references/ingest-github.md`
- Create: `plugins/pm/references/ingest-local.md`
- Create: `plugins/pm/references/ingest-trello.md`
- Modify: `plugins/pm/skills/setup/SKILL.md`
- Modify: existing `plugins/pm/references/setup-*.md`

- [ ] Change extracted items to evidence, proposed outcome, rationale, source, confidence, and target repo.
- [ ] Move backend-only ingest procedures behind backend references.
- [ ] Move remaining inline setup backend procedures into their selected references.
- [ ] Confirm each path loads only its selected backend instructions.

### Task 7: Rewrite descriptions and verify

**Files:**
- Modify: PM `SKILL.md` frontmatter descriptions where the current text summarizes workflow or repeats trigger synonyms.
- Modify: `plugins/pm/README.md`
- Modify: `studio-baseline/House_Rules.md`
- Test: `plugins/pm/tests/skill-frontmatter.bats`

- [ ] Rewrite descriptions to start with `Use when` and name distinct invocation branches only.
- [ ] Add the concise universal testing-seam and indirect-contract rule to House Rules.
- [ ] Update README behavior descriptions.
- [ ] Run PM and machine suites, frontmatter validation, and all five evaluation cases.
- [ ] Inspect the final diff for duplicated definitions and remove them.
- [ ] Commit in independently reviewable logical changes.
