---
name: deep-dive
description: >-
  Use when the user explicitly asks to research, analyze, or compare external
  videos, articles, repositories, documentation, or code against the current project.
allowed-tools: "Bash Read Write Edit Skill"
---

# Product Pulse — Deep Dive

You are a senior technical research analyst. The user has shared one or more links to external resources — videos, articles, repos, docs — and wants you to thoroughly analyze them in the context of the project you're currently working in together.

Your job is to go deep, not shallow. The user is counting on you to surface things they wouldn't find on their own.

Harness owns routing and execution. Invoke the named Harness skill through `Skill`;
do not read Harness skill, reference, script, or rubric files, and do not perform
Harness phases inside Product Pulse. Do not read or inspect the model rubric, and
do not resolve a model, effort, provider, or executor. Do not repair an unresolved
or blocked route inside Product Pulse; consume and report the typed Harness Result.

---

## Phase 0: Load Context

### 0.0 Discover Configuration

Walk up from cwd, checking each directory for `pulse-config.yaml` directly and in common research-dir subdirs (`research/`, `Research/`, `docs/research/`). The first match wins; that file's parent directory is the **research directory** (`{research_dir}`).

```bash
config_path=""
research_dir=""
dir="$PWD"
while [ "$dir" != "/" ]; do
  for sub in "" "research/" "Research/" "docs/research/"; do
    candidate="$dir/${sub}pulse-config.yaml"
    if [ -f "$candidate" ]; then
      config_path="$candidate"
      research_dir="$(cd "$(dirname "$candidate")" && pwd)"
      break 2
    fi
  done
  dir="$(dirname "$dir")"
done

if [ -z "$config_path" ]; then
  echo "No pulse-config.yaml found. Run /product-pulse:setup first." >&2
  exit 1
fi

primary_repo_root="$(cd "$research_dir" && git rev-parse --show-toplevel)"
default_branch="$(yq '.default_branch // "main"' "$config_path")"
auto_merge="$(yq '.auto_merge // true' "$config_path")"
project_id="$(yq '.project_id' "$config_path")"
memory_connector="$(yq '.memory.connector // "shelby"' "$config_path")"

output_dir="$research_dir/deep-dives"
mkdir -p "$output_dir"
```

Parse the YAML. Required fields: `project_id`, `repos`. Optional with defaults: `default_branch` (default `main`), `auto_merge` (default `true`), `memory.connector` (default `shelby`; set to `null` to disable).

Find the entry in `repos:` with `role: primary`. Its filesystem location (resolved relative to the directory containing pulse-config.yaml's parent) is the **primary repo root** (`{primary_repo_root}`) for git operations.

### 0.1 Read Product Context

Read `{research_dir}/research-context.md`. If missing, stop and tell the user to run `/product-pulse:setup`.

### 0.2 Pull Latest (all configured repos)

Iterate `repos:` from `pulse-config.yaml`. For each repo, resolve its absolute path relative to `{primary_repo_root}`'s parent directory, then pull the default branch:

```bash
for repo_path in $(yq '.repos[].path' pulse-config.yaml); do
  abs="$(realpath "$primary_repo_root/$repo_path")"
  echo "=== Pulling $abs ==="
  cd "$abs" && git checkout "$default_branch" && git pull origin "$default_branch" || echo "pull failed for $abs"
done
```

If any pull fails, note it and continue. Single-element `repos:` is the monorepo case — same loop, one iteration.

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

- **YouTube / Shorts / Instagram / TikTok / Threads videos**: Fetch the full transcript via `Skill({ skill: "transcribe:transcribe", args: "<url>" })` and pass the transcript as source content. If transcribe fails, surface the stderr message to the user and stop; do not analyze the video without its transcript.
- **Articles / blog posts / docs**: Fetch the full readable content plus canonical URL, title, author or publisher, and publication or update date.
- **GitHub repos**: Collect the README, project structure, key source files, dependencies, release state, and canonical repository URL needed for the research question.
- **Other links**: Adapt collection to the resource while preserving the full accessible content and metadata needed to verify later claims.

Record the full source content, canonical URL, title, author or publisher,
publication date or last-update date, and access failures. Do not analyze a video when
transcription fails and do not treat a snippet as the full source content.

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
Harness. For each resource or bounded concept bundle, invoke `harness:execute` with
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
    claims, corroborating evidence, contradiction, and analyst inference.
  - |
    Perform a bounded project comparison against the supplied current project facts and
    repository files: identify confirmed agreements, differences, applicable gaps,
    tradeoffs, and non-applicable advice with exact file references. Do not infer project
    behavior from absent evidence and do not modify files.
  - |
    Return Resource Extraction, Source Credibility and Freshness, Ecosystem Evidence,
    Project Comparison, Contradictions and Unknowns, and Citations. Rate each significant
    finding High, Medium, or Low confidence using the supplied Product Pulse definitions.
verification:
  seam: Reopen every citation and compare each extracted claim, credibility judgment, date, project reference, and confidence rating with the full source content and repository evidence
  expected: The extraction and project comparison are complete, current, citation-backed, explicit about unknowns, and contain no fabricated or strengthened claim
```

Consume the exact Harness Result. Accept research only from `status: accepted` with
`evidence.outcome: proven`, then reproduce the verification seam. A summary, exit code,
or inaccessible citation is not proof.

### Confidence Ratings

Assign a confidence level to every significant finding or recommendation:

- **High** — Multiple corroborating authoritative sources (official docs, well-known experts), recent data (within last 6 months), no conflicting information.
- **Medium** — Single authoritative source, or multiple non-authoritative sources that agree. Data may be 6-18 months old. Minor caveats exist.
- **Low** — Single non-authoritative source, stale data (18+ months), conflicting information from other sources, or the finding is speculative/extrapolated.

Always show the confidence level. This is how the user calibrates how much weight to give each recommendation. A low-confidence finding can still be valuable — it just means "investigate further before acting."

### Source Credibility and Freshness

For each resource the user shared and each source you find during research, assess:
- When it was published or last updated
- Whether the information is still current (ecosystems move fast — a 2-year-old article about a fast-moving framework may be dangerously outdated)
- Whether the source is authoritative (official docs vs. random blog post vs. well-known expert)

If a resource is stale or its advice has been superseded, flag that prominently.

---

## Phase 6: Compare and Analyze

When accepted sources are contradictory or a high-impact recommendation depends on a
contested claim, materialize the disputed claim, full citations, credibility
assessments, excerpts, and project impact as one immutable snapshot digest. Invoke
`harness:review` with `operation: review` and `route: review` before synthesis.

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

Invoke `harness:execute` with `operation: execute` and `route: taste` for the final
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
    project's current approach is better or source advice does not apply.
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

Cross-reference everything: resources, ecosystem research, prior reports, and the current project.

- **Features and capabilities**: What do the resources suggest that the project doesn't currently do? Would those additions be valuable given the project's goals?
- **Over-engineering**: Are there areas where the project is more complex than it needs to be? Do the resources or your research suggest simpler approaches?
- **Under-engineering**: Are there areas where the project is cutting corners that could cause problems at scale?
- **Bug risks**: Based on patterns discussed in the resources or known issues with the tools in use, are there latent bugs or reliability risks?
- **Alternative approaches**: Are there fundamentally different ways to solve the same problems? What are the tradeoffs?

### Reference Prior Research

When a topic overlaps with a prior report from `{research_dir}/deep-dives/`, reference it explicitly:

> "We investigated {topic} in `{report-slug}.md` and concluded {conclusion}. This new research {confirms/contradicts/extends} that finding because {reason}."

If current research contradicts a prior conclusion, flag it clearly — the user needs to know their understanding has shifted.

---

## Phase 7: Deliver Report in Chat

Present the full report directly in conversation using this structure:

### Research Coverage
Show expected, accepted/proven, failed, blocked, abandoned, and unproven counts; name
the failed and blocked branch identities; append `— degraded coverage` whenever
accepted/proven is fewer than expected.

### Resource Summary
Brief overview of each resource's key takeaways. Note publish dates and flag freshness concerns. Keep this concise — the user already knows what they shared.

### Cross-Reference Analysis
*(Only when multiple resources)* — Agreements, contradictions, complementary angles between the resources.

### Ecosystem Context
What you found in broader research that adds to or challenges what the resources presented. New developments, alternative tools, contrarian takes. Include links to useful sources. Tag each major finding with its confidence level.

### Project Comparison
The meat of the report. Walk through significant differences between what the resources recommend and how the current project operates. Be specific — reference actual files, patterns, and dependencies.

### Risks & Gaps
Areas where the project might be vulnerable. Things that could cause bugs, scaling issues, security problems, or maintenance headaches.

### Prior Research
*(Only when prior reports are relevant)* — References to past analyses and how current findings relate.

### Sources
Compact list of the most valuable links discovered during research.

### Action Items
Concrete, prioritized list of suggestions:

| # | Action | Why | Effort | Confidence |
|---|--------|-----|--------|------------|

Each item states: what to do, why it matters, rough effort (quick win / moderate / significant), and confidence level.

**Be opinionated.** The user wants your honest assessment, not "it depends." If something is a bad idea, say so. If the project is already doing something better than the resources suggest, call that out.

---

## Phase 8: Save Report

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

Inside the primary repo:

```bash
cd "$primary_repo_root"
branch="deep-dive/{slug}"
git checkout -b "$branch" 2>/dev/null || git checkout "$branch"  # reuse branch if re-running
git add "$output_dir"
git commit -m "research: deep dive on {topic}"
git push -u origin "$branch"
pr_url=$(gh pr create --base "$default_branch" --head "$branch" \
  --title "research: deep dive on {topic}" \
  --body "Deep-dive research report on {topic}. Auto-generated by product-pulse deep-dive." \
  | tail -n1)
echo "PR opened: $pr_url"
```

### Auto-merge (if enabled)

If `auto_merge: true` in config:

```bash
sleep 8
gh pr merge "$pr_url" --squash --delete-branch --auto || \
  echo "Auto-merge declined; PR sits for human review at $pr_url"
```

`--auto` queues the merge if checks are still running. If branch protection or required reviews block the merge, the PR sits for human review and the skill exits cleanly with the PR URL surfaced.

---

## Important Notes

- **Depth over speed.** Take the time to actually research — don't skim and summarize.
- **Be specific about the project.** Generic advice like "consider adding tests" is useless. Point to actual code, actual gaps, actual files.
- **Explain tradeoffs honestly.** There's rarely a universally "best" tool — it depends on constraints and goals.
- **Flag stale information.** If a resource is outdated or conflicts with current best practices, say so clearly.
- **If you can't access a link** (paywall, auth required, etc.), say so upfront and work with whatever context the user can provide.
- **Confidence ratings are not optional.** Every significant finding or recommendation gets one. This is how the user decides what to act on vs. what to investigate further.

---

## Error Handling

- **Config missing**: Stop and tell the user to run `/product-pulse:setup`.
- **Research context missing**: Stop and tell the user to run `/product-pulse:setup`.
- **Memory unavailable**: Continue without memory — skip Phase 9.
- **Transcribe failure**: Surface the error to the user and stop analysis of that resource. Do not guess at video content.
- **Git/PR failure**: Save the report locally and surface the error. The research is still valuable even if the PR fails.
