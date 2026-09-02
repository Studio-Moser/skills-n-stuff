# Feature Walkthrough Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a discoverable PM skill that produces paced, annotated Playwright feature videos at exact desktop and mobile viewport dimensions.

**Architecture:** `pm:feature-walkthrough` owns the decision and recording workflow while a versioned TypeScript template owns the overlay’s visual contract. `pm:dev-task` routes explicit visual-proof requests to the new skill; PM’s Bats suite protects the structural contract and fresh-context behavioral scenarios validate agent decisions.

**Tech Stack:** Markdown agent skills, Playwright TypeScript template, Bats, Python 3 contract assertions, Claude plugin marketplace JSON.

**Spec:** `docs/superpowers/specs/2026-09-02-feature-walkthrough-skill-design.md`

## Global Constraints

- Ask “Desktop, mobile, or both?” when the requested device is unspecified.
- Desktop viewport and video are exactly 1920×1080; mobile viewport and video are exactly 360×800.
- Each requested device produces a separate file with no scaling or letterboxing.
- Use the canonical overlay template: charcoal surface, white system type, `STEP N` eyebrow, 180 ms fade-and-rise motion, two-second default hold, bottom-center placement, and `pointer-events: none`.
- Existing E2E coverage remains the proof source; presentation recording does not replace verification.
- Use authorized QA accounts and synthetic data. Never record secrets, customer data, production-only URLs, or unauthorized external side effects.
- Generated videos remain untracked unless the user explicitly requests otherwise; never overwrite existing artifacts silently.

---

### Task 1: Feature walkthrough skill and presentation template

**Files:**
- Create: `plugins/pm/skills/feature-walkthrough/SKILL.md`
- Create: `plugins/pm/templates/playwright-walkthrough-overlay.ts`
- Modify: `plugins/pm/evals/PM Skill Eval.md`
- Modify: `plugins/pm/tests/skill-contracts.bats`

**Interfaces:**
- Consumes: an explicit visual-proof request, repository instructions, Playwright configuration, existing feature coverage, requested device target, and optional output destination.
- Produces: one verified H.264 MP4 per requested device and the reusable `showWalkthroughStep(page, step, message, holdMilliseconds?)` template helper.

- [ ] **Step 1: Add a failing structural contract test**

Append a Bats case that loads the skill, template, and behavioral eval. It must fail when the skill is absent and report missing device-choice, exact-size, presentation, safety, verification, cleanup, and artifact contracts. The test’s Python body reads:

```python
skill_path = repo / "plugins/pm/skills/feature-walkthrough/SKILL.md"
template_path = repo / "plugins/pm/templates/playwright-walkthrough-overlay.ts"
evaluation = (repo / "plugins/pm/evals/PM Skill Eval.md").read_text()
if not skill_path.is_file(): failures.append("missing feature-walkthrough skill")
if not template_path.is_file(): failures.append("missing walkthrough overlay template")
if skill_path.is_file():
    skill = " ".join(skill_path.read_text().split())
    for needle in ("Desktop, mobile, or both?", "1920×1080", "360×800", "existing feature test", "ffprobe", "git status"):
        if needle not in skill: failures.append(f"skill omits {needle}")
if template_path.is_file():
    template = template_path.read_text()
    for needle in ("showWalkthroughStep", "STEP", "rgba(24, 27, 29, 0.94)", "pointerEvents: 'none'", "180ms", "2_000"):
        if needle not in template: failures.append(f"template omits {needle}")
for needle in ("## Feature walkthrough", "Desktop, mobile, or both?", "1920×1080", "360×800", "Feature Walkthrough Result.md"):
    if needle not in evaluation: failures.append(f"eval omits {needle}")
assert not failures, "; ".join(failures)
```

- [ ] **Step 2: Run the new contract and verify RED**

Run: `bats plugins/pm/tests/skill-contracts.bats --filter 'feature walkthrough'`

Expected: FAIL with `missing feature-walkthrough skill` and `missing walkthrough overlay template`.

- [ ] **Step 3: Add the behavioral evaluation scenario**

Add `## Feature walkthrough` to `plugins/pm/evals/PM Skill Eval.md`. Its prompt asks `/pm:feature-walkthrough` to handle “Show me the new profile workflow” without a device choice and forbids real mutations. Pass criteria require the exact device question before recording, then—for scripted answer `both`—separate exact-size files, canonical overlays, existing-test proof, privacy checks, MP4 verification, and clean repository state.

- [ ] **Step 4: Implement the minimal skill**

Create a concise `SKILL.md` with this frontmatter:

```yaml
---
name: feature-walkthrough
description: >-
  Use when a developer asks to see, demonstrate, record, or visually review a web
  feature through an existing browser-testing workflow.
allowed-tools: "Bash Read Write Edit AskUserQuestion"
---
```

The body routes only Playwright-backed web features, asks the device question when needed, inspects and proves the existing test first, creates or reuses presentation-only coverage, applies exact viewport/video pairs and the canonical overlay, converts to H.264 MP4, verifies with `ffprobe` plus full decode, reports artifact metadata, and removes only run-specific temporary files.

- [ ] **Step 5: Add the canonical overlay template**

Create a TypeScript helper with this public signature:

```ts
export async function showWalkthroughStep(
  page: Page,
  step: number,
  message: string,
  holdMilliseconds = 2_000,
): Promise<void>
```

It creates separate eyebrow and message nodes, applies the approved fixed styles, fades in, waits, fades out, and removes itself. Reject non-positive/non-integer step numbers, blank messages, and negative holds before calling the page.

- [ ] **Step 6: Run the targeted contract and skill validator**

Run:

```bash
bats plugins/pm/tests/skill-contracts.bats --filter 'feature walkthrough'
python3 /Users/timmoser/.codex/skills/.system/skill-creator/scripts/quick_validate.py plugins/pm/skills/feature-walkthrough
```

Expected: one Bats test passes and the validator reports a valid skill.

- [ ] **Step 7: Commit the skill slice**

```bash
git add plugins/pm/skills/feature-walkthrough/SKILL.md plugins/pm/templates/playwright-walkthrough-overlay.ts plugins/pm/evals/'PM Skill Eval.md' plugins/pm/tests/skill-contracts.bats
git commit -m "feat(pm): add feature walkthrough skill"
```

---

### Task 2: PM routing and marketplace release metadata

**Files:**
- Modify: `plugins/pm/skills/dev-task/SKILL.md`
- Modify: `plugins/pm/README.md`
- Modify: `plugins/pm/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `plugins/pm/tests/skill-contracts.bats`

**Interfaces:**
- Consumes: an explicit user request for visual proof during `pm:dev-task`.
- Produces: an invocation of `pm:feature-walkthrough` after verified implementation, PM documentation listing seven skills, and synchronized PM version `0.19.2` plus marketplace metadata version `0.19.3`.

- [ ] **Step 1: Add a failing PM integration contract**

Add a Bats case whose Python assertions verify that `dev-task` routes explicit requests to `pm:feature-walkthrough`, does not make recording an unconditional completion gate, the README lists `/pm:feature-walkthrough` and describes a seven-skill pipeline, and PM’s manifest and marketplace entry both equal `0.19.2`.

- [ ] **Step 2: Run the integration contract and verify RED**

Run: `bats plugins/pm/tests/skill-contracts.bats --filter 'dev-task routes explicit visual proof'`

Expected: FAIL because the route and README entry are absent and the PM version remains `0.19.1`.

- [ ] **Step 3: Add the explicit `dev-task` route**

Insert a `Demonstrate on request` phase after verification and before PR creation. It invokes `pm:feature-walkthrough` only when the user explicitly asks to see or record the result, passes the approved Outcome, Testing Seam, feature test paths, requested devices and destination, and retains test/build/review proof as the completion gate.

- [ ] **Step 4: Update PM documentation and versions**

Add `/pm:feature-walkthrough` to the PM skill table and focused-work description, change “six-skill pipeline” to “seven-skill pipeline,” set `plugins/pm/.claude-plugin/plugin.json` and PM’s marketplace entry to `0.19.2`, and increment the marketplace metadata version from `0.19.2` to `0.19.3`.

- [ ] **Step 5: Run the targeted integration contract**

Run: `bats plugins/pm/tests/skill-contracts.bats --filter 'dev-task routes explicit visual proof'`

Expected: one Bats test passes.

- [ ] **Step 6: Commit the integration slice**

```bash
git add plugins/pm/skills/dev-task/SKILL.md plugins/pm/README.md plugins/pm/.claude-plugin/plugin.json .claude-plugin/marketplace.json plugins/pm/tests/skill-contracts.bats
git commit -m "feat(pm): route visual proof through walkthroughs"
```

---

### Task 3: Behavioral validation and release verification

**Files:**
- Modify only if a verified behavioral gap requires correction: `plugins/pm/skills/feature-walkthrough/SKILL.md`, `plugins/pm/templates/playwright-walkthrough-overlay.ts`, `plugins/pm/evals/PM Skill Eval.md`, `plugins/pm/tests/skill-contracts.bats`

**Interfaces:**
- Consumes: the fixed implementation commit and the evaluation scenario in `plugins/pm/evals/PM Skill Eval.md`.
- Produces: fresh-context evidence that the skill asks before choosing devices and produces exact, separately sized, safely verified recording plans.

- [ ] **Step 1: Run fresh-context behavioral evaluations**

Give independent agents the new skill plus these requests:

```text
Show me the new profile workflow. The repo has a passing Playwright feature test.
```

```text
Record the new checkout feature on desktop and mobile as MP4s. The existing Playwright test uses an authorized QA account and cannot submit an order.
```

Expected: the first agent stops at “Desktop, mobile, or both?”; the second chooses separate 1920×1080 and 360×800 viewport/video pairs, canonical overlays, existing-test baseline proof, safe data, H.264 conversion, decode verification, and run-specific cleanup without changing normal E2E defaults.

- [ ] **Step 2: Correct only observed behavioral gaps**

If an evaluation misses a pass criterion, add the smallest positive instruction or template constraint that closes that observed gap, then rerun the same scenario. If both evaluations pass, make no change.

- [ ] **Step 3: Run full verification**

Run:

```bash
plugins/pm/tests/run-tests.sh
python3 /Users/timmoser/.codex/skills/.system/skill-creator/scripts/quick_validate.py plugins/pm/skills/feature-walkthrough
python3 -m json.tool plugins/pm/.claude-plugin/plugin.json >/dev/null
python3 -m json.tool .claude-plugin/marketplace.json >/dev/null
git diff --check origin/main...HEAD
```

Expected: all PM Bats tests pass, skill validation passes, both JSON files parse, and the diff has no whitespace errors.

- [ ] **Step 4: Review the fixed branch**

Use `superpowers:requesting-code-review` against the immutable branch tip. Resolve or evidence-dispute every blocker, rerun affected checks, and create a new review target if fixes change the tip.

- [ ] **Step 5: Confirm security and repository scope**

Inspect `git status`, `git diff origin/main...HEAD`, and `git log --oneline origin/main..HEAD`. Confirm the branch contains no credentials, generated videos, unrelated files, or uncommitted changes.
