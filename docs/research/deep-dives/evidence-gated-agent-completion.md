---
title: Evidence-Gated Agent Completion for skills-n-stuff
resources:
  - url: https://www.youtube.com/watch?v=c47uqR7XB_c
    type: video
    title: GitHub's #1 Trending Author's New Claude Skill Is Insane
    published: 2026-08-20
  - url: https://github.com/Leonxlnx/unlazy
    type: repo
    title: unlazy
    published: unknown
  - url: https://www.youtube.com/watch?v=4HvFqhtCb-A
    type: video
    title: Stop Paying $200 For Work An $18 Model Can Do Inside Claude Code And Codex.
    published: 2026-08-21
tags: [verification, completion, subagents, orchestration, evidence, model-routing]
related_reports: [model-harness-unbundling]
---

# Evidence-Gated Agent Completion for skills-n-stuff

## Resource Summary

### AI Labs video

The video identifies two real failure modes in long agent sessions: declaring completion before all requested work is done, and silently narrowing the task around its difficult parts. It presents Unlazy's remedy as decomposition into fresh-context tasks plus a ledger in which each acceptance outcome has a runnable check, expected output, and recorded evidence. It also recommends parallelizing independent leaves and combining the workflow with model routing.

The video used uploader-provided manual captions and was published August 20, 2026. It is a useful walkthrough, not an evaluation: its claims that a modified ten-agent run produced a complete app in about two hours are not accompanied by reproducible artifacts. Its explanation that context growth causes “laziness” is plausible but more categorical than the evidence supports. **Confidence: High on the described workflow; Low on the claimed productivity improvement.**

### Unlazy repository

Current Unlazy source at commit `754d9a6` is more careful than the video. A runnable gate passes only when its command exits zero and its expected output matches; checked gates with pending evidence remain unmet; parent `--reverify` reruns already-passing checks. Malformed ledgers fail closed. Current orchestration supports rolling dispatch of ready leaves with declared disjoint ownership, while `--jobs` separately parallelizes independent checks. The repository explicitly says this coordination is not isolation and its research does not prove a fixed improvement. Its test suite passed 64/64 checks during this review. **Confidence: High.**

## Cross-Reference Analysis

The two videos address adjacent layers of the same system:

- `model-harness-unbundling.md` asks which model should execute a bounded task and how context crosses the boundary.
- This video asks what evidence permits the orchestrator to accept that task as complete.

Together they produce a stronger rule than either video states alone: cheaper or fresh-context agents are safe only after the parent fixes the outcome, testing seam, and acceptance oracle, then independently reruns it. Model routing without acceptance evidence creates cheap false completions; evidence gates without routing can be dependable but unnecessarily expensive.

The current Unlazy repository also resolves the video's main criticism of sequential dispatch: it now documents rolling parallel orchestration. The video's paid modified variant is therefore not required to obtain that behavior from current upstream source. **Confidence: High.**

## Ecosystem Context

### E1 — A command is evidence only for the oracle it implements

Unlazy correctly warns that a successful command and matching marker do not prove the English gate title. A weak test can produce impeccable evidence for the wrong outcome. The stable testing seam must therefore be chosen before implementation and reviewed for spec fidelity. **Confidence: High.**

### E2 — Reverification is stronger than worker-authored evidence

The valuable mechanism is not the checkbox; it is parent re-execution against a fixed target. Unlazy's leaf self-check → parent reverify → integration-gate hierarchy matches current software assurance practice and our own review doctrine. **Confidence: High.**

### E3 — Executable ledgers create a security boundary

Unlazy `CHECK:` entries are arbitrary shell commands with the user's filesystem, environment, credentials, and network access. Approval binds the declared command and environment, but does not sandbox it or hash scripts called transitively. A committed or externally supplied ledger must be reviewed as executable code. **Confidence: High.**

### E4 — Parallel coordination is not write isolation

Declared `OWNS:` paths and leases can prevent cooperating workers from obvious collisions, but they cannot restrict writes. Separate worktrees remain the stronger default for concurrent implementation, with ordering for shared caches, services, or generated state. **Confidence: High.**

## Project Comparison

`skills-n-stuff` already contains most of the operational doctrine:

- `plugins/pm/references/work-readiness.md` requires every delivery slice to name its Outcome, Blockers, Testing Seam, and Proof before it can be completed.
- `plugins/pm/references/review-proof.md` fixes the reviewed commit or immutable snapshot, distinguishes Direct proof from supporting evidence, and reopens review whenever that fixed point changes.
- `plugins/pm/skills/sprint-dev/SKILL.md` says “trust the check, not the worker,” executes only the unblocked frontier, independently reruns verification, and separates colliding work.
- `plugins/harness/skills/execute/SKILL.md` treats an executor exit code and worker report as claims, guards against success-shaped no-op results, and requires the accepting parent to reproduce the highest stable verification seam.
- `plugins/harness/references/house-rules.md` requires the highest stable testing seam, recorded output, independent checks, and worktrees for parallel changes.

That is roughly the same completion model without Unlazy's machine-readable ledger. The material gap is enforcement: our Outcome/Testing Seam/Proof contract lives in issue bodies, prompts, reviews, and reports. No shared parser can fail closed on missing gates, distinguish stale evidence from current re-execution, or produce one deterministic completion record for a multi-agent slice.

The tree-depth interface is not a useful addition. Our change classes and delivery-slice frontier choose ceremony from actual scope and dependencies; an arbitrary number risks filler tasks and unnecessary agent cost. Current Unlazy itself now advises the smallest honest decomposition rather than treating depth as an effort multiplier.

## Risks & Gaps

- **R1 — Duplicate orchestration:** installing Unlazy wholesale would overlap PM planning, work readiness, parallel scheduling, worktrees, and review. Two sources of truth would drift. **Confidence: High.**
- **R2 — Oracle theater:** converting every acceptance sentence into `EXPECT: passed` can make weak checks appear stronger without improving coverage. **Confidence: High.**
- **R3 — Executable supply chain:** a checked-in gate file or hook can run arbitrary commands with ambient credentials. **Confidence: High.**
- **R4 — Ceremony inflation:** mandatory ledgers for Polish and narrow Small changes would violate the repository's change-class discipline and waste attention. **Confidence: High.**
- **R5 — Evidence loss:** the current prose-based contract can be scattered across a tracker, agent report, terminal transcript, and PR, making stale or missing proof harder to detect mechanically. **Confidence: High.**

## Prior Research

We investigated provider routing and context handoffs in `model-harness-unbundling.md` and concluded that accepted-task cost—not token price—must include retries, review, latency, and rejection. This research extends that conclusion: “accepted” needs an explicit, independently rerun completion contract. It also reinforces the prior action to collect outcome telemetry rather than merely counting dispatches.

## Sources

- [AI Labs video](https://www.youtube.com/watch?v=c47uqR7XB_c) — practitioner walkthrough, published August 20, 2026.
- [Unlazy repository](https://github.com/Leonxlnx/unlazy/tree/754d9a68109e39b836cc72a39fb9a823f9d6b613) — audited implementation at the reviewed commit.
- [Gate contract](https://github.com/Leonxlnx/unlazy/blob/754d9a68109e39b836cc72a39fb9a823f9d6b613/references/gates.md) — success, evidence, approval, and abandonment semantics.
- [Orchestration reference](https://github.com/Leonxlnx/unlazy/blob/754d9a68109e39b836cc72a39fb9a823f9d6b613/references/orchestration.md) — rolling dispatch and verification hierarchy.
- [Security boundary](https://github.com/Leonxlnx/unlazy/blob/754d9a68109e39b836cc72a39fb9a823f9d6b613/SECURITY.md) — arbitrary-command and environment risks.
- [Prior model–harness video](https://www.youtube.com/watch?v=4HvFqhtCb-A) — routing and context-handoff thesis.

## Action Items

| # | Action | Why | Effort | Confidence |
|---|--------|-----|--------|------------|
| 1 | Prototype one machine-readable acceptance ledger inside PM for Feature-class and sprint delivery slices, generated from the existing Outcome/Testing Seam/Proof contract. | Tests the useful enforcement mechanism without replacing the doctrine or imposing it on small work. | Moderate | High |
| 2 | Require the parent to rerun each runnable ledger entry against the fixed review SHA and invalidate proof when the SHA or oracle changes. | Prevents worker-authored and stale evidence from closing a task. | Moderate | High |
| 3 | Feed gate attempts, failures, re-verifications, abandonments, elapsed time, and accepted outcome into the routing telemetry proposed in `model-harness-unbundling.md`. | Connects model choice to verified accepted-task cost. | Significant | High |
| 4 | Do not adopt tree-depth selection, a second planner, or the Stop hook by default. Treat Unlazy as a reference implementation and reuse only the minimal parser/checker ideas that survive a PM pilot. | Preserves one source of truth and current change-class discipline. | Quick win | High |
| 5 | If executable ledgers are piloted, keep them untrusted until reviewed, restrict them to repository-owned checks, cap evidence, and keep runtime approval/state outside Git. | Controls the main security and portability risks. | Moderate | High |
