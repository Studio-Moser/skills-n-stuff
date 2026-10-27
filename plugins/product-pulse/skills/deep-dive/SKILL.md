---
name: deep-dive
description: >-
  Researches an external video, article, repository, or document against the current project, as a quick conversational take, full research in chat, or a saved cited report. Use when the user asks to research, analyze, or compare an external resource against the project, for example "what do you think of this link", "should we adopt X", or "compare this repo to ours".
allowed-tools: "Bash Read Write Edit Skill AskUserQuestion"
---

# Product Pulse — Deep Dive

The user shared one or more external resources (videos, articles, repos, docs) and wants them judged against the current project: what applies, what the project lacks or risks, and what to do about it.

Harness owns routing and execution. Invoke the named Harness skill through `Skill`;
do not read Harness skill, reference, script, or rubric files, and do not perform
Harness phases inside Product Pulse. Do not read or inspect the model rubric, and
do not resolve a model, effort, provider, or executor. Do not repair an unresolved
or blocked route inside Product Pulse; consume and report the typed Harness Result.

---

## Choose the Path

A deep dive is the start of a conversation, not always a report. Before researching,
ask what the user wants in one round of questions. Use the runtime's structured
question UI (`AskUserQuestion` in Claude Code); where none exists, ask the same
questions in one plain message. Skip any question the request already answers, and
never ask just because a link was shared without a research request.

1. **Depth** (pick one):
   - **Quick take** — read the resources, check them against the project, and answer
     in chat. No setup, no files, no delegation.
   - **Full research in chat** — the complete ecosystem research and project
     comparison, delivered in chat. Nothing is saved.
   - **Saved report and PR** — full research, saved to the research directory and
     opened as a pull request.
2. **Focus** (pick any): whether to adopt it, how the project compares, what the
   project is missing or risking, or simply understanding the resource. Lead the
   answer with the chosen focus and scope the project audit to it.

| Path | Runs | Does not run |
|------|------|--------------|
| Quick take | Phases 2 and 4, your own reading of the ecosystem, then the Phase 7 sections that apply | Phase 0, Harness requests, Phases 8–10; `pulse-config.yaml` is not required |
| Full research in chat | Phases 0–7; without a config, skip Phases 0.1, 0.2, 1 and memory and continue | Phases 8–10 |
| Saved report and PR | Every phase | — |

A quick take states that it is a single-pass read and gives a confidence level for
each finding; it has no Research Coverage section because no branches were scheduled.

---

## Phase 0: Load Context

### 0.0 Discover Configuration

Quick take skips this phase. Otherwise run § Discover Configuration in [Config_and_Publish.md](../../references/Config_and_Publish.md) with `save_report=true` on the saved path and `false` on full research in chat. The chat path continues without a config; the saved path stops for a missing config or `gh` login because only it writes files and opens a PR. On the saved path, set `output_dir="$research_dir/deep-dives"` and create it.

### 0.1 Read Product Context

Read `{research_dir}/research-context.md`. If missing, stop and tell the user to run `/product-pulse:setup`.

### 0.2 Pull Latest (all configured repos)

Run § Pull Latest in [Config_and_Publish.md](../../references/Config_and_Publish.md).

---

## Phase 1: Load Prior Research

Before starting new research, check what's already been done.

- Scan `{research_dir}/deep-dives/` for existing `.md` report files.
- Read the YAML frontmatter of each report (title, resources, tags, related_reports) to build an index.
- Don't read full report bodies — just enough to know what topics have been covered and what conclusions were reached.
- Keep this index in mind for later phases. You'll reference prior reports when they're relevant to the current analysis.

If the output directory is empty or doesn't exist yet, skip this phase.

---

## Phase 2: Understand the Resources

For each link the user provides, extract as much substance as possible:

- **YouTube / Shorts / Instagram / TikTok / Threads videos**: Fetch the full transcript by running `transcribe "<url>"` (the command the transcribe plugin installs) and pass the transcript as source content. If transcribe fails, surface the stderr message to the user and stop; do not analyze the video without its transcript.
- **Articles / blog posts / docs**: Fetch the full readable content plus canonical URL, title, author or publisher, and publication or update date.
- **GitHub repos**: Collect the README, project structure, key source files, dependencies, release state, and canonical repository URL needed for the research question.
- **Other links**: Adapt collection to the resource while preserving the full accessible content and metadata needed to verify later claims.

Record the full source content, canonical URL, title, author or publisher,
publication date or last-update date, and access failures. Do not analyze a video when
transcription fails and do not treat a snippet as the full source content. When a link
is inaccessible (paywall, sign-in), say so up front and work from whatever context the
user can provide.

---

## Phase 3: Define Cross-Reference Requirements

**Only when multiple resources are provided.** Skip this phase for single-resource research.

Include all accepted resource extracts in an additional Phase 5 `bulk` request. Require
that comparison to cover:

- **Agreements** — Where do the sources align? Shared recommendations carry more weight.
- **Contradictions** — Where do they disagree? Flag these prominently and note which source has stronger evidence (more recent, more authoritative, better-supported claims).
- **Complementary angles** — Does one resource cover ground the others miss? Identify the combined picture that emerges from reading all of them together.
- **Gaps** — What important aspects does none of the resources address?

This cross-reference analysis becomes a section in the final report. When sources
contradict each other, don't pick a winner silently; use the Phase 6 review request when
the conflict is high-impact or would drive a recommendation.

---

## Phase 4: Audit the Current Project

Before any project-comparison request, inspect the codebase and project:

- Read the project structure, key configuration files, and documentation
- Understand the tech stack, architecture, and major dependencies
- Look at how the project currently handles the areas the resources touch on
- Identify the project's architectural philosophy and patterns in use

Record the current project facts and repository-relative files that support each fact.
These audited inputs must be present in every comparison-bearing Phase 5 packet. Do not
request a project comparison until this audit is complete.

---

## Phase 5: Research the Ecosystem

Go beyond the resources themselves. For every significant concept, tool, library, pattern, or product mentioned:

- Search for current documentation and best practices
- Look into alternatives and competitors (e.g., if Kafka is mentioned, also look at RabbitMQ, Pulsar, NATS, and understand the tradeoffs)
- Find known issues, gotchas, and common pitfalls
- Check for recent developments — has the landscape changed since the resource was published?

Request independent extraction, ecosystem research, and project comparison through
Harness. For each resource or bounded concept bundle, invoke `harness:delegate` with
`operation: execute` and `route: bulk`. Submit independent requests concurrently.

```yaml
operation: execute
route: bulk
outcome: Return a source-faithful extraction and bounded project comparison for one external resource or concept bundle
context:
  project: {project_id}
  mode: fresh
  state: {research question, full source content, canonical URL, title, author or publisher, publication date or last update, related resource extracts, prior-report conclusions, and current project facts}
  files: [{repository-relative project files needed for the bounded comparison}]
  memory:
    enabled: {memory.connector is not null}
    recall:
      - purpose: Recover durable prior conclusions relevant to this deep-dive topic
        query: Prior deep-dive conclusions for {project_id} and {topic}
        limit: 10
    capture: []
authority:
  working_directory: {absolute primary repository root}
  allowed_paths: [{read-only paths named in context.files}]
  tools: [internet research, read-only source and repository inspection]
  approvals: []
constraints:
  - |
    Product Pulse deep-dive researcher:
    Extract the source's claims, evidence, technical specifics, named tools, patterns,
    recommendations, and caveats from the full source content. Preserve a citation URL
    for every material external claim. Do not fabricate a URL, quote, API, repository
    fact, or source position, and do not analyze inaccessible content as though read.
  - |
    Assess credibility using author or publisher authority, primary versus secondary
    evidence, corroboration, publication date or last update, currentness, disclosed
    incentives, and conflicts. Research current official documentation, alternatives,
    known issues, pitfalls, and material developments since publication. Separate source
    claims, corroborating evidence, contradiction, and analyst inference. Flag a stale or
    superseded source prominently; a two-year-old article on a fast-moving framework can
    be dangerously outdated.
  - |
    Perform a bounded project comparison against the supplied current project facts and
    repository files: identify confirmed agreements, differences, applicable gaps,
    tradeoffs, and non-applicable advice with exact file references. Do not infer project
    behavior from absent evidence and do not modify files.
  - |
    Return Resource Extraction, Source Credibility and Freshness, Ecosystem Evidence,
    Project Comparison, Contradictions and Unknowns, and Citations. Rate every
    significant finding so the user can weigh it: High = multiple corroborating
    authoritative sources, data within 6 months, no conflict; Medium = one authoritative
    source or several agreeing non-authoritative ones, data 6-18 months old, minor
    caveats; Low = one non-authoritative source, data older than 18 months, conflicting
    evidence, or extrapolation (worth investigating before acting).
verification:
  seam: Reopen every citation and compare each extracted claim, credibility judgment, date, project reference, and confidence rating with the full source content and repository evidence
  expected: The extraction and project comparison are complete, current, citation-backed, explicit about unknowns, and contain no fabricated or strengthened claim
```

Consume the exact Harness Result. Accept research only from `status: accepted` with
`evidence.outcome: proven`, then reproduce the verification seam. A summary, exit code,
or inaccessible citation is not proof.

---

## Phase 6: Compare and Analyze

When accepted sources are contradictory or a high-impact recommendation depends on a
contested claim, materialize the disputed claim, full citations, credibility
assessments, excerpts, and project impact as one immutable snapshot digest. Invoke
`harness:delegate` with `operation: review` and `route: review` before synthesis.

```yaml
operation: review
route: review
outcome: Adjudicate one contradictory or insufficiently corroborated high-impact deep-dive claim without changing project or report files
context:
  project: {project_id}
  mode: fresh
  state: {disputed claim, source excerpts, publication dates, credibility assessments, corroboration attempts, and project impact}
  files: [{read-only repository-relative immutable claim packet when materialized as a file}]
authority:
  working_directory: {absolute primary repository root}
  allowed_paths: [{read-only immutable claim packet, cited evidence, and bounded project references}]
  tools: [read-only source and repository inspection]
  approvals: []
constraints:
  - Compare the contradictory evidence without strengthening either position
  - Assess source credibility, freshness, authority, directness, corroboration, and incentives
  - Verify all citations and project references and identify what remains unknown
  - Report whether the high-impact claim is supported, refuted, or unresolved; do not edit files
verification:
  seam: Reopen every citation and reproduce the credibility and project-impact comparison against the immutable claim packet
  expected: The adjudication names the best-supported position and every unresolved uncertainty with no fabricated claim
  fixed_target: {immutable digest of the contradictory or high-impact claim packet and cited evidence}
```

Only use an adjudication with `status: accepted`, matching `evidence.fixed_target`,
and `evidence.outcome: proven`. Otherwise keep the contradiction visible and do not
base a recommendation on it.

### Branch Manifest

Build the Branch Manifest before synthesis with one row for every scheduled resource,
concept bundle, and adjudication. For a returned result, record branch identity, exact
Harness `status`, evidence outcome, blockers, and elapsed when available (`unavailable`
otherwise). When no Harness Result exists, retain the expected identity. Record
`status: unavailable (no result)` as a Product Pulse manifest sentinel, not a Harness
status; record evidence outcome `unproven`, blocker `missing Harness Result`, and elapsed
`unavailable`; count that row as unproven for coverage and exclude its claims. Only
accepted/proven branches whose verification seam Product Pulse reproduced may contribute
content. Keep every other expected branch in the manifest and exclude its claims.

Invoke `harness:delegate` with `operation: execute` and `route: taste` for the final
analysis draft. Product Pulse remains the accepting workflow and publishes the report
only after checking the returned Harness Result.

```yaml
operation: execute
route: taste
outcome: Synthesize accepted deep-dive research into a decisive, citation-preserving report draft for this project
context:
  project: {project_id}
  mode: fresh
  state: {complete branch manifest, research question, accepted extraction and project-comparison results, accepted adjudications, prior-report index, product context, and intended slug}
  files: [{repository-relative project and prior-report paths cited by accepted research}]
  memory:
    enabled: {memory.connector is not null}
    recall: []
    capture:
      - when: accepted
        type: insight
        summary: Deep dive on {topic}: {key conclusion in fewer than 80 characters}
        content: {proven findings, project comparison, confidence, and recommendations}
        topics: [deep-dive, {project_id}-research, {topic tags}]
      - when: accepted and a proven conclusion reverses a referenced prior report
        type: decision
        summary: Deep-dive conclusion changed for {topic}
        content: {prior conclusion, new evidence, and bounded reason for the change}
        topics: [deep-dive, {project_id}-research, changed-conclusion]
authority:
  working_directory: {absolute primary repository root}
  allowed_paths: [{read-only paths named in context.files}]
  tools: [read-only inspection]
  approvals: []
constraints:
  - |
    Product Pulse deep-dive synthesis:
    Synthesize the accepted resource extracts, ecosystem evidence, adjudications, prior
    research, and project comparison. Separate source fact, project observation, and
    inference. Preserve citations, source credibility and freshness caveats, confidence
    ratings, contradictions, and unknowns. Never fabricate or strengthen a claim.
  - |
    Return Resource Summary; Cross-Reference Analysis when multiple resources exist;
    Ecosystem Context; Project Comparison with exact files and patterns; Risks & Gaps;
    Prior Research when relevant; ## Sources with compact citation links; and concrete,
    prioritized Action Items. Each action includes why, effort, confidence, tradeoffs,
    and the evidence it follows from. Make actionable recommendations and say when the
    project's current approach is better or source advice does not apply. Be
    opinionated: say "do X", and say plainly when something is a bad idea.
  - |
    Cross-reference resources, ecosystem research, prior reports, and the project:
    features worth adding, over-engineering that a simpler approach would fix,
    under-engineering that breaks at scale, latent bug or reliability risks, and
    fundamentally different approaches with their tradeoffs. When a topic overlaps a
    prior report, cite its slug, state its conclusion, and say whether this research
    confirms, contradicts, or extends it; flag a contradiction prominently.
  - |
    The chat and saved report bodies must match. Include complete YAML frontmatter data
    and intended report path {research_dir}/deep-dives/{slug}.md; use the next numeric
    suffix instead of overwriting an existing report. Do not write or publish files.
  - |
    Report coverage as expected, accepted/proven, failed, blocked, abandoned, and
    unproven. Count an accepted/unproven result as unproven, not accepted. Mark degraded
    coverage whenever accepted/proven is fewer than expected. Never describe a failed,
    blocked, abandoned, unproven, or missing branch as scanned, researched, or covered.
verification:
  seam: Trace every report claim and actionable recommendation to accepted cited evidence and verify branch manifest totals, including no-result unproven classification, degraded-coverage disclosure, project references, confidence, required sections, frontmatter data, and report path
  expected: The report draft is decisive, source-faithful, project-specific, complete, accurately discloses coverage, and ready for Product Pulse publication
```

Require `status: accepted` and `evidence.outcome: proven`, then reproduce the seam.
Reject a draft that changes a citation, hides a contradiction, invents a project fact,
or drops a required section.

---

## Phase 7: Deliver Report in Chat

Present the accepted draft in chat. Open with `### Research Coverage`: expected,
accepted/proven, failed, blocked, abandoned, and unproven counts; the failed and blocked
branch identities; and `— degraded coverage` whenever accepted/proven is fewer than
expected. Then give the sections the Phase 6 synthesis packet lists, in its order,
ending with an Action Items table:

| # | Action | Why | Effort | Confidence |
|---|--------|-----|--------|------------|

Effort is quick win, moderate, or significant. A quick take uses the sections that apply,
the same confidence definitions from the Phase 5 packet, and the same opinionated stance.

---

## Keep the Conversation Going

On the two chat paths, the delivered findings are an opening, not an ending. End the
turn on the report: close it with one plain-text line offering the next steps, and do
not call the structured question UI after it. Some hosts show only a turn's last
assistant message once the turn ends, so text before a question hides the report.

- **Dig deeper into a finding** — ask which one, research that thread, and answer in
  chat. This is a follow-up, not a new report.
- **Go to the next depth** — a quick take becomes full research; full research becomes
  a saved report and PR, running Phases 8–10 on the research already accepted.
- **Done** — stop without writing files or opening a pull request.

Offer them again after each follow-up until the user is done. A quick take is never
saved directly: a saved report carries proven Research Coverage, so it goes through
full research first.

---

## Phase 8: Save Report

Saved path only.

Save the same report content from Phase 7 to `{output_dir}/{slug}.md`. The slug is derived from the primary topic (e.g., `react-server-components.md`, `auth-middleware-comparison.md`). Use kebab-case, no dates in the slug. If a file with the same slug already exists, append `-2` (or the next available number) to avoid overwriting prior research.

Wrap the report in YAML frontmatter matching the template at `references/report-template.md`. The frontmatter must include: title, resources (url, type, title, published), tags, and related_reports (slugs of prior reports referenced, omit if none). The body sections are the same as the chat report from Phase 7.
Include `### Research Coverage` before `### Resource Summary` with the same counts,
failed and blocked branch identities, and degraded-coverage disclosure as the chat.

---

## Phase 9: Save to Memory (if configured)

The Phase 6 synthesis request carries the insight capture intent and the conditional
changed-conclusion intent. After Product Pulse reproduces the report proof, retain any
returned Harness memory identifiers. If memory is disabled or unavailable, continue
with the saved report and leave those optional identifiers empty; do not call a
provider directly.

---

## Phase 10: Branch + Commit + PR

Saved path only.

Run § Publish in [Config_and_Publish.md](../../references/Config_and_Publish.md) with:

- `branch="deep-dive/{slug}"`
- `publish_path="$output_dir"`
- `title="research: deep dive on {topic}"`
- `body="Deep-dive research report on {topic}. Auto-generated by product-pulse deep-dive."`

It opens the PR with `gh pr create` and queues a squash merge only when `auto_merge` is true.

---

## Error Handling

- **Config missing**: On the saved path, stop and tell the user to run `/product-pulse:setup`. On the chat paths, continue without a research directory and say that saving needs setup.
- **Research context missing**: Same rule as a missing config.
- **Memory unavailable**: Continue without memory — skip Phase 9.
- **Transcribe failure**: Surface the error to the user and stop analysis of that resource. Do not guess at video content.
- **Git/PR failure**: Save the report locally and surface the error. The research is still valuable even if the PR fails.
