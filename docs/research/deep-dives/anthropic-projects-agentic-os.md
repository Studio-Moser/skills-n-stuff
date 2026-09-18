---
title: "Anthropic Projects Is a Host, Not a Replacement for skills-n-stuff"
resources:
  - url: https://www.youtube.com/watch?v=afVpjeoQF2I
    type: video
    title: "Anthropic Just Built It’s Own Agentic OS"
    published: 2026-09-18
tags: [anthropic-projects, claude-code, agent-orchestration, memory, portability, harness, pm]
related_reports: [agent-native-harness-and-pm, evidence-gated-agent-completion, model-harness-unbundling]
---

# Anthropic Projects Is a Host, Not a Replacement for skills-n-stuff

Anthropic’s new Projects beta commoditizes Claude-only cloud coordination and the need to wait on individual coding sessions. It does not replace skills-n-stuff’s differentiated layers: provider-neutral portability, enforced authority, independent proof, local capabilities, research and product-management decision ownership, or shared team tracking.

## Research Coverage

This report synthesizes one accepted and evidence-proven research branch against project commit `cf023755cfe7bc546402d292d1ea85c0c7be73e1`. The accepted branch used the uploader-provided manual transcript, five official Anthropic pages reopened by the parent on 2026-09-18, and the project files reproduced in the research packet.

Coverage is degraded: **4 branches expected; 1 accepted/proven; 1 failed; 0 blocked; 0 abandoned; 2 unproven**.

- **resource-extraction-initial:** unavailable; no result; evidence unproven; blocker: missing Harness Result; elapsed unavailable.
- **ecosystem-comparison-initial:** unavailable; no result; evidence unproven; blocker: missing Harness Result; elapsed unavailable.
- **combined-recovery:** failed; evidence `not_proven`; blocker: Codex worker returned an untyped failure with an empty report; elapsed 102 seconds.
- **resource-extraction-clean-retry:** accepted; evidence proven; route `gpt-5.6-terra@high` via Codex; worker elapsed 255 seconds. The parent corrected four verdicts and two file references, reopened all five official citations and all project references, and accepted the corrected result.

The ecosystem-comparison branch never produced a result. Accordingly, the Ecosystem Context section is limited to facts established by the accepted branch’s official Anthropic citations. It does not claim broader market coverage.

The video is fresh relative to the launch: Anthropic’s announcement is dated 2026-09-17 and the video 2026-09-18. Its creator nevertheless states, “I don't even have access myself yet to test this.” The video is therefore a timely secondary explanation, not hands-on validation. It also promotes the creator’s paid community and gives an unsourced “67% of our community” statistic, which weakens confidence in its market and replacement framing without changing independently verified product facts.

**Confidence: High** in the corrected product and project findings; **Low** in ecosystem completeness because the dedicated ecosystem branch produced no result.

## Resource Summary

The video describes the new Projects beta as one long-running conversation in which Claude coordinates work while delegated threads execute it. Official documentation supports the core model: a project is an ongoing coordinating conversation, and each thread is a Claude Code cloud session working on its own branch and repository copy. Threads can further split work through subagents, loops, and workflows. This is a **video claim confirmed by official product facts**. **Confidence: High.**

Each thread starts with the project’s repositories, instructions, and memory. Threads load `CLAUDE.md`, skills, and plugins from every repository, and read the `MEMORY.md` index at startup. A Library tab collects files added to the project and files produced by threads. Permission rules, hooks, and environment configuration apply only when the project contains one repository. Plugins may also be selected in Project settings. These are **official product facts**, correcting the captioned “memory.mmd file” wording and the video’s simplified account of repository configuration. **Confidence: High.**

The current beta is Claude Code-only, cloud-hosted, gradually rolling out on Pro and Max plans, and not yet available on Team or Enterprise. Projects are absent from the terminal CLI, Amazon Bedrock, Google Cloud’s Agent Platform, and Microsoft Foundry. Anthropic says chat, Cowork, Team, and Enterprise expansion is planned, while local execution behind a user’s network is “coming very soon.” Timing and final behavior remain unknown. **Confidence: High on current availability; Low on delivery timing.**

The project conversation itself has no connectors. Work requiring a connector must be sent to a thread. A local session cannot join a Project, and cloud threads do not inherit the Claude Code setup on the user’s machine. Threads can pause for permission prompts, use plan limits faster, and lose uncommitted changes if a paused sandbox cannot resume and the task continues from a fresh clone. A project that works on code needs it on `github.com` with the Claude GitHub App installed; a project without a repository can still research and write documents. These are **official product facts**, not conclusions drawn from the video. **Confidence: High.**

Two video claims conflate the new beta with legacy chat/Cowork Projects:

- Automatic RAG through a “project knowledge search tool” is documented for legacy Projects. The current Claude Code Projects documentation instead describes automatic thread compaction and context drawn from recent messages, recent threads, and project memory.
- View/edit permissions and email or organization-wide sharing are documented for legacy Team/Enterprise Projects. The current beta belongs to one user, cannot be shared, and has no organization-level controls.

Whether legacy RAG or sharing will reach the new Projects beta is undocumented. **Confidence: High.**

The creator’s description of Projects as an MVP “team OS,” the claim that custom frameworks will eventually be replaced, and the reported 67% community demand are not evidenced by the official sources. The creator’s lack of beta access and commercial incentive further limit those judgments. The claim that nobody had access is contradicted by the beta being live for some Pro and Max users. **Confidence: High that these claims remain opinion or unsupported.**

## Ecosystem Context

### E1 — Hosted Claude coordination is becoming a product feature

Anthropic now supplies a first-party coordinator that can dispatch multiple cloud Claude Code threads, place each on its own branch, retain project memory, load repository instructions and plugins, and continue the main conversation while delegated work runs. The coordination and waiting layer is therefore becoming part of the Claude product rather than something every Claude-only workflow must construct itself.

This is an **inference from official product facts**. It applies to Claude-only cloud execution, not agent orchestration generally. **Confidence: High.**

### E2 — The current beta is a personal host, not a team operating system

Official limitations state that a Project belongs to one user, cannot be shared, and has no organization-level controls during the beta. Claude Tag in Team and Enterprise Slack is the documented shared-team surface; it is distinct from the new Projects beta.

The video’s “team OS” language is therefore **opinion**, not the present product contract. **Confidence: High.**

### E3 — Legacy Projects and the new Projects beta are separate surfaces

Legacy chat/Cowork Projects provide the cited RAG and Team/Enterprise sharing behavior. The new Claude Code Projects beta provides coordinating conversations, cloud execution threads, repository loading, automatic compaction, and project memory, but currently lacks sharing. Anthropic’s help page explicitly separates its beta discussion from “the current version of projects.”

Treating these capabilities as one released surface would overstate the beta. **Confidence: High.**

### E4 — Cloud convenience currently narrows execution choice

New Project threads use Anthropic as the model provider and cannot include local sessions. They are unavailable through the terminal CLI or the named third-party cloud platforms. The main conversation has no connectors, and cloud threads do not inherit machine-local setup.

The beta reduces coordination friction by constraining the environment. It does not establish a provider-neutral or local-capability standard. **Confidence: High.**

### E5 — Ecosystem conclusions remain intentionally narrow

The failed and missing branches provide no admissible comparison evidence. This report therefore makes no claim about competing orchestration products, adoption, pricing advantage, or comparative productivity. It establishes only what Anthropic’s verified product surfaces imply for skills-n-stuff.

**Confidence: High in the boundary; Low in broader ecosystem coverage.**

## Project Comparison

### P1 — Projects overlaps with orchestration mechanics, not Harness governance

**Project observation.** Harness routes explicit delegated work through semantic routes, preserves authority and constraints, dispatches bounded execution, and requires an evidence-bearing Harness Result that the parent reproduces before acceptance (`AGENTS.md:9`). Its public interface is one bounded request with explicit authority, context, and verification (`plugins/harness/README.md:23-26`).

**Official product fact.** Projects provides a hosted coordinating conversation and parallel Claude Code cloud threads on separate branches.

**Inference.** Projects can host or initiate work that uses skills-n-stuff, but it does not replace the Harness contract. Routing the same work independently through both systems would create a duplicate control plane. The useful boundary is Projects as the Claude cloud host and Harness as the authority, routing, and proof contract where those guarantees are required.

**Confidence: High.**

### P2 — Claude-only coordination is commoditized; provider-neutral routing is not

**Project observation.** Harness supports Claude plus Codex cross-provider delegation while remaining valid with either provider alone (`plugins/harness/README.md:34-38`). Personal provider mechanics stay outside project instructions (`plugins/harness/README.md:81-91`). Non-Claude agents can install portable `SKILL.md` prompts directly (`README.md:34-40`), although subagents, hooks, and bundled scripts remain Claude Code-only (`README.md:42`).

**Official product fact.** Projects threads use Anthropic as the model provider and are unavailable through the terminal CLI or the named external cloud platforms.

**Inference.** Projects replaces part of the convenience case for a Claude-only coordinator. It does not replace cross-agent skill portability, semantic provider routing, or provider-resilient execution.

**Confidence: High.**

### P3 — Project memory overlaps with standing context, but not decision ownership

**Project observation.** PM maintains domain knowledge through `CONTEXT.md`, architecture decision records, and out-of-scope rejections (`plugins/pm/README.md:364-385`). Product Pulse optionally requests memory enrichment through Harness while retaining file-based research when the provider is absent (`plugins/product-pulse/README.md:252-258`).

**Official product fact.** Each Project thread starts with repository instructions and memory and reads the project’s `MEMORY.md` index.

**Inference.** Projects may reduce the need to manually reconstruct Claude-specific standing context. It does not replace the project’s durable decision artifacts, rejection history, or optional provider-independent file path. Preferences stored in Project memory are instructions rather than enforced settings, so memory is not an authority boundary.

**Confidence: High.**

### P4 — Existing plugins are compatible with Projects, subject to beta constraints

**Official product fact.** Threads load `CLAUDE.md`, skills, and plugins from project repositories; plugins can also be selected in Project settings. Repository permission rules, hooks, and environment settings apply only to one-repository Projects.

**Project observation.** skills-n-stuff is distributed as Claude Code plugins and as portable skills for other agents (`README.md:5`, `README.md:34-42`).

**Inference.** The current product evidence supports treating Projects as another Claude Code host for the existing plugins, not as a reason to rewrite them. Actual end-to-end compatibility remains untested in this research because the video creator lacked access and no accepted branch ran the beta.

**Confidence: High on documented compatibility; Medium on operational compatibility until tested.**

### P5 — Projects does not replace Product Pulse’s research ownership

**Project observation.** Product Pulse owns research questions, source selection, credibility checks, citations, project comparison, synthesis, and publication. It delegates provider-neutral routing and evidence mechanics to Harness (`plugins/product-pulse/README.md:45-50`). Its workflow covers weekly strategy, daily intelligence, and on-demand deep dives (`plugins/product-pulse/README.md:16-22`).

**Inference.** Projects can coordinate Claude threads that perform parts of this work, but coordination does not decide which sources matter, distinguish evidence from inference, preserve citations, or own the resulting recommendation. Those remain differentiated workflow responsibilities.

**Confidence: High.**

### P6 — Projects does not replace PM’s lifecycle or shared tracking

**Project observation.** PM is a seven-skill lifecycle from ingestion and triage through execution and reconciliation (`plugins/pm/README.md:7-19`). PM defines development constraints and submits bounded Harness operations, then reproduces the worker’s Testing Seam before completion (`plugins/pm/README.md:41-60`). Its `owner/ai`, `owner/human`, and `owner/operator` labels identify intended workers (`plugins/pm/README.md:223-232`); they are workflow metadata, not access control.

**Official product fact.** A beta Project belongs to one user and cannot be shared.

**Inference.** A personal Project may coordinate work on PM-approved tasks, but it cannot replace a team-shared tracker, readiness decisions, status transitions, backlog ownership, or reconciliation against merged work.

**Confidence: High.**

### P7 — Independent proof and enforced authority remain differentiated

**Project observation.** Harness resolves concrete execution without widening authority, returns evidence, and requires the parent to reproduce proof (`AGENTS.md:9`). PM’s constraints include Outcomes, Blockers, Testing Seams, tracker boundaries, PR boundaries, and review axes (`plugins/pm/README.md:52-60`).

**Official product fact.** Project preferences are instructions rather than enforced settings. Permission prompts can wait inside a thread, and a sandbox restart can lose uncommitted changes.

**Inference.** Projects improves dispatch and continuity but does not establish an equivalent enforced authority ceiling or independent acceptance mechanism. A completed thread remains a work result to verify, not self-validating proof.

**Confidence: High.**

### P8 — Local capabilities remain outside the beta

**Project observation.** Harness includes explicit operation of local apps, browsers, simulators, and other screenshot-capable interfaces (`plugins/harness/README.md:27-28`). skills-n-stuff also includes local or capability-specific plugins and scripts; the portable skills path explicitly excludes Claude-Code-only hooks and bundled scripts (`README.md:42`).

**Official product fact.** Local sessions cannot join Projects, cloud threads do not inherit local setup, and the coordinating conversation has no connectors.

**Inference.** Projects does not replace workflows that require local files, machine tools, native applications, local secrets, or direct connector access from the coordinator.

**Confidence: High.**

## Risks & Gaps

- **R1 — Duplicate control planes.** Routing the same work through independent Projects and Harness orchestration would create competing ownership of dispatch, authority, state, and acceptance. Treat Projects as a host, not a second Harness contract. **Confidence: High.**

- **R2 — Legacy-feature overstatement.** Advertising RAG or sharing as capabilities of the new beta would merge legacy chat/Cowork documentation with the Claude Code Projects surface. Whether these features will converge is undocumented. **Confidence: High.**

- **R3 — Memory mistaken for enforcement.** Project memory can carry preferences and context, but Anthropic documents those preferences as instructions rather than hard settings. It cannot substitute for authority ceilings or deterministic validation. **Confidence: High.**

- **R4 — Single-user coordination mistaken for team tracking.** A Project currently belongs to one user. It cannot replace a shared issue tracker, ownership taxonomy, lifecycle state, or organization policy. **Confidence: High.**

- **R5 — Cloud-host assumptions.** Code work in Projects requires `github.com` hosting and the Claude GitHub App; Projects also excludes local sessions and does not inherit local Claude Code setup. Workflows depending on local tools or non-GitHub repositories remain outside the verified surface. **Confidence: High.**

- **R6 — Work-loss and attention risk.** A paused sandbox may resume from a fresh clone and lose uncommitted changes. Permission prompts still wait inside threads, while Project use consumes plan limits faster. Hosted coordination reduces polling but does not eliminate supervision or recovery needs. **Confidence: High.**

- **R7 — Untested compatibility.** Documentation says repository plugins load, but this research did not exercise skills-n-stuff inside the beta. Multi-repository behavior is especially uncertain because hooks, permission rules, and environment settings apply only to one-repository Projects. **Confidence: Medium.**

- **R8 — Product-roadmap dependence.** Anthropic has announced planned expansion and near-term local execution, but no verified dates or final contracts establish when sharing, RAG, chat/Cowork integration, Team/Enterprise support, or local execution will arrive. **Confidence: High that the details remain unknown.**

- **R9 — Commercial and secondary-source framing.** The video creator had no beta access, promotes a paid community, and supplies an unsupported demand statistic. Its “agentic OS” and framework-replacement conclusions should not drive architecture decisions. **Confidence: High.**

- **R10 — Degraded research coverage.** Only one of four expected branches was accepted and proven. No independent ecosystem-comparison result exists, so competitive conclusions beyond the verified Anthropic surface would be unsupported. **Confidence: High.**

## Prior Research

`agent-native-harness-and-pm.md` established the governing split: automate waiting and proof transport while preserving product decisions. Projects reinforces the first half by productizing a coordinating conversation and cloud worker threads. It does not alter the second half: PM still owns scope, priority, readiness, and lifecycle decisions, while Harness preserves authority and proof.

`evidence-gated-agent-completion.md` established that worker output and successful execution are claims until the accepting parent reruns the stable verification seam against a fixed target. Projects makes cloud dispatch easier but supplies no contrary evidence. Its thread results should enter the same evidence-gated acceptance path.

`model-harness-unbundling.md` separated the model, harness, durable project context, and transient conversation. Projects bundles Anthropic’s model, cloud harness, memory, and coordinating conversation into one hosted surface. That strengthens the value of the remaining unbundled layer: portable skills, provider-neutral requests, explicit authority, and accepted-task evidence.

Three conclusions are reinforced:

1. **Hosted coordination is infrastructure, not product ownership.** Projects can dispatch and remember; Product Pulse and PM still decide what matters.
2. **Convenience does not replace proof.** Cloud threads still require fixed-target verification before acceptance.
3. **Portability becomes more valuable as hosts bundle vertically.** A Claude-only Project is useful, but the durable differentiator is behavior that survives outside that host.

The new conclusion is narrower: skills-n-stuff should explicitly support Projects as a compatible Claude host while declining to build a competing project-level coordinator.

## Sources

### Primary resource

- [Simon Scrapes, “Anthropic Just Built It’s Own Agentic OS”](https://www.youtube.com/watch?v=afVpjeoQF2I) — video published 2026-09-18. This report used the supplied uploader-provided manual captions. Neither the worker nor the parent fetched the YouTube page; metadata came from the research request.

### Official Anthropic sources

- [Claude Code Projects documentation](https://code.claude.com/docs/en/claude-projects) — coordinating conversation, cloud threads, repositories, memory, plugin loading, availability, connectors, local-session limits, provider limits, permissions, usage, and sandbox recovery.
- [Projects redesigned](https://claude.com/blog/projects-redesigned) — announcement dated 2026-09-17, thread execution model, delegation, and stated local-execution direction.
- [What are projects?](https://support.claude.com/en/articles/9517075-what-are-projects) — distinguishes the new beta discussion from the current legacy Projects documentation.
- [Retrieval augmented generation for Projects](https://support.claude.com/en/articles/11473015-retrieval-augmented-generation-rag-for-projects) — legacy chat/Cowork Projects RAG behavior; not evidence for the new Claude Code Projects beta.
- [Manage project visibility and sharing](https://support.claude.com/en/articles/9519189-manage-project-visibility-and-sharing) — legacy Team/Enterprise Projects sharing behavior; contradicted as a description of the current single-user beta.

### Project evidence at `cf023755cfe7bc546402d292d1ea85c0c7be73e1`

- `AGENTS.md:9` — semantic Harness requests, authority preservation, evidence-bearing results, and parent reproduction.
- `README.md:34-42` — portable skills for non-Claude agents and the boundary around Claude-Code-only capabilities.
- `plugins/harness/README.md:23-28` — bounded execution, independent review, and local computer-use capability.
- `plugins/harness/README.md:34-38` — Claude and Codex cross-provider delegation.
- `plugins/harness/README.md:81-91` — provider mechanics remain outside project instructions.
- `plugins/product-pulse/README.md:45-50` — Product Pulse owns research and synthesis; Harness owns routing and evidence mechanics.
- `plugins/product-pulse/README.md:114-116` — optional memory provider configuration.
- `plugins/product-pulse/README.md:252-258` — optional memory enrichment and file-based fallback.
- `plugins/pm/README.md:7-19` — PM’s seven-skill lifecycle.
- `plugins/pm/README.md:41-60` — PM and Harness execution, authority, and verification boundary.
- `plugins/pm/README.md:223-232` — intended-worker labels.
- `plugins/pm/README.md:364-385` — durable domain knowledge and rejection history.

## Action Items

### A1 — Clarify the product boundary

- **Why:** Projects commoditizes Claude-only cloud coordination and waiting, not the governance and workflow layers that define skills-n-stuff.
- **Effort:** Quick documentation change.
- **Confidence:** High.
- **Tradeoffs:** The wording must remain explicitly tied to the beta and may require revision as the product matures.
- **Evidence:** Projects supplies the hosted coordinator and cloud threads (E1); it remains Anthropic-only and single-user (E2, E4); Harness, Product Pulse, and PM retain distinct ownership (P1-P8).

### A2 — Verify compatibility without creating a new system

- **Why:** Official documentation says repository plugins load, but this research contains no hands-on beta run.
- **Effort:** Small and conditional on access.
- **Confidence:** Medium-high.
- **Tradeoffs:** A successful one-repository check will not prove multi-repository parity. Plan usage, connector limitations, permission waits, and sandbox recovery should be recorded as constraints rather than hidden.
- **Evidence:** P4, R6, R7, and the [Claude Code Projects documentation](https://code.claude.com/docs/en/claude-projects).
- **Minimum check:** Confirm that a Project thread loads the repository’s `CLAUDE.md`, skills, and plugins; honors the documented one-repository hooks, permissions, and environment behavior; returns a result that can enter the existing Harness/PM verification path; and preserves committed work across the tested lifecycle.
- **Unverified dependency:** Beta access and the account’s current rollout state.

### A3 — Preserve one control plane

- **Why:** A second coordinator or memory layer would duplicate product behavior while weakening ownership of authority and acceptance.
- **Effort:** None unless a future incompatibility is demonstrated.
- **Confidence:** High.
- **Tradeoffs:** This intentionally leaves Anthropic’s hosted experience in charge of its own scheduling and interface. skills-n-stuff does not gain a bespoke Projects dashboard or synchronization layer.
- **Evidence:** P1, P3, P5-P7 and R1-R4.
- **Non-goals:** No duplicate thread scheduler, Project-state mirror, custom RAG implementation, sharing proxy, or replacement for Harness Results and PM state.

### A4 — Track released contracts, not roadmap implications

- **Why:** Current evidence separates legacy RAG and sharing from the new beta, while local execution and additional surfaces are only planned.
- **Effort:** Quick review when Anthropic materially updates Projects.
- **Confidence:** High.
- **Tradeoffs:** Compatibility documentation may lag a rollout until official sources can be rechecked; that is preferable to claiming unreleased behavior.
- **Evidence:** E2-E5 and R2, R5, R8.
- **Unverified dependencies:** Whether or when sharing, RAG, chat/Cowork integration, Team/Enterprise support, or local execution will reach the new Projects model.
