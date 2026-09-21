---
title: "Planning Lessons from Anthropic Projects"
resources:
  - url: https://www.youtube.com/watch?v=afVpjeoQF2I
    type: video
    title: "Anthropic Just Built It’s Own Agentic OS"
    published: 2026-09-18
tags: [anthropic-projects, claude-code, agent-orchestration, memory, product-planning, workflow-design]
related_reports: [agent-native-harness-and-pm, evidence-gated-agent-completion, model-harness-unbundling]
---

# Planning Lessons from Anthropic Projects

Anthropic’s Projects beta offers a useful model for planning agentic work: one durable coordinating conversation, isolated execution threads, persistent context, and supervision focused on exceptions rather than constant polling. Its current boundaries also show what future specifications should make explicit.

## Research Coverage

This report synthesizes one accepted and evidence-proven research branch against project commit `cf023755cfe7bc546402d292d1ea85c0c7be73e1`. The accepted branch used the uploader-provided manual transcript, five official Anthropic pages reopened by the parent on 2026-09-18, and the project files reproduced in the research packet.

Coverage is degraded: **4 branches expected; 1 accepted/proven; 1 failed; 0 blocked; 0 abandoned; 2 unproven**.

- **resource-extraction-initial:** unavailable; no result; evidence unproven; blocker: missing Harness Result; elapsed unavailable.
- **ecosystem-comparison-initial:** unavailable; no result; evidence unproven; blocker: missing Harness Result; elapsed unavailable.
- **combined-recovery:** failed; evidence `not_proven`; blocker: Codex worker returned an untyped failure with an empty report; elapsed 102 seconds.
- **resource-extraction-clean-retry:** accepted; evidence proven; route `gpt-5.6-terra@high` via Codex; worker elapsed 255 seconds. The parent corrected four verdicts and two file references, reopened all five official citations and all project references, and accepted the corrected result.

The ecosystem-comparison branch never produced a result. Accordingly, the Ecosystem Context section is limited to facts established by the accepted branch’s official Anthropic citations. It does not claim broader market coverage.

The video is fresh relative to the launch: Anthropic’s announcement is dated 2026-09-17 and the video 2026-09-18. Its creator nevertheless states, “I don't even have access myself yet to test this.” The video is therefore a timely secondary explanation, not hands-on validation. It also promotes the creator’s paid community and gives an unsourced “67% of our community” statistic, which weakens confidence in its market framing without changing independently verified product facts.

**Confidence: High** in the corrected product and project findings; **Low** in ecosystem completeness because the dedicated ecosystem branch produced no result.

## Resource Summary

The new Projects beta centers on one ongoing coordinating conversation. Delegated threads run as Claude Code cloud sessions, each with its own branch and repository copy, while the main conversation remains available. Threads can further divide work through subagents, loops, and workflows. **Confidence: High.**

Each thread starts with the project’s repositories, instructions, and memory. Threads load `CLAUDE.md`, skills, and plugins from every repository and read the `MEMORY.md` index at startup. A Library tab collects files added to the project and files produced by threads. Permission rules, hooks, and environment configuration apply only when the project contains one repository. Plugins may also be selected in Project settings. **Confidence: High.**

The current beta is Claude Code-only, cloud-hosted, gradually rolling out on Pro and Max plans, and not yet available on Team or Enterprise. Projects are absent from the terminal CLI, Amazon Bedrock, Google Cloud’s Agent Platform, and Microsoft Foundry. Anthropic says chat, Cowork, Team, and Enterprise expansion is planned, while local execution behind a user’s network is “coming very soon.” Timing and final behavior remain unknown. **Confidence: High on current availability; Low on delivery timing.**

The coordinating conversation has no connectors; connector-dependent work must be delegated to a thread. Local sessions cannot join a Project, and cloud threads do not inherit the user’s machine-local Claude Code setup. Threads can pause for permission prompts, consume plan limits faster, and lose uncommitted changes if a paused sandbox cannot resume and work continues from a fresh clone. Code projects require `github.com` and the Claude GitHub App; projects without a repository can still research and write documents. **Confidence: High.**

The current new Projects beta is single-user, cannot be shared, and has no organization-level controls. It does **not** inherit the legacy chat/Cowork Projects behavior documented for automatic RAG or Team/Enterprise sharing. The beta instead documents automatic thread compaction and context from recent messages, recent threads, and project memory. Whether the two product surfaces will converge is undocumented. **Confidence: High.**

The creator’s “team OS” framing and reported 67% community demand are not evidenced by the official sources. The creator’s lack of beta access and promotion of a paid community further limit those judgments. **Confidence: High that these claims remain opinion or unsupported.**

## Ecosystem Context

### E1 — Coordination is becoming a provider-native product capability

Anthropic now supplies a first-party coordinator that can dispatch multiple cloud Claude Code threads, place each on its own branch, retain project memory, load repository instructions and plugins, and continue the main conversation while work runs.

This is an **inference from official product facts** and applies specifically to Claude-only cloud execution. **Confidence: High.**

### E2 — The current surface is personal and cloud-bound

A beta Project belongs to one user, cannot be shared, and has no organization-level controls. Its threads use Anthropic as the model provider, cannot include local sessions, and are unavailable through the terminal CLI or the named third-party cloud platforms. **Confidence: High.**

### E3 — Legacy and new Projects are separate product surfaces

Legacy chat/Cowork Projects provide the cited RAG and Team/Enterprise sharing behavior. The new beta provides coordinating conversations, cloud execution threads, repository loading, automatic compaction, and project memory, but currently lacks sharing. Anthropic’s help page explicitly separates the beta from “the current version of projects.” **Confidence: High.**

### E4 — Ecosystem conclusions remain intentionally narrow

The failed and missing branches provide no admissible comparison evidence. This report therefore makes no claim about competing orchestration products, adoption, pricing advantage, or comparative productivity. **Confidence: High in this boundary; Low in broader ecosystem coverage.**

## Planning Lessons

### L1 — Use one durable coordinator conversation as the intake surface

**Observed pattern —** A Project is an ongoing coordinating conversation that can delegate work to cloud threads while the main conversation continues.

**Planning principle —** Give users one stable place to ask questions, provide context, delegate work, and synthesize results.

**How it could affect planning —** Future workflow specifications could identify a durable coordinator as the default intake surface instead of making users choose an execution mechanism before expressing the outcome they want.

**Confidence —** High.

**Unverified —** The accepted research did not test how reliably the coordinator preserves intent across long-running, high-volume work.

### L2 — Treat threads as isolated execution units with explicit states

**Observed pattern —** Each thread works from its own repository copy and branch. Threads may pause for permission, finish independently, or require recovery from a fresh clone.

**Planning principle —** A delegated unit should have a clear identity, isolated workspace, lifecycle state, and recoverable output.

**How it could affect planning —** Specifications could define thread states such as running, waiting on you, ready for review, failed, and complete, along with what evidence or committed artifact allows each transition.

**Confidence —** High in the isolation and recovery facts; Medium in the proposed state model.

**Unverified —** The accepted evidence does not establish that Projects exposes this explicit state taxonomy or provides a complete recovery protocol.

### L3 — Make shared memory and the Library first-class artifacts

**Observed pattern —** Threads start with repository instructions and project memory, read the `MEMORY.md` index, and contribute files to a Library alongside files added directly to the Project.

**Planning principle —** Durable context and produced artifacts should be visible parts of the workflow, not hidden inside transient conversations.

**How it could affect planning —** Roadmap and feature specifications could distinguish durable memory, repository instructions, working conversation context, and produced artifacts, including which one is authoritative for each decision.

**Confidence —** High.

**Unverified —** Project memory preferences are instructions rather than enforced settings, and the research did not test Library organization, conflict handling, or multi-thread update behavior.

### L4 — Design supervision around exceptions

**Observed pattern —** The coordinator can remain active while threads run, but permission prompts, sandbox recovery, and completed work still require attention.

**Planning principle —** Human attention should concentrate on exceptions and decisions rather than continuous polling.

**How it could affect planning —** Workflow designs could foreground waiting-on-you, ready-for-review, failure, recovery, and approval events, with ordinary progress remaining background state.

**Confidence —** High in the documented interruption and recovery conditions; Medium in this supervision model.

**Unverified —** The accepted evidence does not document a unified exception queue, notification model, or approval dashboard.

### L5 — Answer quick questions in place and delegate expensive work selectively

**Observed pattern —** The main surface remains a conversation while threads provide isolated cloud execution. Parallel thread use can consume plan limits faster.

**Planning principle —** Delegation should have a threshold: keep lightweight clarification and synthesis in the coordinator, and create a thread when work benefits from isolation, tools, parallelism, or a durable branch.

**How it could affect planning —** Future specifications could state when work stays conversational and when it becomes a delegated execution unit, reducing unnecessary thread creation and its resource cost.

**Confidence —** High in the underlying product behavior; Medium in the delegation threshold.

**Unverified —** The accepted evidence provides no measured cost boundary or documented rule for deciding when delegation is worthwhile.

### L6 — Expose usage and bound concurrency

**Observed pattern —** Projects can run multiple threads in parallel, and Anthropic warns that this can consume plan limits faster.

**Planning principle —** Parallelism should be paired with visible resource consumption and deliberate concurrency bounds.

**How it could affect planning —** Planning discussions could require any concurrent workflow proposal to explain how users will see usage, limit active work, prioritize threads, and avoid starting more work than they can supervise.

**Confidence —** High in the parallelism and usage facts; Low in any specific control design.

**Unverified —** The accepted evidence does not establish built-in usage visibility, user-configurable concurrency controls, or the optimal concurrency limit.

### L7 — State cloud, local, connector, repository, and sharing boundaries explicitly

**Observed pattern —** The beta is cloud-hosted and Claude Code-only; local sessions cannot join; cloud threads do not inherit local setup; the coordinating conversation has no connectors; code work requires `github.com` and the Claude GitHub App; multi-repository Projects have configuration limitations; and Projects are single-user with no organization-level controls.

**Planning principle —** Execution location, connector access, repository assumptions, credential boundaries, and sharing scope are product contracts, not implementation details.

**How it could affect planning —** Future specifications could include a boundary table covering cloud versus local execution, coordinator versus worker connector access, supported repository hosts, multi-repository behavior, sharing, and organization controls.

**Confidence —** High.

**Unverified —** Final behavior and timing for local execution, additional product surfaces, sharing, and organization support remain undocumented.

### L8 — Keep the outcome layer separable from provider-native coordination

**Observed pattern —** Projects bundles Anthropic’s model, coordinator, cloud threads, memory, and Library while loading repository instructions, skills, and plugins. Existing project evidence separates bounded outcomes, authority, verification, and portable skills from personal provider mechanics (`AGENTS.md:9`, `README.md:34-42`, `plugins/harness/README.md:23-26`, `plugins/harness/README.md:81-91`).

**Planning principle —** Specify outcomes, authority, durable artifacts, and acceptance independently from the scheduling surface that executes them.

**How it could affect planning —** This separation could allow future plans to adopt provider-native capabilities when they are useful, change hosts as contracts evolve, and retire obsolete coordination plumbing without rewriting the intended workflow outcome.

**Confidence —** High in the documented product and project boundaries; Medium in the future-planning effect.

**Unverified —** This research did not run an end-to-end compatibility test or establish which existing mechanics would become obsolete under real usage.

## Risks & Gaps

- **R1 — Capability conflation.** Planning against legacy RAG or sharing behavior would overstate the new beta. Whether these product surfaces converge is undocumented. **Confidence: High.**

- **R2 — Memory treated as enforcement.** Project memory carries preferences and context, but Anthropic documents preferences as instructions rather than hard settings. Plans should not assume memory alone supplies deterministic authority or validation. **Confidence: High.**

- **R3 — Hidden execution boundaries.** Local tools, machine configuration, connector access, non-GitHub repositories, sharing, and multi-repository configuration differ from the coordinator’s apparent single surface. **Confidence: High.**

- **R4 — Work-loss and attention risk.** A paused sandbox may restart from a fresh clone and lose uncommitted changes. Permission prompts still require attention, while parallel work can consume plan limits faster. **Confidence: High.**

- **R5 — Untested operational fit.** Documentation says repository plugins load, but this research did not exercise skills-n-stuff inside the beta. Multi-repository behavior remains especially uncertain. **Confidence: Medium.**

- **R6 — Roadmap dependence.** Anthropic has announced planned expansion and near-term local execution, but no verified dates or final contracts establish when sharing, RAG, chat/Cowork integration, Team/Enterprise support, or local execution will arrive. **Confidence: High that the details remain unknown.**

- **R7 — Secondary-source incentives.** The video creator had no beta access, promotes a paid community, and supplies an unsupported demand statistic. Those judgments should not set planning priorities. **Confidence: High.**

- **R8 — Degraded research coverage.** Only one of four expected branches was accepted and proven. No independent ecosystem-comparison result exists, so broader competitive conclusions would be unsupported. **Confidence: High.**

## Prior Research

- [`agent-native-harness-and-pm.md`](agent-native-harness-and-pm.md) concluded that waiting and proof transport can be automated while product decisions remain explicit. That supports planning for exception-based supervision without hiding decision ownership.

- [`evidence-gated-agent-completion.md`](evidence-gated-agent-completion.md) concluded that worker output remains a claim until the accepting parent reruns a stable verification seam against a fixed target. That informs the proposed ready-for-review and acceptance states.

- [`model-harness-unbundling.md`](model-harness-unbundling.md) separated the model, harness, durable project context, and transient conversation. Projects demonstrates how a provider can bundle those layers, reinforcing the planning value of expressing outcomes independently from host-specific coordination.

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

## Recommendations

These recommendations are planning inputs, not approved implementation work or backlog commitments.

### Adopt now

- Require planning discussions to distinguish the coordinator, execution threads, durable memory, Library artifacts, exception states, and acceptance evidence. **Confidence: High.**
- Include explicit cloud/local, connector, repository, multi-repository, sharing, and organization boundaries in relevant specifications. **Confidence: High.**
- Keep outcomes and acceptance criteria separate from provider-specific scheduling so native capabilities can be adopted or retired without preserving obsolete plumbing. **Confidence: Medium-high.**

### Validate

- When beta access permits, test whether a one-repository Project loads `CLAUDE.md`, skills, plugins, hooks, permission rules, and environment configuration as documented; preserves committed work; exposes useful artifacts through the Library; and produces results that can enter the existing verification path. **Confidence: Medium-high.**
- Test multi-repository behavior separately because hooks, permission rules, and environment settings are documented only for one-repository Projects. **Confidence: Medium.**
- Evaluate proposed delegation thresholds, exception states, usage visibility, and concurrency bounds with real workflows before treating them as product requirements. **Confidence: Medium.**

### Monitor

- Track official changes to local execution, chat and Cowork integration, Team and Enterprise availability, sharing, organization controls, and RAG. Do not infer convergence from the legacy Projects documentation. **Confidence: High.**
- Revisit usage and concurrency planning when official documentation exposes clearer limits, controls, or operational behavior. **Confidence: High that the current evidence is incomplete.**
