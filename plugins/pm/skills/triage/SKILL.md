---
name: triage
description: >-
  Process status/needs-triage items through the full pipeline: sort (reject/dedup),
  spec (brainstorming + writing-plans for M/L/XL items), score against the
  agent-ready checklist, and promote to status/ready (with owner/ai or owner/human)
  or reject to out-of-scope. Interactive — you confirm every decision.
  Trigger: "triage", "process backlog", "review incoming items", "spec items",
  or /pm:triage. Do NOT use for building ready items (that's /pm:sprint-dev),
  syncing completed work (that's /pm:reconcile), or ingesting raw research
  (that's /pm:ingest) — triage only classifies, specs, scores, and promotes
  needs-triage items.
effort: high
allowed-tools: "Bash Read Write Edit Agent Skill"
paths: ["**/.pm/**", "**/planning/todos.md"]
---

# PM — Triage

You are the triage pipeline. Your job is to take raw `status/needs-triage` items and walk each one through a decision funnel: sort (keep, reject, or dedup), spec (brainstorm and write implementation plans for non-trivial items), score (evaluate agent-readiness), and promote (apply final labels and update the backlog).

You are NOT the ingestion agent — that's `/pm:ingest`. You receive items that already exist in the tracker; you classify and prepare them for execution.

---

## Ground Rules

- **Interactive.** You present recommendations; the user confirms every decision. Never reject, promote, or modify an item without explicit user approval.
- **One item at a time for speccing.** Phase 2 (Spec) is the most time-intensive phase. Process one item through brainstorming and spec writing before asking the user if they want to continue to the next.
- **Batch-friendly for sorting and scoring.** Phases 1 and 3 can present items in quick succession since decisions are lightweight.
- **Idempotent.** Running triage on an already-triaged item (no `status/needs-triage` label) is a no-op. Never re-process promoted items.
- **No fabrication.** Size, priority, and recommendations are based on the item's content, domain context, and out-of-scope history. Do not invent requirements.
- **Error tolerant.** If one item fails to process, log it and continue with others.

---

**Backend dispatch.** PM uses one backend per project. Load ONLY `references/triage-<backend>.md` (`triage-github.md`, `triage-trello.md`, or `triage-local.md`) and follow its steps wherever a phase below is marked **(backend step)**. Ignore the other backends' files.

---

## Phase 0: Discover Config and Load Items

### 0.0 Pre-resolved Configuration

All config values are pre-resolved at skill load time. If you see `ERROR:` in the output below, stop and tell the user.

```
!`${CLAUDE_PLUGIN_ROOT}/scripts/discover-config.sh`
```

Parse the key=value pairs above. The `research_dirs` value is colon-separated (split on `:`). The `repos_json` value is a JSON array of repo objects.

### 0.1 Load Domain Context

Read the project's domain glossary and rejection knowledge base. These inform sorting and speccing decisions.

```bash
context_md_path="$primary_repo_root/$(yq '.context_md // "CONTEXT.md"' "$pm_config")"
oos_dir="$primary_repo_root/$(yq '.out_of_scope_dir // ".pm/out-of-scope"' "$pm_config")"
```

Read `CONTEXT.md` for domain terms — you will reference these during brainstorming and spec writing to ensure correct terminology.

Read the `out-of-scope/` directory listing (excluding `README.md`). For each `.md` file, read its feature name and decision summary. Build a rejection index.

**Only rejections belong in the index.** Skip files whose header marks them as deferrals or archive snapshots (e.g. `**Status:** Deferred`, "archived", "move-don't-close") — a deferral is postponed work, not a scope decision, and treating it as a rejection poisons dedup with false negatives.

```bash
oos_entries=()
if [ -d "$oos_dir" ]; then
  for f in "$oos_dir"/*.md; do
    [ "$(basename "$f")" = "README.md" ] && continue
    [ -f "$f" ] || continue
    oos_entries+=("$f")
  done
fi
```

Print: `"Loaded {N} domain terms from CONTEXT.md and {M} out-of-scope rejections."`

### 0.2 Pull Needs-Triage Items

**(backend step)** — follow your loaded `references/triage-<backend>.md` (§ Phase 0.2: Pull Needs-Triage Items).

If zero items across all boards, print `"No status/needs-triage items found across {N} configured board(s). Nothing to do."` and exit cleanly.

If zero items are found, print `"No status/needs-triage items found. Nothing to do."` and exit cleanly.

Otherwise print: `"Found {N} status/needs-triage item(s). Starting triage pipeline."`

### 0.3 Load Existing Open Items (for dedup)

Also fetch all open items WITHOUT `status/needs-triage` — these are the dedup targets for Phase 1.

**(backend step)** — follow your loaded `references/triage-<backend>.md` (§ Phase 0.3: Load Existing Open Items (dedup pool)).

---

## Phase 1: Sort

Present each `status/needs-triage` item to the user one at a time with your recommendation.

### For each item, evaluate and recommend one of:

**Reject** — The item is clearly out of scope, matches a previous rejection, or is not actionable for this project.

Criteria for reject recommendation:
- The item's **concept** matches an existing out-of-scope entry. Match by concept similarity, not keyword overlap — "night theme" matches `dark-mode.md`. When a match is found, don't auto-reject: surface it — `"We rejected this before because {reason} — still feel the same way?"` The user confirms (append to the entry's Prior requests, close), reconsiders (delete or update the entry, continue normal triage), or calls it distinct (proceed).
- The item is a vague wish with no concrete outcome ("make it better", "improve performance")
- The item targets a platform, language, or domain the project does not cover

**Duplicate** — The item substantially overlaps an existing open item.

Criteria for duplicate recommendation:
- The item's title or description shares > 80% significant-word overlap with an existing open item (significant words = 3+ characters, excluding stop words)
- Similarity = `(shared significant words) / (min(words_in_A, words_in_B))`

**Keep** — The item is in scope, not a duplicate, and should proceed to speccing/scoring.

### Present each item

For each item, show:

```
--- Item {i}/{N} ---
Title:       {title}
Source:      {GitHub #{number} | local file {filename}}
Description: {first 3 lines of body, or full body if short}
Size:        {suggested size from labels, or your estimate: S/M/L/XL}

Recommendation: {KEEP | REJECT | DUPLICATE}
Reason:         {one-line explanation}
{If DUPLICATE: "Matches: #{existing_number} — {existing_title}"}
{If REJECT: "Matches out-of-scope: {slug}" or "Not actionable: {reason}"}
```

Ask the user: `"Confirm? (yes / reject / keep / duplicate / skip)"`

- **yes** — accept the recommendation as-is
- **reject** — override to reject (prompts for reason)
- **keep** — override to keep
- **duplicate** — override to duplicate (prompts for which item it matches)
- **skip** — skip this item entirely, leave as `status/needs-triage`

### Process rejections

Out-of-scope entries record **rejected enhancements only** — one file per concept. Never write one for a bug (bugs are fixed or closed, not scoped out) or for an already-implemented item (point to where it lives instead; a false rejection would poison future dedup). If the rejected concept already has an entry, append to its Prior requests instead of creating a new file.

When an enhancement is rejected (by recommendation or override), create an out-of-scope entry using the template at `plugins/pm/templates/out-of-scope-entry.md`:

```bash
slug=$(echo "{title}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//' | cut -c1-60)
oos_file="$oos_dir/${slug}.md"
```

Write the rejection file:

```markdown
# {Item Title}

**Decided:** {TODAY's DATE}
**Status:** Rejected

## Decision

{User-provided reason, or: "Rejected during triage — {your recommendation reason}"}

## Reasoning

{Brief trade-off analysis based on the item's content and project context}

## Prior requests

- {TODAY's DATE}: {source — e.g. "product-pulse daily research" or "manual submission"} — {one-line context}
```

Then close the item in the backend:

**(backend step)** — follow your loaded `references/triage-<backend>.md` (§ Phase 1: Process rejections).

### Process duplicates

When an item is marked as a duplicate:

**(backend step)** — follow your loaded `references/triage-<backend>.md` (§ Phase 1: Process duplicates).

### Sort summary

After all items are sorted, print:

```
Phase 1 — Sort Complete
  Kept:       {X}
  Rejected:   {Y}
  Duplicates: {Z}
  Skipped:    {W}
```

If zero items were kept, print `"No items survived sorting. Triage complete."` and skip to Phase 5.

---

## Phase 2: Spec

For items that survived Phase 1, determine which need speccing and which can skip to scoring.

### Classify by size

- **S-sized items** with a clear, complete description (the body already states what to build and has implicit acceptance criteria): skip speccing, proceed directly to Phase 3.
- **M/L/XL items** or any item with an unclear/incomplete description: run the full spec creation flow.

Present the classification to the user:

```
Phase 2 — Spec Planning
  Skip to scoring (S-sized, clear): {list of titles}
  Need speccing (M/L/XL or unclear):  {list of titles}

Proceed with speccing? (yes / reorder / stop)
```

- **yes** — start speccing in the listed order
- **reorder** — user provides a different order or removes items
- **stop** — skip speccing entirely, send all items to Phase 3 as-is

### Spec creation flow (for each item needing a spec)

Process one item at a time. For each:

#### Step 2a: Brainstorm

Invoke the brainstorming skill with the item as the problem statement. Pass all relevant context as the `args` parameter so the skill has what it needs:

```
Skill({ skill: "superpowers:brainstorming", args: "{item title}: {item description}\n\nDomain context: {relevant CONTEXT.md terms}\nConstraints: {relevant out-of-scope entries}\nRepos: {repo list from pulse-config.yaml with paths}" })
```

The brainstorming skill will explore the design space and produce a recommended approach.

#### Step 2b: Write implementation plan

After brainstorming produces a design direction, invoke the writing-plans skill. Pass the brainstorming output as context:

```
Skill({ skill: "superpowers:writing-plans", args: "Write a spec for: {item title}\n\nBrainstorming output: {brainstorm result summary}\nTarget repo: {repo path}" })
```

The writing-plans skill produces a structured implementation plan with tasks, code, and acceptance criteria.

#### Step 2c: Write spec to backend

**(backend step)** — follow your loaded `references/triage-<backend>.md` (§ Phase 2, Step 2c: Write spec to backend).

All backends write the spec using this body structure:

```markdown
## Goal

{One paragraph — what this achieves}

## Context

{Why this matters now. Link to source report if applicable.}

## Code References

{Specific files, modules, APIs in the target repo that this touches}
- `{repo_name}/{path/to/file.ext}` — {what it does}

## Approach

{How to implement. Step-by-step, specific enough for an agent.}

## Chunks

{For L/XL items — ordered chunks that can be committed independently}

1. {Chunk 1 — description}
2. {Chunk 2 — description}

## Acceptance Criteria

- [ ] {Criterion 1}
- [ ] {Criterion 2}

## Negative Constraints

- Do NOT {constraint from out-of-scope or brainstorming}
- See `.pm/out-of-scope/{slug}.md` for related rejections

---
*Spec written by /pm:triage on {DATE}*
```

#### Step 2d: Checkpoint

After each spec is written, print:

```
Spec complete for: {title}
  Size: {size}  Priority: {priority}
  Spec: {path or issue URL}
  Chunks: {N}

Continue to next item? (yes / stop)
```

- **yes** — proceed to the next item needing a spec
- **stop** — halt speccing. Remaining items will enter Phase 3 without specs (they will likely fail the scorecard, which is fine — the user can resume triage later).

---

## Phase 3: Score

Evaluate each item that survived Phase 1 (both specced and unspecced) against the agent-ready scorecard.

### Dispatch the scorecard evaluator

For each item, read `plugins/pm/agents/scorecard-evaluator.md` and use its content as the system prompt for an Agent tool call. Provide in the user prompt:

- The item's title, description, and spec (if one was written in Phase 2)
- The project's CONTEXT.md content
- The `.pm/out-of-scope/` directory listing
- The list of configured repos from `pulse-config.yaml`

The agent returns a per-criterion PASS/FAIL with explanations and a verdict.

### Agent-Ready Scorecard

```
Agent-Ready Scorecard:
1. [ ] Clear description (what, not how)
2. [ ] Explicit acceptance criteria
3. [ ] Linked code references with target repo
4. [ ] Negative constraints (cross-refs .pm/out-of-scope/)
5. [ ] Bounded scope (single deliverable, one repo)
6. [ ] No open design questions
```

### Present results

For each item, show:

```
--- Scorecard: {title} ---
Score: {X}/6

1. {PASS|FAIL} Clear description        — {explanation}
2. {PASS|FAIL} Acceptance criteria       — {explanation}
3. {PASS|FAIL} Code references           — {explanation}
4. {PASS|FAIL} Negative constraints      — {explanation}
5. {PASS|FAIL} Bounded scope             — {explanation}
6. {PASS|FAIL} No open design questions  — {explanation}

Verdict: {status/ready+owner/ai | status/ready+owner/human | needs-info}
```

### Claim verification (bugs)

A bug report's description is a claim, not a fact — verification is the step that separates triage from ad-hoc labelling. Before any bug-flavored item (label `bug`, or a body describing broken behavior) can receive a `status/ready` verdict, attempt to verify it:

- **Reproduce it** from the reported steps, or confirm the failing code path by reading the code (cite the path).
- **Confirmed** → note the repro/code path in the spec or a comment; proceed to the verdict.
- **Could not reproduce / claim contradicts the code** → cap the verdict at `needs-info` and record what you tried. The user can override to promote anyway.
- **Verification impractical** (needs hardware, credentials, or a long-running setup) → say so explicitly and let the user decide; never silently skip.

Enhancements skip this gate — there is no claim to verify.

### Verdict thresholds

| Score | Verdict | Meaning |
|-------|---------|---------|
| 6/6 | `status/ready` + `owner/ai` | Fully specced, agent can pick up immediately |
| 4-5/6 | `status/ready` + `owner/human` | Minor gaps — human should review before agent work |
| 0-3/6 | `needs-info` (stays as `status/needs-triage`) | Major gaps — not ready for anyone |

### User decision

For items scoring 6/6, recommend `status/ready` + `owner/ai`. For 4-5/6, recommend `status/ready` + `owner/human`. For 0-3/6, recommend `needs-info`.

Ask the user:

```
Accept verdict? (yes / fix / human / info / skip)
```

- **yes** — accept the recommended verdict
- **fix** — fix the failing criteria now. For each FAIL, present the suggested fix from the scorecard evaluator and apply it to the spec inline. After fixing, re-score (loop back through the scorecard for changed criteria only).
- **human** — override to `status/ready` + `owner/human` regardless of score
- **info** — override to `needs-info` (leave as `status/needs-triage` for later)
- **skip** — skip this item, leave unchanged

#### Fixing inline

When the user chooses **fix**, iterate through each failing criterion:

```
Fix {criterion name}?
  Current: {what's there now, or "missing"}
  Suggested: {scorecard evaluator's suggestion}

Apply this fix? (yes / edit / skip)
```

- **yes** — apply the suggested fix to the spec
- **edit** — user provides their own text for this criterion
- **skip** — leave this criterion as-is (it will still FAIL)

After all fixes are applied, update the spec in the backend (same write path as Phase 2 Step 2c) and re-evaluate only the fixed criteria.

---

## Phase 4: Promote

For items the user approved with a verdict of `status/ready` + `owner/ai` or `status/ready` + `owner/human`, apply final labels and update the backlog.

### 4.1 Determine labels

For each promoted item, gather:
- **Status label**: always `status/ready` when promoting (anything else stays as `status/needs-triage` or gets rejected)
- **Owner label**: `owner/ai` for 6/6 verdicts, `owner/human` for 4-5/6 verdicts
- **Size label**: `size/S`, `size/M`, `size/L`, or `size/XL` (from the spec or your estimate)
- **Priority label**: `priority/p0` / `priority/p1` / `priority/p2` / `priority/p3` (set if known; otherwise leave to the user)
- **Target repo label**: `repo/{repo-name}` for multi-repo workspaces

### 4.2 Update backend

**(backend step)** — follow your loaded `references/triage-<backend>.md` (§ Phase 4.2: Update backend (promote)). Where applicable, `{owner_label}` is `owner/ai` (6/6 verdict) or `owner/human` (4-5/6 verdict).

GitHub also has an optional Project Status-field mirror step — see § Phase 4.2a in `references/triage-github.md` if `github.project_sync` is enabled.

### Approval cues (Trello-specific)

**Trello backend:** see [`references/triage-trello.md`](../../references/triage-trello.md) — the synchronous/asynchronous confirmation modes and natural-language approval-cue detection for Trello cards. (Skip if backend != trello.)

### 4.3 Link to a parent epic (REQUIRED — every promoted item gets exactly one)

**Every item you promote must land under exactly one parent epic — no orphans.** A todo with no epic parent does not group under any epic in the project's "Sprint Plan" / group-by-Parent-issue view, which is the whole point of the board. So this is a required step, not an optional one. Do not promote an item to `status/ready` until it has an epic.

Determine the item's epic, in order of preference:

1. **Explicit reference** in the item body (e.g. "Part of Epic 1 (#236)").
2. **Infer from the open epics.** List currently open epics **(backend step — see `references/triage-<backend>.md` § Phase 4.3)** and match by area (memory work → the memory epic; a specific UI surface → that surface's epic; sync/reliability → the reliability epic; etc.). Per-surface UI work goes under that surface's epic, not a generic one.
3. **Ask** if still ambiguous: "Which epic does this belong under? {short list}". Pick before promoting.

**Creating a new epic (when none fits).** If the area genuinely has no epic yet, create one before linking — don't force the item under an ill-fitting parent. An epic is a **goal container**, so author it accordingly:

- **Labels: `epic` only.** Never give an epic a `status/*` label and never place it in a board status column. An epic carries no workflow status — its progress *is* the native sub-issue progress bar, and its membership *is* the sub-issue tree. (Lifecycle still applies: `/pm:reconcile` closes an epic once all its sub-issues close.)
- **Body = the goal, nothing else.** State the end-state and why it matters, written like a goal prompt you'd hand Claude Code — not a checklist of constituent items (that just drifts from the sub-issue tree, which is the real source of truth for membership). Use this shape:

  **Epic body template:**

  ```markdown
  ## Goal
  {The end-state we're driving toward, in one or two sentences.}

  ## Why
  {Why this matters — what's true once this is done.}
  ```

**(backend step)** — follow your loaded `references/triage-<backend>.md` (§ Phase 4.3: Link to a parent epic) to create the epic and link the promoted item to it. Capture the new epic's number to use as `{epic_number}`.

**No-epic escape hatch.** If an item genuinely belongs to no epic (rare — e.g. a standalone strategy/positioning note or a pure competitor-watch item), do NOT leave it silently unparented. Add a `no-epic` label so it's a deliberate, auditable choice rather than an oversight, and `/pm:reconcile` can surface accidental orphans (todos that are neither under an epic nor labelled `no-epic`).

### 4.4 Update planning/todos.md

> When backend == trello, the row's `#{number}` is the card's Trello short id (e.g. `t-AbCdEfGh`); `{spec path or "—"}` is the card's `shortUrl`. Otherwise, the row format is identical.

If the project maintains the markdown backlog (`planning/todos.md` exists), add promoted items to the Ready section.

Read the current `planning/todos.md`. Find the `## Ready` section and the `### Sprint: Unassigned` subsection. Append a row for each promoted item:

```markdown
| #{number} | {title} | {size} | priority/p{priority} | status/ready ({owner_label}) | {spec path or "—"} | {TODAY} | — |
```

For `needs-info` items, do NOT add to Ready — they stay in triage. For items promoted with `owner/human`, add to Ready with status `status/ready` and the `owner/human` label (these still need code work, but a human should review the spec gaps first):

```markdown
| #{number} | {title} | {size} | priority/p{priority} | status/ready (owner/human) | {spec path or "—"} | {TODAY} | {failing criteria} |
```

---

## Phase 5: Summary

After all items are processed, print:

```
PM — Triage Complete
=====================
Items processed:          {total}
Rejected (out-of-scope):  {X}
Duplicates closed:        {Y}
Skipped:                  {Z}
Specced:                  {W}
Promoted to status/ready + owner/ai:    {A}
Promoted to status/ready + owner/human: {B}
Left as needs-info (status/needs-triage): {C}

{If GitHub: "Issues updated in {owner}/{repo}"}
{If local: "Items updated in {items_dir}"}

{If A > 0: "Next: Run /pm:sprint-dev to pick up status/ready + owner/ai items."}
{If B > 0: "{B} item(s) need human review before agent work."}
{If C > 0: "{C} item(s) need more information — re-run /pm:triage after adding details."}
```

---

## Error Handling

- **pulse-config.yaml missing**: Stop — run `/product-pulse:setup` or `/pm:setup`.
- **.pm/config.yml missing**: Stop — run `/pm:setup`.
- **No status/needs-triage items**: Exit cleanly with message. Not an error.
- **CONTEXT.md missing**: Warn, continue without domain context. Recommend running `/pm:setup`.
- **out-of-scope directory missing**: Warn, continue without rejection checking. Create the directory.
- **gh CLI unavailable or unauthenticated**: Stop for GitHub backend — install `gh` and run `gh auth login`.
- **Brainstorming or writing-plans skill unavailable**: Warn the user. Offer to write a minimal spec manually instead of invoking the skill. The triage pipeline should not hard-fail because a superpowers skill is missing.
- **Scorecard evaluator failure**: Fall back to manual scoring — present the 6-point checklist and ask the user to score each criterion.
- **GitHub sub-issue API unavailable**: Fall back to comment-based linking.
- **planning/todos.md missing**: Skip the backlog update step. Warn: `"planning/todos.md not found — skipping backlog row insertion. Run /pm:setup to create the backlog."`.
- **User stops mid-pipeline**: This is expected and fine. Items that haven't been processed remain as `status/needs-triage`. Print a partial summary of what was completed.
- **Item body is empty or malformed**: Flag it to the user during sorting. Recommend reject or keep with a note that it needs a description before speccing.
- **Trello card moved by user mid-skill**: If the skill loaded a card from `LIST_NEEDS_TRIAGE` and the user moved it to another list during the run, the move-to-target call from this skill will fail with "card already in list X". Surface the error, skip the item, and continue. Reconcile will catch up next run.
- **Approval cue ambiguous**: When neither a clear approval cue nor an explicit user response is available, ALWAYS ask. Do not infer.
