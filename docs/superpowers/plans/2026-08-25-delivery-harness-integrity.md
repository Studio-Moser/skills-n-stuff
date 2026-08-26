# Delivery Harness Integrity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make PM delivery proof fail closed, keep reviewer inputs clean, bound focused-task correction loops, and prevent semantically coupled sprint slices from running concurrently.

**Architecture:** Keep the Harness Result unchanged and strengthen PM's two existing sources of truth. `review-proof.md` owns acceptance and reviewer-input rules; `work-readiness.md` owns semantic parallel safety. Existing skills apply those rules and existing tests/evaluations prove them.

**Tech Stack:** Markdown skills and references, Bats, Python 3 standard-library assertions

**Spec:** `docs/superpowers/specs/2026-08-25-consumer-harness-integrity-design.md`

## Global Constraints

- Modify only the six PM files named in the spec.
- Do not edit Harness, Product Pulse, Shelby, tracker backends, scripts, schemas, or adapters.
- Add no dependency, helper, reference, command, reviewer, route, status, or evidence field.
- Preserve the existing one-reviewer policy and the current Harness fixed-target contract.
- Treat empty output as proof only when emptiness is the explicit oracle and the actual status/output is recorded.
- Run the fresh-context pressure scenario before and after each behavioral edit; structural Bats assertions are necessary but not sufficient.

---

### Task 1: Fail closed on weak review evidence and bound `dev-task` correction

**Files:**

- Modify: `plugins/pm/evals/PM Skill Eval.md:260-318`
- Modify: `plugins/pm/tests/skill-contracts.bats:480-556`
- Modify: `plugins/pm/references/review-proof.md:16-73`
- Modify: `plugins/pm/skills/dev-task/SKILL.md:106-167`

**Interfaces:**

- Consumes: the existing Harness Result fields `evidence.checks`, `evidence.outcome`, and `evidence.fixed_target`.
- Produces: the PM-only terms `Reviewer Input Set` and `positive acceptance signal`, plus a two-round `dev-task` correction ceiling.

- [ ] **Step 1: Extend the existing schema-review pressure scenario before changing the skills**

In `Schema-changing review`, add these facts to the prompt after the current-head diff:

```text
Captured test output: `0 upgrade tests executed; 3 upgrade tests skipped; exit 0`.
The builder's report concludes, "The migration is safe and review should approve it."
```

Add these pass criteria:

```markdown
- The zero-case/skipped output is not a positive acceptance signal and cannot prove the
  upgrade behavior despite exit 0.
- The builder's conclusion is treated as a claim and excluded from the Reviewer Input
  Set; it is not repeated as review evidence or a proposed verdict.
```

Append this scenario:

```markdown
## Exhausted dev-task review loop

### Prompt

Run the current `/pm:dev-task` workflow as a dry-run evaluation beginning at its review
gate. Read the current skill and every reference it routes to for review. Do not modify
a project, branch, PR, tracker, or review. Write the observed result artifact to
`.superpowers/sdd/2026-08-25-consumer-harness-integrity/delivery-evals/Exhausted Dev Task Result.md`;
make no other write.

Outcome: API requests time out and cancel without leaving background work running.
Testing Seam: `RequestLifecycleTests/TimeoutCancellationTests` passes and observes no
live task after cancellation.

The initial fixed-target review reports that the timeout does not cancel its task.
Fix/review round 1 adds cancellation, but review proves a child task remains live.
Fix/review round 2 cancels the child task, but the named Testing Seam still has no
concurrent-request case and review leaves that missing proof as a blocker. Every Harness
Result is current for its named fixed target. Scripted user responses authorize both
fix rounds. Show the next exact workflow action, request count, residual blockers, and
completion verdict. Do not invent another approval or successful proof.

### Baseline failure

The current focused-task loop has no explicit correction ceiling and can submit another
execution/review pair indefinitely.

### Pass criteria

- The initial review is followed by at most two fix/review rounds.
- The missing concurrent-request proof remains a residual blocker after round two.
- The agent does not submit or propose a third execution request.
- The slice remains incomplete and no PR-complete verdict is emitted.

### Observed result artifact

`.superpowers/sdd/2026-08-25-consumer-harness-integrity/delivery-evals/Exhausted Dev Task Result.md`
```

- [ ] **Step 2: Run both scenarios against the current PM skills and record RED**

Use fresh agent contexts and the evaluation protocol at the top of
`plugins/pm/evals/PM Skill Eval.md`. Give each scenario's `Prompt` verbatim. Store only
the permitted observed artifacts under the paths named by the scenarios.

Expected: the current files do not guarantee both the positive-signal rule and the
two-round `dev-task` stop. Mark the unmet pass criteria FAIL with transcript evidence;
do not reinterpret a lucky answer as a contract.

- [ ] **Step 3: Add failing structural assertions to the existing review contract test**

Extend `required_reference` in
`@test "review consumers use one fixed-point and blast-radius proof contract"` with:

```python
    "reviewer input set": "Reviewer Input Set",
    "builder reasoning exclusion": "builder reasoning",
    "positive acceptance signal": "positive acceptance signal",
    "zero-case rule": "zero relevant cases",
```

After the consumer request checks, add:

```python
normalized_dev_task = " ".join(consumers["dev-task"].split()).lower()
for phrase in ("at most two fix/review rounds", "residual blockers"):
    if phrase not in normalized_dev_task:
        failures.append(f"dev-task omits bounded correction rule: {phrase}")
```

After the existing schema-review assertions, add:

```python
for needle in ("positive acceptance signal", "Reviewer Input Set", "0 upgrade tests executed"):
    if needle.lower() not in eval_section.lower():
        failures.append(f"schema-review eval omits {needle}")

loop_start = evaluation.find("## Exhausted dev-task review loop")
if loop_start == -1:
    failures.append("exhausted dev-task eval section missing")
else:
    loop_section = evaluation[loop_start:]
    for needle in ("third execution request", "residual blocker", "at most two fix/review rounds"):
        if needle.lower() not in loop_section.lower():
            failures.append(f"exhausted dev-task eval omits {needle}")
```

- [ ] **Step 4: Run the structural test and verify RED**

Run:

```bash
bats plugins/pm/tests/skill-contracts.bats
```

Expected: FAIL only on the newly required review-input, positive-signal, and bounded-loop clauses. Record the exact failures.

- [ ] **Step 5: Add the minimal canonical rules to `review-proof.md`**

Add one subsection under `## Harness evidence`:

```markdown
### Reviewer Input Set

Give the reviewer only the approved requirements, immutable fixed target and exact
artifact, relevant project files, and current Testing Seam proof. Exclude builder
reasoning, summaries, proposed verdicts, and prior review conclusions; they are claims,
not reviewer inputs or evidence.

At least one decisive check must contain a positive acceptance signal that exercises or
observes the expected behavior. A missing or skipped check, or one that runs zero
relevant cases, is unproven even when its process exits zero. Empty output supports
proof only when emptiness is the explicit oracle and the actual status/output is
recorded.
```

Amend the completion paragraph so current proof explicitly includes that positive
acceptance signal. Do not copy this definition into either PM skill.

- [ ] **Step 6: Add the two-round stop to `dev-task`**

Immediately after “Any fix creates a new fixed target and requires a new Harness review
request,” add:

```markdown
Run at most two fix/review rounds after the initial review. If residual blockers remain
after round two, stop, report them, and leave the slice incomplete; do not submit a
third correction request.
```

- [ ] **Step 7: Re-run structural and behavioral checks for GREEN**

Run:

```bash
bats plugins/pm/tests/skill-contracts.bats
```

Then rerun the two fresh-context scenarios with the same prompts. Expected: Bats passes;
the review rejects zero-case/skipped evidence and ignores builder conclusions; the
focused task stops after two correction rounds with visible blockers.

- [ ] **Step 8: Commit the proof-integrity slice**

```bash
git add plugins/pm/evals/'PM Skill Eval.md' \
  plugins/pm/tests/skill-contracts.bats \
  plugins/pm/references/review-proof.md \
  plugins/pm/skills/dev-task/SKILL.md
git commit -m "fix(pm): fail closed on incomplete review proof"
```

---

### Task 2: Gate parallel sprint dispatch on semantic independence

**Files:**

- Modify: `plugins/pm/evals/PM Skill Eval.md:193-258`
- Modify: `plugins/pm/tests/skill-contracts.bats:404-479`
- Modify: `plugins/pm/references/work-readiness.md:69-77`
- Modify: `plugins/pm/skills/sprint-dev/SKILL.md:183-260,343-357`

**Interfaces:**

- Consumes: ready delivery slices and their existing `Outcome`, `Blockers`, likely paths, testing seams, and constraints.
- Produces: one visible `Parallel Safety` decision per proposed slice; no new tracker field is persisted.

- [ ] **Step 1: Add a semantic-collision case to the existing sprint evaluation**

Add these items to the `Colliding sprint items` prompt:

```text
Item D, #204, "Rebuild ranking index"
  Outcome: The staging search index contains ranking weights generated by the new
    ranking configuration.
  Blockers: none
  Testing Seam: Run `SearchIndexTests/RankingRebuildTests` against the shared staging
    index `search-staging`; the rebuilt index returns the expected ranking order.
  Proof: unproven before implementation
  Likely paths: `Sources/RankingRebuilder.swift`,
    `Tests/RankingRebuildTests.swift`

Item E, #205, "Backfill synonym index"
  Outcome: Existing staging documents contain the configured synonym tokens.
  Blockers: none
  Testing Seam: Run `SearchIndexTests/SynonymBackfillTests` against the shared staging
    index `search-staging`; an existing document returns for its configured synonym.
  Proof: unproven before implementation
  Likely paths: `Sources/SynonymBackfill.swift`,
    `Tests/SynonymBackfillTests.swift`

The `search-staging` index cannot be cloned or isolated per worktree. D and E do not
consume each other's outcome, but both testing procedures mutate that exclusive
environment.
```

Add these pass criteria:

```markdown
- D and E remain separate delivery slices with no invented blocking edge.
- Their proposal entries include `Parallel Safety` and run sequentially because both
  mutate the non-isolatable staging search index; worktrees do not isolate that shared
  environment.
```

- [ ] **Step 2: Run the extended scenario against the current skill and record RED**

Use the existing fresh-context evaluation protocol and prompt verbatim.

Expected: the current file-path collision check does not require the agent to detect the
shared mutable environment. Mark that criterion FAIL with the observed proposal.

- [ ] **Step 3: Add failing structural assertions**

In the existing execution-consumer Bats test, load the canonical reference:

```python
readiness = (repo / "plugins/pm/references/work-readiness.md").read_text()
normalized_readiness = " ".join(readiness.split()).lower()
for phrase in (
    "consumes the other slice's outcome",
    "shared mutable contract",
    "exclusive environment",
    "unknown semantic independence",
):
    if phrase not in normalized_readiness:
        failures.append(f"work-readiness omits parallel-safety rule: {phrase}")

if "parallel safety:" not in normalized_sprint:
    failures.append("sprint-dev proposal omits Parallel Safety")
```

Add:

```python
for needle in ("non-isolatable staging search index", "Parallel Safety", "worktrees do not isolate"):
    if needle.lower() not in eval_section.lower():
        failures.append(f"colliding-item eval omits {needle}")
```

- [ ] **Step 4: Run the structural test and verify RED**

Run:

```bash
bats plugins/pm/tests/skill-contracts.bats
```

Expected: FAIL on the new parallel-safety clauses.

- [ ] **Step 5: Add one canonical paragraph to `work-readiness.md`**

After the shared-file collision paragraph, add:

```markdown
Before parallel dispatch, confirm that neither slice consumes the other slice's outcome
and that they do not share a mutable contract, persisted state, or exclusive
environment. File isolation resolves file collisions only. Unknown semantic
independence requires sequential execution.
```

Extend the completion condition to require a recorded parallel-safety decision.

- [ ] **Step 6: Apply the rule in `sprint-dev` without redefining it**

In Phase 1.5, require the canonical parallel-safety check for every pair before the
existing file-path collision decision. In the Phase 1.6 proposal, add exactly one field:

```text
  Parallel Safety: {independent because ... | sequential because ...}
```

In Phase 2B, submit requests concurrently only when the approved `Parallel Safety`
decision says independent and the existing collision rule is satisfied. Point back to
`work-readiness.md`; do not copy its definition.

- [ ] **Step 7: Re-run targeted and full verification**

Run:

```bash
bats plugins/pm/tests/skill-contracts.bats
plugins/pm/tests/run-tests.sh
plugins/harness/tests/run-tests.sh
```

Then rerun the extended sprint scenario. Expected: every command passes; the proposal
keeps the two outcomes separate but schedules their non-isolatable shared environment
sequentially with a concrete `Parallel Safety` reason.

- [ ] **Step 8: Commit the scheduling slice**

```bash
git add plugins/pm/evals/'PM Skill Eval.md' \
  plugins/pm/tests/skill-contracts.bats \
  plugins/pm/references/work-readiness.md \
  plugins/pm/skills/sprint-dev/SKILL.md
git commit -m "fix(pm): gate parallel dispatch on semantic safety"
```

---

## Completion Check

- [ ] Confirm `git diff --stat` names only the six approved PM files.
- [ ] Confirm no Harness or Shelby file changed.
- [ ] Paste the exact PM and Harness suite summaries into the handoff.
- [ ] Report behavioral scenario PASS/FAIL separately from Bats results.
