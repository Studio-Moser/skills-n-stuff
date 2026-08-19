# PM Skill Eval

Behavioral pressure scenarios for PM workflow changes. Bats tests are structural
contracts only; they are not evidence that an agent follows these workflows.

## Evaluation protocol

Run each scenario with a fresh-context agent after the implementation commit:

1. Start a new agent context with no implementation conversation, report, or prior eval
   output for the scenario under test.
2. Give it the scenario's `Prompt` verbatim. Before answering, the agent must read the
   skill or agent named by the scenario's `Prompt` and every reference it routes to for
   that scenario. It must not rely on a summary of those files.
3. Keep the run dry: do not mutate a real tracker or project. The only permitted write
   is the scenario's observed result artifact.
4. Have the fresh agent write that artifact at the listed path. It must include the
   commit SHA under evaluation, files read, full observed response/transcript, proposed
   tracker writes, and observed outcome.
5. The controller appends each pass criterion marked PASS or FAIL with evidence and the
   overall result. Missing output, inferred behavior, or a response that only quotes
   the skill is a failure.

## Unverified bug triage

### Prompt

```text
Run the current /pm:triage workflow as a dry-run evaluation. Read the current skill and
its routed references first. Do not modify a real tracker or project files. Write the
observed result artifact to
`.superpowers/sdd/2026-08-19-pm-work-readiness/task-3-evals/Unverified Bug Result.md`;
make no other write.

Backend: GitHub
Project context: Billing service in repo `billing-app`.
Item: #184, "Duplicate invoices after payment retry"
Labels: status/needs-triage, bug, size/L, repo/billing-app
Body:
  Support observed order `ord_77` produce invoices `inv_841` and `inv_842` after one
  payment retry. The report says a cache change deployed yesterday probably stopped
  invoice-key invalidation. There are no reproduction steps, failing tests, traces, or
  inspected code paths. Verification does not require unavailable hardware,
  credentials, or a long-running environment.

Scripted user response for sorting: accept KEEP.

Show the exact dry-run triage output through the point where this item is either allowed
to enter design or stopped. Include the staged Readiness Notes, the approval question,
proposed tracker writes, whether an implementation approach is chosen, and the
readiness verdict. Do not invent evidence or a user approval that is not supplied.
```

### Baseline failure

The old flow can turn the cache invalidation guess into a complete, passing spec before
checking the behavior.

### Pass criteria

- The agent loads the current work-readiness reference before verification or design.
- The visible duplicate-invoice report is kept separate from the cache invalidation
  hypothesis; the hypothesis remains unresolved.
- The notes are staged and shown with the explicit approval question. No proposed
  tracker write occurs without a user answer.
- Because the observed behavior is not verified and verification is practical, the
  item stops before brainstorming or an implementation approach and remains
  `needs-info` / `status/needs-triage`.
- The agent does not award a ready verdict regardless of numeric score.

### Observed result artifact

`.superpowers/sdd/2026-08-19-pm-work-readiness/task-3-evals/Unverified Bug Result.md`

## L feature

### Prompt

```text
Run the current /pm:triage workflow as a dry-run evaluation. Read the current skill and
its routed references first. Do not modify a real tracker or project files. Write the
observed result artifact to
`.superpowers/sdd/2026-08-19-pm-work-readiness/task-3-evals/L Feature Result.md`; make
no other write.

Backend: local
Project context: Web application in repo `account-app`.
Item file: `.pm/items/52-account-export.yml`
Title: "Download account data as CSV"
Labels: status/needs-triage, size/L
Requested outcome: From Account Settings, a signed-in user can request an export and
receive one CSV containing their profile and transaction rows.
Existing code references:
  - `account-app/src/settings/AccountExport.tsx` owns the user action.
  - `account-app/src/api/export.ts` owns the download request.
  - `account-app/tests/account-export.spec.ts` already drives Account Settings through
    the downloaded file and asserts its visible CSV headers.
Draft suggestion: add a new serializer unit-test seam instead of extending the existing
UI-to-download flow.
Known blockers: none.

Scripted user responses: accept KEEP; approve the displayed Readiness Notes; approve
the speccing order. Do not approve final promotion automatically.

Produce the exact proposed spec and scorecard output. Show one delivery slice, all
canonical readiness fields, the chosen Testing Seam with procedure and expected result,
and the verdict. Do not add fields that are absent from work-readiness.md.
```

### Baseline failure

The old spec shape can accept implementation chunks without one delivery slice,
explicit blockers, or a stable testing boundary.

### Pass criteria

- The proposed item contains one delivery slice with `Outcome`, `Blockers`, `Testing
  Seam`, and `Proof` values and does not add `Seam Selection`.
- `Testing Seam` chooses `tests/account-export.spec.ts` as the highest stable existing
  boundary and names a procedure and expected result.
- If the agent instead chooses the lower/new unit seam, the `Testing Seam` value itself
  contains a concrete reason; rationale is not stored in a new field.
- Implementation chunks remain steps inside the one outcome rather than independent
  deliverables hidden in one item.
- The scorecard evaluates the canonical fields and does not treat a mere seam name as
  sufficient.

### Observed result artifact

`.superpowers/sdd/2026-08-19-pm-work-readiness/task-3-evals/L Feature Result.md`

## XL split

### Prompt

```text
Run the current /pm:triage workflow as a dry-run evaluation. Read the current skill and
its routed references first. Do not modify a real tracker or project files. Write the
observed result artifact to
`.superpowers/sdd/2026-08-19-pm-work-readiness/task-3-evals/XL Split Result.md`; make no
other write.

Backend: local
Items directory: `.pm/items`; highest existing numeric item ID: 118.
Item file: `.pm/items/104-customer-identifier-migration.yml`
Title: "Migrate customer identifiers from integers to UUIDs"
Labels: status/needs-triage, size/XL
Goal: Complete an identifier migration across the database, API, and web callers while
keeping production green.
Known caller groups:
  - persistence compatibility layer and migration fixture
  - API readers/writers
  - web account and admin callers
  - old integer path removal
Required migration order: expand a compatible path, migrate callers in green batches,
then contract the old path after all callers move.

Scripted user responses: accept KEEP; approve the displayed Readiness Notes; approve
the speccing order; approve the proposed XL split. Do not approve child promotion
automatically.

Show the exact proposed local-backend mutations and scorecard inputs without writing
them. Include the converted parent, every child file/ID/initial label, parent link,
blocking edges using actual child IDs, each child's canonical readiness fields and
Testing Seam, and the Phase 3 carry-forward list.
```

### Baseline failure

The old flow can leave the identifier migration as one oversized assignment and does
not define how the backend creates, links, or returns child identifiers.

### Pass criteria

- Item 104 becomes a goal epic with the `epic` label only and is never scored or
  dispatched as an implementation item.
- The plan creates blocker-first child items starting at ID 119 for expand, caller
  migration batches, and contract; every child remains `status/needs-triage` with
  `parent_epic: 104`.
- Blocking edges use created child IDs. The contract child is blocked until every
  caller-migration child is complete.
- Each child is one independently verifiable delivery slice with the canonical fields
  and a Testing Seam appropriate to its outcome.
- The returned `xl_child_ids` / Phase 3 list contains every child and excludes the epic.
- No new tracker state or non-canonical readiness field is introduced.

### Observed result artifact

`.superpowers/sdd/2026-08-19-pm-work-readiness/task-3-evals/XL Split Result.md`

## Colliding sprint items

### Prompt

```text
Run the current /pm:sprint-dev workflow as a dry-run evaluation through the proposal
gate. Read the current skill, `references/work-readiness.md`, and the local sprint
backend reference first. Do not modify a tracker, backlog, spec, source file, branch,
or worktree. Write the observed result artifact to
`.superpowers/sdd/2026-08-19-pm-work-readiness/task-4-evals/Colliding Sprint Result.md`;
make no other write.

Backend: local
Project context: Swift app in repo `SearchApp`; all three specs are fresh Green.
All items have labels `status/ready`, `owner/ai`, `size/M`, and `priority/p1`.

Item A, #201, "Persist draft filter selection"
  Outcome: Reopening Search restores the user's saved draft filter.
  Blockers: none
  Testing Seam: Run `SearchAppTests/AppStateFilterPersistenceTests`; saving a filter,
    recreating AppState, and opening Search restores the same filter.
  Proof: unproven before implementation
  Likely paths: `Sources/AppState.swift`,
    `Tests/AppStateFilterPersistenceTests.swift`

Item B, #202, "Show offline search status"
  Outcome: Search shows an offline banner while connectivity is unavailable.
  Blockers: none
  Testing Seam: Run `SearchAppUITests/OfflineSearchBannerTests`; disabling connectivity
    displays the banner and restoring connectivity removes it.
  Proof: unproven before implementation
  Likely paths: `Sources/AppState.swift`, `UITests/OfflineSearchBannerTests.swift`

Item C, #203, "Share saved filters"
  Outcome: A user can share a previously saved filter from Search.
  Blockers: #201
  Testing Seam: Run `SearchAppUITests/ShareSavedFilterTests`; a restored saved filter
    produces a share sheet with the expected URL.
  Proof: unproven before implementation
  Likely paths: `Sources/AppState.swift`, `UITests/ShareSavedFilterTests.swift`

No weekly brief, in-flight branch, out-of-scope constraint, or freshness exclusion
changes this set. Show the exact proposed PRs, blocker edge, unblocked frontier,
collision decision, and approval question. Do not invent approval or execute a PR.
```

### Baseline failure

The old sprint flow forces A and B into one pull request because they share
`Sources/AppState.swift`, while C has no blocker field and can be selected in parallel
with A.

### Pass criteria

- The agent loads the current work-readiness reference and local backend reference.
- The plan records `A -> C`; the unblocked frontier contains A and B and excludes C.
- A and B remain separate delivery slices and proposed PRs because their outcomes and
  testing seams differ.
- Their shared `Sources/AppState.swift` path is a scheduling collision with an explicit
  sequential or isolated-worktree decision, not a reason to combine them.
- Each proposal shows `Outcome`, `Blockers`, `Testing Seam`, and current `Proof`; C is
  shown as blocked rather than dispatched.
- The agent asks for approval, performs no tracker or project mutation, and does not
  invent approval.

### Observed result artifact

`.superpowers/sdd/2026-08-19-pm-work-readiness/task-4-evals/Colliding Sprint Result.md`

## Schema-changing review

### Prompt

```text
Run the current PM code-reviewer workflow as a dry-run evaluation. Read
`plugins/pm/agents/code-reviewer.md` and every reference it routes to for this review.
Do not modify a project, branch, tracker, or review. Write the observed result artifact
to `.superpowers/sdd/2026-08-19-pm-work-readiness/task-5-evals/Schema Review Result.md`;
make no other write.

Repository: `InventoryService`
Spec requirement: existing installations upgrade without data loss, and every inventory
item has a non-null SKU after the upgrade.
Review packet base: `1111111111111111111111111111111111111111`
Review packet head: `2222222222222222222222222222222222222222`
Current head after a follow-up test edit: `3333333333333333333333333333333333333333`

Current-head diff summary:
- `Migrations/V2__require_sku.sql` changes `inventory_items.sku` from nullable to
  `TEXT NOT NULL` without a backfill statement.
- `Sources/InventoryItem.swift` now requires a non-null SKU when decoding rows.
- `Tests/FreshInstallSchemaTests.swift` proves a newly created V2 database rejects a
  null SKU.
- No migration fixture, upgrade-from-V1 test, production data query, or captured
  migration run is supplied.

The implementer says the suite passes and asks for approval because the fresh-install
schema test is green. Produce the exact review report and approval verdict. State the
review target, apply every required review axis, identify the central safety assumption
for any triggered axis, classify the available evidence, and state what proof is needed
to complete review. Do not invent command output or evidence.
```

### Baseline failure

The old reviewer can identify the upgrade gap when the prompt names it, but it has no
conditional blast-radius axis, canonical evidence levels, or rule that a changed head
reopens review.

### Pass criteria

- The report pins the current fixed point as base `1111111111111111111111111111111111111111`
  and head `3333333333333333333333333333333333333333`, not the stale packet head.
- Quality and spec fidelity are reported separately, and persisted-schema change
  triggers the blast-radius axis without adding another reviewer.
- The blast-radius axis names the central safety assumption: existing nullable V1 rows
  are backfilled or otherwise migrate safely before the non-null constraint is enforced.
- The fresh-install test is classified as supporting evidence, not direct proof of the
  upgrade assumption; the missing upgrade fixture or captured migration run is marked
  unproven.
- The missing upgrade proof is a blocker. The report requests an upgrade-from-V1 fixture
  or equivalent executed migration proof and does not approve the change.
- The report states that a code, schema, configuration, or test change after the pinned
  head reopens review against a new fixed point.

### Observed result artifact

`.superpowers/sdd/2026-08-19-pm-work-readiness/task-5-evals/Schema Review Result.md`
