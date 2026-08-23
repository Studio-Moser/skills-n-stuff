---
title: Model–Harness Unbundling for skills-n-stuff
resources:
  - url: https://www.youtube.com/watch?v=4HvFqhtCb-A
    type: video
    title: Stop Paying $200 For Work An $18 Model Can Do Inside Claude Code And Codex.
    published: 2026-08-21
tags: [model-routing, harnesses, codex, claude-code, glm-5.3, evaluation, handoffs]
---

# Model–Harness Unbundling for skills-n-stuff

## Resource Summary

Nate B. Jones argues that the model, coding harness, durable project context, and transient conversation are separate layers. Teams can keep Claude Code or Codex—and their files, tools, hooks, permissions, and habits—while routing bounded work to a cheaper model such as GLM-5.3. The cheap route is only cheaper when retries, review, context reconstruction, latency, and rejected output are included. His operating rule is sound: start substantial work on the model expected to finish it; if a midstream handoff is unavoidable, transfer a bounded goal, current state, relevant files, constraints, definition of done, and checks.

The video is fresh (published August 21, 2026) and used uploader-provided manual captions. It is a credible practitioner synthesis, not an independent benchmark. Its Z.ai setup claims are supported by Z.ai, but Anthropic explicitly does not support routing Claude Code to non-Claude models; that path is vendor-compatible rather than Anthropic-supported.

## Ecosystem Context

### E1 — The economic unit is an accepted task, not a token or subscription

OpenAI recommends comparing representative tasks by success, completeness, evidence, total tokens, latency, and cost. Z.ai's current Coding Plan adds 5-hour and weekly credit limits, model-specific credit multipliers, and time-of-day pricing. A nominal $18 plan therefore does not prove savings for this workflow. **Confidence: High.**

### E2 — Codex is the cleaner provider-abstraction boundary

Codex supports user-level custom providers with a Responses-compatible `base_url`, secret-bearing environment-variable names, and separate `$CODEX_HOME/<name>.config.toml` profiles selected by `--profile`. Project-local config cannot override provider or authentication routing. Legacy `[profiles.<name>]` syntax is no longer read. **Confidence: High.**

### E3 — Claude Code compatibility has a support boundary

Claude Code supports `ANTHROPIC_BASE_URL` for proxies and gateways, and Z.ai documents an Anthropic-compatible endpoint. Anthropic's current documentation says gateway routing to non-Claude models is unsupported. A separate process can still work, but it should be treated as a Z.ai compatibility layer with different support, MCP-context, cache, and privacy risks—not as a native Claude Code provider feature. **Confidence: High.**

### E4 — Fresh subagents and provider switches make durable files economically valuable

Claude Code normal subagents start with isolated context; forks inherit the parent conversation and cache but must share its model. Switching models invalidates that model's prompt cache for the next request. Codex likewise loads `AGENTS.md` and selected skills from files, while separate agent threads consume separate model/tool work. This confirms the video's core distinction between portable file context and non-portable conversation state. **Confidence: High.**

### E5 — GLM-5.3 is testable, but should not be adopted on price alone

Z.ai currently advertises Lite at $18/month and documents GLM-5.3 for Claude Code and Codex through Anthropic- and Responses-compatible endpoints. Plan/account eligibility differs, reasoning cannot be disabled, and individual-plan prompts may be retained and processed in Singapore; the Team Plan's no-training statement should not be generalized to individual plans. **Confidence: High for integration and plan details; Medium for account-specific eligibility and data handling.**

## Project Comparison

`skills-n-stuff` already implements most of the video's architecture better than the video specifies:

- `studio-baseline/Rubric_Setup.md` separates flat-subscription quota/latency from metered dollar cost, scores model-plus-effort pairs, and routes bounded, exploratory, batch, review, and independent work separately.
- `plugins/pm/references/model-orchestration.md` treats cross-vendor execution as capability-gated and requires explicit model and effort selection.
- `plugins/pm/skills/codex-implementation/SKILL.md` already uses a compact handoff containing Outcome, Blockers, Testing Seam, Proof, files, constraints, and verification. That is the video's proposed handoff in a stronger, testable form; adding another handoff template would duplicate it.
- `studio-baseline/AGENTS_Baseline.md` requires isolated worktrees for parallel work and independent verification of worker claims.
- `plugins/machine/scripts/rubric-audit.sh` audits whether dispatches set a model and counts Codex handoffs.

Two gaps matter:

1. The routing doctrine is more precise than the executor. `plugins/pm/skills/codex-implementation/SKILL.md` invokes `codex exec` without passing the rubric-selected model, reasoning effort, or profile. Today the desired route works only when the user's Codex default happens to match the rubric. It cannot intentionally select a GLM profile or another provider.
2. `rubric-audit.sh` counts dispatches and handoffs, but not accepted-task outcomes: retries, rejection, verification failures, review turns, latency, quota/tokens, or whether the result shipped. It can prove routing compliance, not economic value.

## Risks & Gaps

- **R1 — Decorative routing:** a model rubric that is not enforced at the CLI call can silently route work to the wrong model or effort. **Confidence: High.**
- **R2 — False savings:** provider price can look cheaper while retries and frontier-model review make the accepted task more expensive. Current audit data cannot detect this. **Confidence: High.**
- **R3 — Unsupported compatibility:** presenting non-Claude Claude Code routing as officially supported by Anthropic would overstate the support contract. **Confidence: High.**
- **R4 — Secret and source exposure:** Z.ai's installer can modify user settings, and individual-plan data handling differs from the Team Plan. No API key or full provider config belongs in this public repository. **Confidence: High.**
- **R5 — Volatile config syntax:** Codex moved profiles to separate files and stopped reading legacy profile tables. Static setup guidance needs live verification. **Confidence: High.**

## Sources

- [Video](https://www.youtube.com/watch?v=4HvFqhtCb-A) — primary resource, published August 21, 2026.
- [Z.ai Coding Plan overview](https://docs.z.ai/devpack/overview) — current plan limits and supported tools.
- [Z.ai Codex integration](https://docs.z.ai/devpack/tool/codex) — Responses-compatible Codex setup.
- [Z.ai Claude Code integration](https://docs.z.ai/devpack/tool/claude) — Anthropic-compatible Claude Code setup.
- [Z.ai GLM-5.3](https://docs.z.ai/guides/llm/glm-5.3) — model capabilities and endpoint details.
- [Claude Code gateway configuration](https://code.claude.com/docs/en/llm-gateway) — Anthropic's provider-support boundary.
- [Claude Code prompt caching](https://code.claude.com/docs/en/prompt-caching) — cache invalidation on model switches.
- [Claude Code subagents](https://code.claude.com/docs/en/sub-agents) — isolated versus forked context.
- [Codex advanced configuration](https://developers.openai.com/codex/config-file/config-advanced) — providers and current profile structure.
- [Codex configuration reference](https://developers.openai.com/codex/config-reference/) — provider and project-config restrictions.
- [OpenAI model guidance](https://developers.openai.com/api/docs/guides/latest-model) — representative-task evaluation dimensions.

## Action Items

| # | Action | Why | Effort | Confidence |
|---|--------|-----|--------|------------|
| 1 | Make `pm:codex-implementation` and `pm:codex-review` resolve and pass the rubric-selected model, effort, and optional profile explicitly. | Turns the existing routing doctrine into enforced behavior and enables controlled alternate-provider trials. | Moderate | High |
| 2 | Extend routing telemetry from dispatch counts to accepted-task outcomes: attempts, verification failures, review rounds, elapsed time, and available quota/token usage. | Measures the fully loaded cost the video correctly identifies. | Significant | High |
| 3 | Add a repository-specific challenge-set gate to `/machine:model-rubric`: no provider/model earns a route until it passes representative bounded tasks against the incumbent. | External leaderboards and subscription prices do not predict accepted-task cost on this codebase. | Moderate | High |
| 4 | Do not add GLM-5.3 as a default route yet; run a secret-safe personal Codex-profile trial after Actions 1–3, using no sensitive repository data. | Current Claude/Codex flat subscriptions already cover the workflow, and there is no local evidence that GLM improves quota, latency, or accepted-task cost. | Quick win | High |
| 5 | Keep the existing PM work-readiness handoff; document it as the cross-provider handoff contract instead of creating another template. | The current Outcome/Blockers/Testing Seam/Proof contract already exceeds the video's six-line handoff. | Quick win | High |
