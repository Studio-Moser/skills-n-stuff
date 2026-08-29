---
title: "Agent-Native Harness and PM: Automate the Waiting, Preserve the Decisions"
resources:
  - url: https://www.youtube.com/watch?v=TlmTypTQFj8
    type: video
    title: The hidden truth inside Firstmate AI
    published: 2026-08-27
tags: [agent-orchestration, harness, product-management, verification, supervision, worktrees, telemetry]
related_reports: [evidence-gated-agent-completion, model-harness-unbundling]
---

# Agent-Native Harness and PM: Automate the Waiting, Preserve the Decisions

## Research Coverage

This deep dive synthesizes the uploader-provided manual transcript, two accepted and evidence-proven research branches, current ecosystem evidence, the fixed project target `b980db72e16bd0f9420dfb4df5a282da2cd088b7`, and the prior reports `evidence-gated-agent-completion.md` and `model-harness-unbundling.md`.

Coverage is complete: **2 branches expected, 2 completed, 2 accepted and evidence-proven, 0 failed, 0 blocked, and 0 unproven**.

- **Harness comparison:** accepted and proven; bulk research; `gpt-5.6-terra@high`; OpenAI native; primary.
- **PM comparison:** accepted and proven; bulk research; `gpt-5.6-terra@high`; OpenAI native; primary.

Both bulk requests encountered the same execution anomaly: the selected native worker-session dispatch returned an untyped `no thread with id` collaboration failure. This is **not evidence of provider unavailability** and did not authorize typed provider fallback. The selected native parent runtime completed each unchanged request and reproduced the evidence. The anomaly is evidence for a typed supervision or executor-event seam because an untyped child-session failure currently cannot distinguish lifecycle loss, stale session identity, dispatch failure, or provider health.

Parent reproduction reopened the project HEAD and clean status, the pinned project claims, and the external heads. AXI remained at `d28c5e7`, gh-axi at `84112b7`, and no-mistakes at `554474f`. Firstmate advanced during synthesis from `4eb587d` to `c731c36` by one commit that extracts a harness-adapter operations reference, prunes duplicate instruction ownership, and adds an instruction evaluation. The compared orchestration, worktree, authority, and supervision behavior did not change. The update reinforces the maintenance lesson: agent instruction systems require continual ownership cleanup and evaluation, not unbounded accumulation.

The project audit confirmed the cited Harness request, routing, handoff, authority, and verification mechanisms; the PM ingest, triage, sprint-dev, reconcile, readiness, and review-proof mechanisms; and the approved provider-neutral evaluation design. The Harness test surface at the pinned target contains 28 test files: 27 Bats files with 213 `@test` cases plus one fixture; its test runner is separate.

## Resource Summary

Hal Shin’s video presents Firstmate as a clone-and-run personal “agent distro,” not a hosted application or a new model harness. A person talks to one liaison; that liaison scopes work, briefs workers, starts each worker in a separate Git worktree and visible terminal session, supervises progress through shell scripts and durable state, verifies the returned outcome, and asks for merge authority. The transcript’s strongest contribution is not the nautical interface. It is the proposition that recurring attention costs should be moved from human memory and polling into explicit software contracts.

The transcript describes five operating rules: the orchestrator is read-only over project code; workers operate in worktrees; merge requires the captain’s approval; unlanded work is not torn down; workers report through the first mate; and outcomes, including failures, are reported faithfully. Current Firstmate source qualifies the first rule with narrow guarded project-write exceptions and configurable delivery modes, including optional standing `+yolo` authority. That evolution matters: the resource is a snapshot of a rapidly changing personal stack, not a stable specification.

Four transferable principles emerge:

1. **Wrap an existing CLI only around repeated agent friction.** Shape output, defaults, counts, recovery instructions, and error types around the recurring decision the agent must make.
2. **Build a missing personal CLI only when repeated use justifies ownership.** Personal software may accept a narrower compatibility surface, but publication raises its maintenance and support obligations.
3. **Verify the outcome instead of making a person babysit every tool call.** This is valuable only when the environment, authority ceiling, fixed target, and exit proof together cover both mid-run and final-state risk.
4. **Use shared conventions, then prune them.** A consistent lifecycle reduces cognitive load, but instructions, wrappers, and automations become maintenance inventory and must earn their place continuously.

The video’s quantitative claims remain attributed claims. Its roughly 35% byte reduction has no published frozen fixture in the supplied evidence. Its statement that gh-axi reduces six-to-eight turns to three is not supported by the current published AXI table as stated: the maintainer study reports three average turns for both gh-axi and raw `gh`. The current study is still useful, but its scope is narrow: 17 GitHub tasks, five interface conditions, five repeats, 425 total runs, one target repository, and Claude Sonnet 4.6 as both agent and judge. It reports 100% success for gh-axi versus 86% for raw `gh`, but transfer to this project, other models, other repositories, or other workflow classes is unknown. No measured local productivity or cost gain is claimed here.

The central conclusion is therefore narrower than “build your own Firstmate”: **automate the waiting and proof transport; do not automate the product decision.** Scripts can monitor, classify deterministic lifecycle states, preserve evidence, and surface exceptions. They must not silently decide ambiguous scope, priority, acceptance criteria, destructive or external actions, or merge policy.

## Ecosystem Context

### Personal agent distributions are becoming operational systems

At the `4eb587d` snapshot, Firstmate documented one liaison, visible workers, isolated worktrees, explicit delivery modes, durable state, and an event-driven Bash watcher. Its architecture places scripted mechanics below the agent’s judgment: the watcher sleeps until a status is actionable, while the first mate retains intake, escalation, and reporting. Current head `c731c36` preserves that model while moving harness-specific operations out of the always-loaded instruction surface and adding an evaluation. This is concrete evidence that instruction size and ownership are operating concerns, not cosmetic cleanup.

Firstmate had no GitHub releases at the synthesis snapshot. It is consumed from a moving branch, and its head changed during this research. That makes it a useful reference implementation but a poor wholesale dependency for a project that needs pinned, provider-neutral behavior.

### Agent-facing interfaces need task-level evidence

AXI’s maintained principles—minimal default schemas, progressive disclosure, structured recovery, and consistent help—are sensible interface heuristics. The accompanying GitHub study provides stronger evidence than the video’s byte-count anecdote because it publishes the task matrix and aggregate results. Even so, it is a maintainer-run benchmark with a single agent/judge model and a single GitHub target. The evidence supports evaluating narrow wrappers against representative tasks; it does not support a general rule that wrappers beat native CLIs or MCP in every environment.

The project’s approved testing design supplies the right local evaluation seam. `docs/superpowers/specs/2026-08-28-harness-testing-design.md` pins Harbor, ATIF, and RewardKit; separates correctness, workflow integrity, and efficiency; admits only correct trials to comparative efficiency claims; and records missing telemetry as unknown rather than zero. That is a better basis for a wrapper or supervision decision than star counts, byte counts, or one maintainer benchmark.

### Exit validation does not erase mid-run authority

no-mistakes is a state-changing delivery pipeline: it accepts a branch, uses a disposable worktree, runs review/test/docs/lint/CI stages, may apply safe fixes, pushes to a configured target, and opens a pull request only after its gates pass. Its current documentation also preserves user decisions for findings that require judgment. Those are valuable delivery mechanics, but they overlap Harness and PM’s existing fixed-target proof and PR lifecycle.

The transcript’s stronger claim—that disposable worktrees plus exit validation can replace interactive safety—does not transfer intact. A Git worktree isolates the checkout and branch state. It does not isolate credentials, the network, external services, ambient filesystem paths, shared caches, or destructive commands. This is an inference from Git worktree’s scope and the project’s explicit authority model. Harness must retain tool, path, sandbox, and approval ceilings during execution, then verify the outcome at exit.

### The market signal is attention management, not autonomous product ownership

Firstmate, AXI, no-mistakes, and the project’s own Harness/PM architecture converge on a useful split:

- deterministic software should carry lifecycle state, fixed targets, routing provenance, retries, and proof;
- agents should perform bounded judgment and implementation;
- the product owner should retain decisions whose correctness depends on intent rather than observable mechanics.

The valuable automation target is the interval between meaningful events. A quiet worker that remains within its authority should not demand attention. A decision, blocker, failed or invalidated check, stuck task, external effect, or merge-ready outcome should.

## Project Comparison

### Harness

**Observation.** `plugins/harness/references/harness-contract.md`, `plugins/harness/references/routing.md`, `plugins/harness/references/handoff.md`, and `plugins/harness/references/verification.md` already implement the transferable Firstmate ideas at a stricter boundary: one top-level orchestrator owns the user conversation and acceptance; consumers submit provider-neutral typed requests; Harness resolves an explicit model, effort, provider, and executor; authority is a ceiling; fallback is limited to typed availability; workers return a typed result; and the accepting parent reproduces the highest stable verification seam against a fixed target. Parallel-worktree guidance is carried by the project baseline and PM scheduling rules.

**Source attribution.** These observations come from the pinned project target, not the video. The video and Firstmate source provide the external comparison; the Harness contract and execution skills establish current project behavior.

**Inference.** A Firstmate-style general orchestrator, wrapper suite, or validation pipeline would duplicate mechanisms Harness already owns and create two sources of truth for routing, authority, handoff, and acceptance. The transferable design unit is smaller: aggregate existing results and, if repeated failures justify it, add a typed executor/supervision event at the executor boundary.

**Unknowns.** Harness Results expose attempts, elapsed time when available, verification failures, token or quota usage when available, and final acceptance per request, but the repository does not aggregate these fields across accepted tasks. It is therefore unknown whether a wrapper, additional supervision, or a different route would reduce accepted-task cost locally. Persistent background supervision is also unproven as a Harness-core requirement; no accepted evidence shows that Harness itself should own a daemon.

**Confidence: High** that the current contract, authority, routing, handoff, and evidence mechanisms already cover the reusable architecture. **Confidence: High** that aggregate accepted-task telemetry is a real gap. **Confidence: Medium** that a narrow typed executor-event seam will be warranted; the repeated untyped child-session anomaly is evidence of friction, but not yet a complete interface design.

### PM

**Observation.** PM already owns the single product liaison. `plugins/pm/skills/ingest/SKILL.md` creates reversible `status/needs-triage` candidates and explicitly says proposed outcomes are not commitments. `plugins/pm/skills/triage/SKILL.md` requires user confirmation before rejection, promotion, readiness-note persistence, or verdict mutation. `plugins/pm/skills/sprint-dev/SKILL.md` builds only approved work from the dependency-aware unblocked frontier, separates scheduling collisions, uses worktrees, submits bounded Harness execution and immutable fixed-target review requests, reproduces the Testing Seam, and never auto-builds. `plugins/pm/references/work-readiness.md` and `plugins/pm/references/review-proof.md` make Outcome, Blockers, Testing Seam, Proof, immutable artifacts, positive acceptance signals, and invalidation rules explicit. `plugins/pm/scripts/check-transition.sh` and `plugins/pm/scripts/materialize-review-artifact.sh` are narrow deterministic interfaces for transition and review integrity.

**Source attribution.** These are direct observations from the pinned PM skills, references, and scripts. The video’s “one captain conversation” is analogous, but it is not the source of the project mechanism.

**Inference.** PM, not Harness or an agent fleet, is the correct owner of product decisions. Harness should execute a bounded approved slice; workers should report discovered work without expanding it; PM should decide whether that work changes scope, priority, acceptance criteria, or scheduling. This is the operational distinction between automating the waiting and automating the product decision.

**Observation of gaps.** Sprint-dev currently requires “Report live. Tell the user about each PR as it completes, don’t batch results.” That policy turns routine completion cadence into attention demand. Triage is described as batch-friendly for sorting and scoring, but its confirmation loop remains item-by-item. Reconcile automatically mutates spawned-item blocker or independent classification from heuristics such as issue references, open-parent status, and “nice-to-have” judgment.

**Inference.** Routine progress should be quiet or digestible; decisions, blockers, failures, invalidated proof, stuck work, and terminal PR-ready outcomes should surface promptly. Reversible, high-confidence triage recommendations can be presented as one numbered decision set with “accept all except” overrides. Reconcile should auto-apply only deterministic explicit parent dependencies; heuristic blocker classifications should be an evidence-backed approval digest.

**Unknowns.** PM has no durable typed projection of all in-flight outcomes and open decisions. Tracker state, branches, Harness Results, review artifacts, and conversation state together carry the truth, but no current artifact projects `working`, `needs-decision`, `blocked`, `failed`, and `accepted` with a decision owner and evidence pointer. It is unknown whether a watcher is needed; current evidence supports a small projection first, not background infrastructure.

**Confidence: High** in PM’s current product-ownership and proof boundaries, the live-reporting attention gap, and the unsafe breadth of heuristic automatic blocker mutation. **Confidence: Medium-high** in batched reversible triage confirmation. **Confidence: Medium** that a minimal outcome/open-decision projection will materially improve restart recovery; it must be validated before adding a watcher.

## Risks & Gaps

- **R1 — False isolation.** Treating worktrees as a security sandbox would leave credentials, network calls, external services, shared state, and non-worktree filesystem writes outside the claimed boundary. Preserve Harness authority ceilings. **Confidence: High.**
- **R2 — Duplicate control planes.** Wholesale Firstmate or no-mistakes adoption would duplicate orchestration, routing, worktrees, validation, PR lifecycle, and proof ownership. Divergent state would make failures harder to adjudicate. **Confidence: High.**
- **R3 — Outcome-only safety.** A green exit gate cannot undo a destructive external action or unauthorized mid-run effect. Final verification complements, but does not replace, path, tool, sandbox, approval, and merge authority. **Confidence: High.**
- **R4 — Attention automation that becomes notification debt.** Reporting every routine PR cycle preserves chronology but recreates tab-juggling in one conversation. Event policy must distinguish routine progress from decisions and exceptions. **Confidence: High.**
- **R5 — Heuristic product mutation.** Automatically converting inferred blocker relationships into tracker state can change scope and priority indirectly. Only explicit, deterministic dependency evidence should bypass approval. **Confidence: High.**
- **R6 — Wrapper maintenance without measured value.** Every wrapper inherits upstream API changes, security work, packaging, documentation, and evaluation. The current project has no local accepted-task evidence that an AXI-style wrapper pays for that inventory. **Confidence: High.**
- **R7 — Telemetry without aggregation.** Per-request Result fields cannot answer model, executor, supervision, or wrapper economics until accepted outcomes are aggregated with retries, verification failures, time, and available usage. Missing values must remain unknown. **Confidence: High.**
- **R8 — Premature daemon.** A general background fleet service would add lifecycle, concurrency, recovery, and security obligations before repeated asynchronous work proves the need. A consumer or executor may eventually own persistent supervision; Harness core should not assume it. **Confidence: Medium-high.**
- **R9 — Moving external targets.** Firstmate had no releases and changed during synthesis. Unpinned adoption would make comparative claims and regressions difficult to reproduce. **Confidence: High.**
- **R10 — Benchmark overreach.** The AXI study supports a bounded experiment, not general transfer. Same-model agent/judge use, one repository, and small task families limit external validity. **Confidence: High.**

The non-negotiable authority boundary across these risks is explicit: ambiguous scope, priority, acceptance criteria, destructive or external actions, and merge policy remain user decisions. Automation may prepare evidence and recommendations; it may not manufacture consent.

## Prior Research

Two conclusions are **reinforced**, not new.

First, `evidence-gated-agent-completion.md` already established that worker output and exit zero are claims; the accepting parent must re-run the highest stable Testing Seam against a fixed target. It also established that parallel coordination and declared file ownership are not write isolation. This report reinforces both conclusions with Firstmate’s worktree model and with the native child-session anomaly: reliable completion depends on typed lifecycle evidence plus parent reproduction, not worker confidence or terminal visibility.

Second, `model-harness-unbundling.md` already established provider-neutral handoff, explicit routing, authority preservation, and accepted-task economics rather than token-price comparison. It identified aggregate Harness Result telemetry as missing. This report reinforces that gap and connects it to the approved Harbor/ATIF/RewardKit design: correctness and integrity must gate any efficiency comparison, and missing usage data must remain unknown.

The genuinely **new conclusions** are at the PM and supervision boundaries:

1. **N1 — Outcome-event reporting policy.** PM should surface decisions, blockers, failures, invalidated proof, stuck work, and terminal PR-ready outcomes while making routine progress quiet or digestible.
2. **N2 — Approval-digest triage and reconcile.** Reversible recommendations can be batched with explicit overrides; ambiguous rejection, scope, priority, criteria, and inferred dependency changes remain individually controlled.
3. **N3 — Minimal outcome/open-decision projection.** Before any watcher, PM should test a typed projection of in-flight outcome state, decision owner, and evidence pointer for summary and restart recovery.
4. **N4 — Typed supervision failure seam.** The repeated untyped `no thread with id` failure justifies investigating a narrow executor-event type. It does not prove provider unavailability and does not yet justify a persistent Harness daemon.
5. **N5 — Instruction pruning as evaluated maintenance.** Firstmate’s one-commit head change shows that adapter instructions benefit from explicit ownership, extraction, duplicate removal, and evaluation. Shared conventions are maintained products, not write-once prompt assets.

## Sources

### Primary resource and Firstmate

- [Hal Shin, “The hidden truth inside Firstmate AI”](https://www.youtube.com/watch?v=TlmTypTQFj8) — primary video, published August 27, 2026; this report used the uploader-provided full manual transcript.
- [Firstmate README at the research snapshot](https://github.com/kunchenguid/firstmate/blob/4eb587d670ff1a34afaba32fa94d02e74fed0399/README.md) — one liaison, worktrees, delivery modes, supervision, and authority.
- [Firstmate architecture at the research snapshot](https://github.com/kunchenguid/firstmate/blob/4eb587d670ff1a34afaba32fa94d02e74fed0399/docs/architecture.md) — event-driven watcher, lifecycle state, and delivery mechanics.
- [Firstmate operating contract at the research snapshot](https://github.com/kunchenguid/firstmate/blob/4eb587d670ff1a34afaba32fa94d02e74fed0399/AGENTS.md) — instruction and authority surface.
- [Firstmate snapshot-to-current comparison](https://github.com/kunchenguid/firstmate/compare/4eb587d670ff1a34afaba32fa94d02e74fed0399...c731c36c381ea0886fa5aabf6a3be761534d3f30) — the single instruction/reference extraction and evaluation commit observed during synthesis.
- [Firstmate releases](https://github.com/kunchenguid/firstmate/releases) — no published releases at the synthesis snapshot.
- [Git worktree documentation](https://git-scm.com/docs/git-worktree) — defines checkout/worktree scope; broader security isolation is not provided by this mechanism.

### AXI and validation

- [AXI principles at `d28c5e7`](https://github.com/kunchenguid/axi/blob/d28c5e79aa7ee7a59a386fc34125f8cd1470fbeb/.agents/skills/axi/SKILL.md) — agent-facing CLI design principles.
- [AXI GitHub benchmark study at `d28c5e7`](https://github.com/kunchenguid/axi/blob/d28c5e79aa7ee7a59a386fc34125f8cd1470fbeb/bench-github/published-results/STUDY.md) — 17 tasks × 5 conditions × 5 repeats, methodology, and aggregate results.
- [gh-axi at `84112b7`](https://github.com/kunchenguid/gh-axi/tree/84112b7897fc1d0833f2727a817ecc91a297c3ef) — wrapper implementation snapshot.
- [no-mistakes at `554474f`](https://github.com/kunchenguid/no-mistakes/blob/554474f66423ad3f6021fc934077cc3a54e20158/README.md) — state-changing validation and PR pipeline.

### Current project and prior research

- [Harness contract at the fixed project target](https://github.com/Studio-Moser/skills-n-stuff/blob/b980db72e16bd0f9420dfb4df5a282da2cd088b7/plugins/harness/references/harness-contract.md) — typed Request and Result ownership.
- [Harness routing at the fixed project target](https://github.com/Studio-Moser/skills-n-stuff/blob/b980db72e16bd0f9420dfb4df5a282da2cd088b7/plugins/harness/references/routing.md) — explicit semantic resolution and typed availability-only fallback.
- [Harness verification at the fixed project target](https://github.com/Studio-Moser/skills-n-stuff/blob/b980db72e16bd0f9420dfb4df5a282da2cd088b7/plugins/harness/references/verification.md) — fixed targets, direct proof, and acceptance.
- [PM sprint-dev at the fixed project target](https://github.com/Studio-Moser/skills-n-stuff/blob/b980db72e16bd0f9420dfb4df5a282da2cd088b7/plugins/pm/skills/sprint-dev/SKILL.md) — liaison ownership, approval, frontier dispatch, worktrees, review, and live reporting.
- [PM triage at the fixed project target](https://github.com/Studio-Moser/skills-n-stuff/blob/b980db72e16bd0f9420dfb4df5a282da2cd088b7/plugins/pm/skills/triage/SKILL.md) — reversible recommendations and explicit mutation gates.
- [PM reconcile at the fixed project target](https://github.com/Studio-Moser/skills-n-stuff/blob/b980db72e16bd0f9420dfb4df5a282da2cd088b7/plugins/pm/skills/reconcile/SKILL.md) — current heuristic automatic blocker classification.
- [PM work readiness at the fixed project target](https://github.com/Studio-Moser/skills-n-stuff/blob/b980db72e16bd0f9420dfb4df5a282da2cd088b7/plugins/pm/references/work-readiness.md) — delivery slices, dependency frontier, collisions, and Testing Seam.
- [PM review proof at the fixed project target](https://github.com/Studio-Moser/skills-n-stuff/blob/b980db72e16bd0f9420dfb4df5a282da2cd088b7/plugins/pm/references/review-proof.md) — immutable review input and positive acceptance proof.
- [Harness testing design](https://github.com/Studio-Moser/skills-n-stuff/blob/b980db72e16bd0f9420dfb4df5a282da2cd088b7/docs/superpowers/specs/2026-08-28-harness-testing-design.md) — pinned Harbor/ATIF/RewardKit evaluation and correctness/integrity/efficiency separation.
- [Evidence-Gated Agent Completion](https://github.com/Studio-Moser/skills-n-stuff/blob/b980db72e16bd0f9420dfb4df5a282da2cd088b7/docs/research/deep-dives/evidence-gated-agent-completion.md) — parent re-verification, worktree limits, and completion evidence.
- [Model–Harness Unbundling](https://github.com/Studio-Moser/skills-n-stuff/blob/b980db72e16bd0f9420dfb4df5a282da2cd088b7/docs/research/deep-dives/model-harness-unbundling.md) — provider-neutral handoff and accepted-task economics.

## Action Items

| # | Action | Why | Effort | Confidence |
|---|--------|-----|--------|------------|
| A1 | Aggregate accepted-task economics from existing Harness Results. | Routing and interface choices cannot be evaluated from per-run claims or token price alone. | Significant | High |
| A2 | Replace routine PM progress messages with typed outcome-event reporting. | Decisions and failures need attention; routine cycles do not. | Moderate | High |
| A3 | Batch reversible triage choices and require approval for inferred dependencies. | This reduces interaction fragmentation without manufacturing product consent. | Moderate | Medium-high |
| A4 | Evaluate a narrow supervision seam only after traces prove repeated friction. | The repeated untyped child-session failure merits investigation, not a general daemon. | Moderate, conditional | Medium |

### A1 — Aggregate accepted-task economics

- **Rank / priority:** 1 / High
- **Owner:** Harness maintainers
- **Outcome:** Aggregate existing Harness Results by requested route, actual model, effort, provider, executor, resolution, attempts, elapsed time, verification failures, available usage, and final acceptance. Keep missing telemetry explicitly unknown.
- **Dependencies:** Existing Harness Result schema; sanitized result storage or audit input.
- **Validation seam:** Run the pinned Harbor/ATIF/RewardKit comparison on representative tasks. Correctness and integrity must pass before comparing runtime, tokens, tool calls, retries, or cost. Confirm aggregates reproduce source Result records exactly.
- **Evidence trace:** Harness finding H7; `model-harness-unbundling.md`; `evidence-gated-agent-completion.md`; Harness testing design.
- **Non-goals:** No model leaderboard from price alone; no inferred token values; no wrapper adoption; no provider change.

### A2 — Replace routine progress with typed outcome-event reporting

- **Rank / priority:** 2 / High
- **Owner:** PM maintainers
- **Outcome:** Define a small reporting policy and projection with `working`, `needs-decision`, `blocked`, `failed`, and `accepted`; a decision owner; and an evidence pointer. Routine progress is silent or digestible. Decisions, blockers, failures, invalidated proof, stuck work, and terminal PR-ready outcomes surface promptly.
- **Dependencies:** Existing PM tracker state, Harness Result, and review-proof artifact; A1 only if accepted-task aggregates are included in summaries.
- **Validation seam:** Replay representative sprint traces, including restart recovery, and verify that every decision or failure surfaces once, routine cycles do not produce one notification per PR phase, and every terminal outcome resolves to current evidence.
- **Evidence trace:** PM findings P4 and P7; native child-session anomaly; prior completion-ledger gap.
- **Non-goals:** No background watcher or daemon; no new product decisions; no automatic merge; no hidden failure suppression.

### A3 — Batch reversible triage decisions and gate inferred dependencies

- **Rank / priority:** 3 / Medium
- **Owner:** PM maintainers
- **Outcome:** Present lightweight reversible triage recommendations as one numbered decision set supporting “accept all except.” Keep ambiguous rejection, scope, priority, acceptance criteria, and brainstorming individually explicit. Auto-apply only deterministic explicit parent dependencies; present heuristic blocker/independent classifications as an evidence-backed approval digest.
- **Dependencies:** Existing triage scorecard, transition checker, tracker backend adapters, and work-readiness dependency definition.
- **Validation seam:** Use PM evaluation fixtures to prove bulk overrides map to the intended items, ambiguous cues stop for input, no failed readiness gate is bypassed, and heuristic-only dependency evidence cannot mutate tracker state without confirmation.
- **Evidence trace:** PM findings P5 and P6; current triage and reconcile source.
- **Non-goals:** No batch approval for destructive actions; no inferred scope or priority; no change to explicit user control over acceptance criteria or item rejection.

### A4 — Evaluate a narrow supervision seam only after traces prove repeated friction

- **Rank / priority:** 4 / Conditional
- **Owner:** Harness maintainers for executor events; the owning consumer or executor for any background lifecycle
- **Outcome:** If repeated traces show the same unresolved child-session failure, define the smallest typed event needed to distinguish dispatch accepted, running, terminal success, terminal task failure, lifecycle/session loss, and typed provider availability. Evaluate any AXI-style wrapper against the same tasks before adopting it.
- **Dependencies:** A1 telemetry; A2 outcome projection; a reproducible corpus containing the `no thread with id` anomaly or equivalent lifecycle failures.
- **Validation seam:** Add deterministic adapter fixtures for each event and run the approved provider-neutral benchmark. The parent must still reproduce outcome proof, and untyped errors must not authorize provider fallback.
- **Evidence trace:** Harness findings H8 and the execution anomaly; Firstmate’s event-driven watcher; AXI benchmark limitations.
- **Non-goals:** No general Harness daemon; no wholesale Firstmate, AXI, gh-axi, or no-mistakes adoption; no weakened sandbox, path, tool, approval, external-action, or merge boundary.

This sequence deliberately starts with observability, then reduces attention cost, then compresses reversible approvals, and only then considers a new executor interface. It automates waiting and evidence transport while preserving explicit user authority over ambiguous scope, priority, acceptance criteria, destructive or external actions, and merge policy.
