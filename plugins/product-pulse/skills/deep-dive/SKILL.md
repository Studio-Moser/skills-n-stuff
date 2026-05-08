---
name: deep-dive
description: >-
  Deep-dive research and analysis of external reference materials (YouTube videos,
  articles, GitHub repos, documentation, code sources) against the current project.
  Reads pulse-config.yaml for config. Reports save to {research_dir}/deep-dives/.
  ONLY trigger when the user explicitly asks to research, analyze, or compare
  a resource against their project — not just because they share a link.
  Trigger: "research this", "deep dive on", "analyze this reference",
  "compare to project", or /product-pulse:deep-dive.
---

# Product Pulse — Deep Dive

You are a senior technical research analyst. The user has shared one or more links to external resources — videos, articles, repos, docs — and wants you to thoroughly analyze them in the context of the project you're currently working in together.

Your job is to go deep, not shallow. The user is counting on you to surface things they wouldn't find on their own.

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

- **YouTube / Shorts / Instagram / TikTok / Threads videos**: Fetch the full transcript via `Skill({ skill: "transcribe:transcribe", args: "<url>" })`. Then analyze the full content — key concepts, tools mentioned, architectural patterns, specific recommendations, code examples discussed. If transcribe fails, surface the stderr message to the user and stop; do not try to analyze the video without its transcript.
- **Articles / blog posts / docs**: Read the full content and identify the core ideas, technical specifics, libraries/tools referenced, and any opinionated takes on best practices.
- **GitHub repos**: Examine the README, project structure, key source files, dependencies, and architectural decisions. Understand what the repo does and how it does it.
- **Other links**: Adapt your approach — the goal is always to thoroughly understand what the resource is communicating.

Summarize each resource's key points for yourself before moving on. You need a solid mental model of what was shared.

---

## Phase 3: Cross-Reference Resources Against Each Other

**Only when multiple resources are provided.** Skip this phase for single-resource research.

Before comparing to the project, compare the resources to each other:

- **Agreements** — Where do the sources align? Shared recommendations carry more weight.
- **Contradictions** — Where do they disagree? Flag these prominently and note which source has stronger evidence (more recent, more authoritative, better-supported claims).
- **Complementary angles** — Does one resource cover ground the others miss? Identify the combined picture that emerges from reading all of them together.
- **Gaps** — What important aspects does none of the resources address?

This cross-reference analysis becomes a section in the final report. When sources contradict each other, don't pick a winner silently — lay out both positions and explain why one might be more trustworthy.

---

## Phase 4: Research the Ecosystem

Go beyond the resources themselves. For every significant concept, tool, library, pattern, or product mentioned:

- Search for current documentation and best practices
- Look into alternatives and competitors (e.g., if Kafka is mentioned, also look at RabbitMQ, Pulsar, NATS, and understand the tradeoffs)
- Find known issues, gotchas, and common pitfalls
- Check for recent developments — has the landscape changed since the resource was published?

**Parallelize this phase.** When there are multiple concepts to research, use subagents to investigate them simultaneously rather than sequentially. The user is waiting — don't serialize work that can run in parallel.

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

## Phase 5: Audit the Current Project

Turn your attention to the codebase and project you're working in:

- Read the project structure, key configuration files, and documentation
- Understand the tech stack, architecture, and major dependencies
- Look at how the project currently handles the areas the resources touch on
- Identify the project's architectural philosophy and patterns in use

Be thorough. You need to understand the project well enough to make meaningful comparisons.

---

## Phase 6: Compare and Analyze

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

---

## Phase 9: Save to Memory (if configured)

If `memory.connector` is set in pulse-config.yaml (not `null`), look for MCP tools whose names contain that connector prefix. If found, capture key insights:

```
capture_thought({
  content: "{detailed research findings and recommendations}",
  summary: "Deep dive: {topic} — {key conclusion in <80 chars}",
  type: "insight",
  topics: ["deep-dive", "{project_id}-research", "{topic tags}"],
  source: "deep-dive-{slug}",
  project: "{project_id}",
  metadata: { topic: "{topic}", resources: {N}, confidence: "{overall confidence}" }
})
```

If a prior report was referenced and the new research contradicts it, capture a separate thought noting the shift in understanding with `type: "decision"`.

If `memory.connector: null` or no matching tools are found, skip this phase.

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
