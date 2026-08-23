# Harness Plugin Design

**Date:** 2026-08-23
**Status:** Proposed

## Purpose

Create one `harness` plugin that defines and configures how Studio Moser agents behave across tools and workflows. It replaces the `machine` plugin and removes model selection, provider selection, executor mechanics, general delegation rules, and universal verification policy from PM and Product Pulse.

The desired layering is:

```text
Harness plugin       control plane: policy, setup, routing, execution, verification
Claude/Codex/etc.    execution plane: the agent runtimes that perform work
Shelby (optional)    state plane: project memory, plans, checkpoints, run observability
PM/Product Pulse     workflow plane: domain-specific work definitions and lifecycle
Project repositories project plane: local context, artifacts, tests, and source
```

Harness and Shelby are intended to converge on the same behavioral contracts without duplicating implementations. Harness configures existing external agent runtimes; Shelby remains the richer native product and persistent state provider.

## Goals

1. Give every workflow one provider-neutral contract for execution, review, computer use, context, and proof.
2. Make the model rubric and installed `agents` repository the resolved personal harness configuration.
3. Keep PM focused on software-development workflow and Product Pulse focused on research workflow.
4. Preserve correct execution when Shelby is unavailable while using its project-scoped memory and run state when connected.
5. Replace structural confidence with a repeatable old-versus-new behavioral evaluation.
6. Remove `machine` completely; no aliases or compatibility layer are required.
7. Subsume the static `studio-baseline` package into Harness so universal behavior has one source of truth.

## Non-Goals

- Reimplement Shelby's memory database, graph, retrieval, synchronization, native agent loop, provider transports, CloudKit storage, chat UI, heartbeat, or recommendations.
- Create a second project manager, research workflow, or backlog.
- Add a general-purpose agent runtime or hide runtime permission prompts.
- Pick new model providers or add GLM to the default rubric without representative eval evidence.
- Require Shelby for public or cross-machine use.
- Apply a machine-readable acceptance ledger to every small task in this migration. The contract must leave room for a later eval-gated pilot on substantial work.

## Ownership Boundary

### Harness owns

- Initial personal harness setup and ongoing synchronization.
- The `agents` repository relationship and portable-versus-machine-local state boundary.
- Capability discovery for installed agent CLIs, computer-use systems, and optional integrations.
- Model rubric creation, refresh, validation, route resolution, and audit.
- Semantic routes and their escalation/fallback behavior.
- Native and cross-vendor executor selection.
- Delegation, context mode, worktree/isolation, tool scope, and permission policy.
- Typed handoffs between workflows, parent agents, workers, and reviewers.
- Universal truthful-completion, evidence, and parent-reverification rules.
- Provider-neutral execution, review, independent review, and computer-use operations.
- Optional Shelby project scope, memory lookup, plans, checkpoints, and run events.
- Execution telemetry needed to measure verified accepted-task cost.

### PM owns

- Issue intake, triage, prioritization, readiness, and tracker state.
- Development-specific Outcomes, Blockers, delivery slices, testing seams, and proof requirements.
- The unblocked frontier, sprint proposals, PR lifecycle, and reconciliation.
- Development review axes such as spec fidelity and blast radius.

PM submits those domain requirements to Harness. PM does not read `model-rubric.yml`, interpret `via:`, select a provider, invoke a vendor-specific executor, or redefine universal evidence rules.

### Product Pulse owns

- Research questions, source selection, source credibility, comparison, synthesis, and report publication.
- Classification of research work by semantic altitude, such as bulk scanning or judgment-heavy synthesis.

Product Pulse requests Harness routes. It does not name models or repeat dispatch mechanics.

### `agents` owns

- One developer's version-controlled resolved harness instance: synced instructions, skill declarations, routing configuration, and portable tool settings.
- No credentials, absolute machine paths, temporary artifacts, run evidence, approval records, or mutable Shelby state.

## Plugin Surface

The new plugin lives at `plugins/harness/` and replaces `plugins/machine/`.

### User-facing skills

| Skill | Responsibility |
| --- | --- |
| `harness:setup` | Configure the personal harness, including the `agents` repository, capabilities, rubric, and optional integrations. |
| `harness:sync` | Reconcile portable agent instructions, skills, manifests, and settings across supported tools and the `agents` repository. |
| `harness:model-rubric` | Create, refresh, validate, and audit semantic routes against current models and local capabilities. |
| `harness:execute` | Execute one bounded task from a Harness Request and return a Harness Result. |
| `harness:review` | Review a fixed target through the normal or independent semantic route and reproduce relevant evidence. |
| `harness:computer-use` | Execute or verify work that requires a local UI, browser, simulator, screenshot, or other computer-use capability. |

`harness:review` supports both ordinary and independent review because independence is an attribute of the request, not a separate workflow product.

### Shared references

| Reference | Source of truth |
| --- | --- |
| `references/harness-contract.md` | Request/result schema and consumer rules. |
| `references/routing.md` | Semantic route meanings, resolution, explicit dispatch, escalation, and fallbacks. |
| `references/handoff.md` | Typed handoff fields and context boundaries. |
| `references/verification.md` | Fixed targets, evidence levels, truthful completion, and parent reverification. |
| `references/context.md` | Fresh, forked, and hybrid session choice; durable versus transient context. |
| `references/shelby-integration.md` | Optional project scope, memory, plans, checkpoints, and run logging. |
| `references/house-rules.md` | Universal engineering discipline and change-class behavior. |

Harness also ships `templates/AGENTS_Baseline.md`, the project instruction block
rendered or stamped by setup/sync. The former plugin-free Studio Baseline is not
retained as a parallel distribution surface.

References are loaded only by skills and workflows that need them. Universal rules should not be duplicated in consumer skills.

## Harness Contract

### Request

A consumer constructs one provider-neutral request:

```yaml
operation: execute | review | computer-use
route: bulk | quick | default | taste | batch | review | independent
outcome: bounded observable result
context:
  project: canonical project identifier when known
  mode: fresh | fork | hybrid
  state: concise current state
  files: relevant repository-relative paths
authority:
  working_directory: repository root or worktree
  allowed_paths: explicit write/read scope when narrower than the repository
  tools: required capabilities
  approvals: actions that still require the user
constraints:
  - explicit task constraints
verification:
  seam: highest stable observable check
  expected: expected result
  fixed_target: commit or immutable snapshot when reviewing
```

Workflow-specific fields remain in the consumer's domain. For example, PM owns blockers and blast-radius assumptions; Product Pulse owns source requirements. They are included as constraints or context rather than added to the universal schema.

### Result

Harness returns one evidence-bearing result:

```yaml
status: accepted | failed | blocked | abandoned
route:
  requested: semantic route
  actual_model: resolved model
  effort: resolved effort
  provider: resolved provider
  executor: native agent or external CLI
artifacts:
  files: changed or created paths
  report: optional report path
evidence:
  fixed_target: commit or immutable snapshot
  checks: commands or procedures with actual results
  outcome: proven | unproven
telemetry:
  attempts: count
  elapsed: duration when available
  verification_failures: count
  token_or_quota_usage: value when available
shelby:
  project_id: optional
  run_id: optional
  checkpoint_ids: optional
blockers: explicit unresolved items
```

`accepted` requires delivered outcome plus current proof. Executor exit zero and worker-authored claims are insufficient.

## Routing and Execution

Consumers choose semantic altitude; Harness resolves concrete execution.

- `bulk`: clear-spec, mechanical, independently verifiable work.
- `quick`: short latency-sensitive work.
- `default`: ordinary interactive work without a stronger reason.
- `taste`: user-facing judgment such as UI, copy, or public API design.
- `batch`: unattended fan-out when configured and appropriate.
- `review`: strong fixed-target review.
- `independent`: a context-independent adversarial read, requiring explicit user approval under the existing cost rule.

The rubric continues to store concrete `model@effort` values and optional executor metadata, but only Harness interprets them. Every dispatch passes the resolved model and effort explicitly. A provider-specific adapter may translate the route into a CLI invocation, native subagent call, or current-session execution.

Unavailable capability is a typed resolution outcome:

- Use an allowed fallback route or executor when the request permits it.
- Report `blocked` when the required capability has no safe fallback.
- Never silently change permission scope, independence, provider boundary, or required computer-use capability.

## Context and Handoffs

The context mode is explicit:

- `fresh`: isolated task with only the handoff and durable project instructions.
- `fork`: full parent context when supported and when shared context is the point.
- `hybrid`: stable project/session brief plus a bounded task packet and live lookup for changing facts.

The default for delegated implementation, bulk research, and independent review is `fresh`. The default for a continuation requiring prior decisions is `hybrid`. `fork` is reserved for tasks whose correctness depends on full conversational context and whose runtime actually supports faithful inheritance.

The handoff uses Shelby's useful `HandoffPacket` concept without copying its Swift implementation. It includes outcome, current state, relevant files, constraints, unresolved blockers, verification seam, current proof, authority, and expected return shape.

## Verification

Harness centralizes universal evidence rules now scattered across Studio Baseline and PM:

1. Fix the target before review or reverification.
2. Treat worker summaries and old logs as claims.
3. Execute the highest stable seam against the returned artifact.
4. Record actual output and classify it as direct proof, supporting evidence, or unproven.
5. Reopen verification when the fixed target or oracle changes.
6. Keep impossible requirements visible as abandoned or blocked; never silently shrink scope.

PM continues to define development-specific Quality, Spec Fidelity, and Blast Radius axes. Harness supplies the fixed-target and evidence mechanism they use.

A machine-readable ledger is a future Harness capability, not a prerequisite for this migration. Its adoption requires the same old/new eval protocol and should initially target Feature-class and sprint work rather than all changes.

## Optional Shelby Integration

Harness detects Shelby MCP tools at runtime.

### When Shelby is available

- Resolve one canonical project scope before memory reads or writes.
- Load a stable project brief at session start and use targeted live queries for changing facts.
- Search prior decisions before routing or architectural choices.
- Log substantial Harness runs and phase transitions.
- Create plans and save recovery checkpoints when the work is long enough to benefit.
- Capture durable decisions and non-obvious findings into the scoped project.
- Include Shelby identifiers in the Harness Result.

### When Shelby is unavailable

- Continue using repository instructions, Git state, and temporary local artifacts.
- Preserve the same routing, authority, verification, and result contract.
- Omit memory and run-state enrichment without creating a competing database.
- State only the missing enrichment when it materially affects continuity; do not call correct execution blocked merely because Shelby is absent.

No Shelby data is copied into repository files unless it is independently appropriate project documentation.

## Migration

### Machine to Harness

- Rename `plugins/machine/` to `plugins/harness/`.
- Change manifest identity, skill names, documentation, tests, and marketplace entries from `machine` to `harness`.
- Preserve and relocate the current synchronization, manifest reconciliation, portability lint, model-data fetch, rubric-path, and link-plan mechanics.
- Add `harness:setup`; it orchestrates existing setup responsibilities rather than duplicating their scripts.
- Remove the `machine` plugin entry entirely after all callers migrate.

### PM to Harness

- Move `codex-implementation`, `codex-review`, and `codex-computer-use` into Harness as provider-neutral `execute`, `review`, and `computer-use` skills.
- Move `model-orchestration.md` and universal evidence rules into Harness references.
- Retain `work-readiness.md` and development-specific `review-proof.md` in PM; rewrite their universal portions as references to Harness.
- Replace rubric path reads, `via:` branching, explicit provider handling, and vendor-specific skill names in every PM skill and agent with Harness requests.
- Keep PM's issue/tracker, delivery-slice, review-axis, PR, and reconciliation behavior unchanged.

### Product Pulse to Harness

- Replace direct instructions to pick cheap/strong models and pass model values with semantic Harness routes.
- Map scanning and extraction to `bulk`, latency-sensitive work to `quick`, and synthesis/adjudication to `taste` or `review` as appropriate.
- Preserve Product Pulse's own source-quality and publication verification.

### Studio Baseline into Harness, then `agents`

- Move `studio-baseline/House_Rules.md` into `plugins/harness/references/house-rules.md`.
- Move `studio-baseline/AGENTS_Baseline.md` into `plugins/harness/templates/AGENTS_Baseline.md`.
- Fold Machine Setup and Rubric Setup guidance into `harness:setup`, `harness:sync`, `harness:model-rubric`, and their focused references.
- Delete `studio-baseline/` after every caller uses the Harness-owned paths; do not retain plugin-free duplicates.
- Replace Machine setup and model-orchestration reminders with the concise universal Harness Contract.
- Keep route values personal and user-global; project files contain only semantic behavior and setup discovery.
- Update `skills.manifest`, synced plugin declarations, instructions, and documentation to install `harness` and remove `machine`.
- Do not sync credentials, executor profiles containing secrets, temporary evidence, or Shelby state.

## Evaluation Strategy

The migration uses Anthropic's current official `skill-creator` evaluation workflow rather than `/skill-test`.

### Snapshot and baseline

Before implementation:

1. Snapshot the existing `machine`, PM, Product Pulse, Studio Baseline, and relevant `agents` configuration before Studio Baseline is subsumed.
2. Define realistic prompts that exercise the current overlap:
   - PM bounded implementation routed through a cross-vendor executor.
   - PM fixed-target review with independent evidence reproduction.
   - Product Pulse multi-source research with bulk fan-out and judgment-heavy synthesis.
   - Computer-use verification outside a PM workflow.
   - Missing rubric, missing executor, and missing Shelby cases.
   - A non-development task that should use Harness but not PM.
3. Save prompts and expected outputs in `evals/evals.json` using the official schema.
4. Run the existing plugin setup and capture transcripts, artifacts, duration, and tokens.

### Candidate evaluation

After implementation, run the same prompts against the new Harness setup. Launch old and new runs together for each eval so timing and environmental conditions remain comparable.

Assertions measure outcomes rather than phrases:

- The consumer selects a semantic route without reading or interpreting the rubric.
- The actual dispatch carries an explicit model and effort.
- Vendor/provider mechanics appear only in Harness.
- Required authority and working-directory constraints reach the executor.
- Worker-reported verification is independently reproduced.
- A changed fixed target invalidates prior proof.
- Missing optional Shelby does not block correct execution.
- Missing required capabilities produce a typed fallback or blocker rather than silent degradation.
- PM and Product Pulse preserve their domain-specific lifecycle and outputs.
- No `machine` plugin or `/machine:*` references remain in distributed configuration.

### Grading and comparison

- Grade each run against observable artifacts and transcripts using the official grader schema.
- Aggregate pass rate, time, tokens, tool calls, and variance with Anthropic's benchmark scripts.
- Generate the official eval viewer for human review.
- Blind the old/new labels and run the official comparator on output quality.
- Unblind only in the post-hoc analyzer to identify causal instruction or contract differences.
- Treat assertions that pass equally in old and new variants as non-discriminating and revise them.
- Require the new design to improve separation and retain or improve task success without unreasonable time/token regression.

### Trigger evaluation

After behavior stabilizes, test each new skill description with realistic should-trigger and near-miss should-not-trigger queries. Use the official held-out description optimization loop only after human review of the query set. The test must distinguish Harness setup/execution requests from PM lifecycle requests and ordinary tasks that need neither.

## Repository Tests

In addition to behavioral evals:

- Move and update Machine Bats tests under Harness.
- Add structural tests that fail while PM or Product Pulse reads `model-rubric.yml`, interprets `via:`, or names Harness-owned provider executors, or while a parallel `studio-baseline/` remains.
- Add contract tests for route resolution, explicit model/effort propagation, unavailable capabilities, verification state, and Shelby-present/Shelby-absent behavior.
- Run skill frontmatter and plugin manifest validation.
- Run portability lint and sync reconciliation against a temporary `agents` fixture.
- Run every Harness, PM, and Product Pulse test suite before commit and PR.
- Independently review the fixed final diff and rerun its highest stable tests.

The current local baseline cannot execute Bats suites because `bats` is not installed. Implementation must satisfy that prerequisite or run the same suites in an environment where it is present; absence is not a passing baseline.

## Security and Failure Handling

- Provider credentials and secret-bearing profiles remain user-global and untracked.
- Harness never prints secrets or copies them into handoffs, evidence, telemetry, or Shelby.
- External CLI execution preserves explicit working directory, sandbox, and user-approval boundaries.
- Computer-use actions retain their runtime confirmation policies.
- Optional Shelby failure degrades state enrichment only; it does not widen authority or change the route silently.
- Run logs and evidence store decisive output, not unbounded command logs.
- Hooks or future executable ledgers are treated as executable code and require explicit review before activation.

## Completion Criteria

The migration is complete when:

1. `plugins/harness` is the only setup/routing/execution plugin and `plugins/machine` no longer exists.
2. PM and Product Pulse consume the Harness Contract and contain no concrete model/provider/executor selection logic.
3. Studio Baseline has been subsumed and removed, and `agents` installs and describes Harness consistently.
4. The optional Shelby path and no-Shelby fallback both pass their behavioral tests.
5. All repository tests and validators pass.
6. The official old/new benchmark, viewer, blind comparison, and analyzer artifacts are produced.
7. The new setup retains or improves task success, demonstrates cleaner ownership, and has no unexplained material regression in time or tokens.
8. An independent fixed-target review finds no unresolved blocker.

## Sources

- [Anthropic skill-creator](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md) — current iterative eval, benchmark, viewer, blind comparison, and description-optimization workflow.
- [Claude Code skills](https://code.claude.com/docs/en/slash-commands) — current skill discovery, invocation, frontmatter, and progressive-disclosure behavior.
- [Claude Code extension model](https://code.claude.com/docs/en/features-overview) — roles of instructions, skills, subagents, agent teams, MCP, hooks, and plugins.
- [Claude Code plugins](https://code.claude.com/docs/en/plugins) — plugin packaging and local testing.
- `docs/research/deep-dives/model-harness-unbundling.md` — model/harness/context separation and accepted-task cost.
- `docs/research/deep-dives/evidence-gated-agent-completion.md` — evidence gates, parent reverification, and the decision not to duplicate orchestration.
