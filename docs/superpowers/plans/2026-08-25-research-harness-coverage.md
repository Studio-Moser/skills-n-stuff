# Research Harness Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every Product Pulse synthesis and report disclose the complete outcome of its expected research branches so degraded fan-in cannot look complete.

**Architecture:** Each existing Product Pulse skill builds a small in-memory branch manifest from current Harness Results immediately before synthesis. The complete manifest travels in the existing taste request's `context.state` and appears as a compact coverage statement in the output. No shared helper or Harness field is added.

**Tech Stack:** Markdown skills, Bats, Python 3 standard-library assertions

**Spec:** `docs/superpowers/specs/2026-08-25-consumer-harness-integrity-design.md`

## Global Constraints

- Modify only the three Product Pulse skills and `tests/harness-boundary.bats`.
- Add no runtime file, shared reference, template edit, dependency, Harness schema, retry, or telemetry store.
- Do not modify Shelby or memory behavior.
- Preserve current error tolerance: unsuccessful branches remain visible and synthesis continues from accepted/proven branches.
- Do not call a missing branch scanned, researched, covered, or successful.
- Use `telemetry.elapsed` only when Harness supplies it; record `unavailable` otherwise.

---

### Task 1: Require a complete branch manifest at every Product Pulse fan-in

**Files:**

- Modify: `plugins/product-pulse/tests/harness-boundary.bats:81-322`
- Modify: `plugins/product-pulse/skills/daily-research/SKILL.md:135-250,281-339,385-404`
- Modify: `plugins/product-pulse/skills/weekly-strategist/SKILL.md:124-288,320-435`
- Modify: `plugins/product-pulse/skills/deep-dive/SKILL.md:145-322,344-448`

**Interfaces:**

- Consumes: expected branch identities and existing Harness Result fields `status`, `evidence.outcome`, `telemetry.elapsed`, and `blockers`.
- Produces: an in-memory `Branch Manifest` passed through the existing synthesis request and a `Research Coverage` line or section in existing outputs.

- [ ] **Step 1: Run one fresh-context baseline pressure scenario**

Start a fresh agent with the current Product Pulse skills and give it this prompt
verbatim. Permit only temporary output below
`${TMPDIR:-/tmp}/product-pulse-coverage-eval/`:

```text
Dry-run the current Product Pulse fan-in behavior; do not browse, edit a repository,
publish, commit, or open a PR. Read the current daily-research, weekly-strategist, and
deep-dive skills. Simulate these exact Harness Results:

- Daily expected domains: platforms=accepted/proven, competitors=failed/unproven,
  audience=blocked/unproven.
- Weekly expected roles: Market Scout, Competitor Tracker, Audience Analyst, Growth
  Analyst, Product Scout. Market Scout, Audience Analyst, and Product Scout are
  accepted/proven; Competitor Tracker is abandoned/unproven; Growth Analyst is
  accepted/unproven.
- Deep-dive expected inputs: resource/video=accepted/proven,
  concept/graph-scheduling=failed/unproven, adjudication/shared-state=blocked/unproven.

For each workflow, show the exact state handed to taste synthesis and the coverage text
that would appear in its final report. Do not invent successful evidence for a missing
branch.
```

Expected RED: at least one current workflow can continue without a complete expected
versus accepted/failed/blocked/abandoned manifest or can describe attempted branches as
scanned coverage. Save the transcript and criterion result outside the repository.

- [ ] **Step 2: Add one failing structural contract to `harness-boundary.bats`**

Append:

```bash
@test "Product Pulse manifests every expected research branch before synthesis" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]) / "plugins/product-pulse/skills"
requirements = {
    "daily-research": ("every configured domain", "Research Coverage"),
    "weekly-strategist": ("five analyst roles", "Research Coverage"),
    "deep-dive": ("every scheduled resource, concept bundle, and adjudication", "Research Coverage"),
}
failures = []
for name, (expected_set, report_label) in requirements.items():
    text = (root / name / "SKILL.md").read_text()
    normalized = " ".join(text.split())
    lowered = normalized.lower()
    taste = re.search(r"```yaml\noperation: execute\nroute: taste\n(.*?)\n```", text, re.DOTALL)
    for phrase in (
        "Branch Manifest",
        expected_set,
        "status",
        "evidence outcome",
        "blockers",
        "elapsed when available",
        "unproven",
        "degraded coverage",
        report_label,
    ):
        if phrase.lower() not in lowered:
            failures.append(f"{name}: missing {phrase}")
    if not taste or "complete branch manifest" not in " ".join(taste.group(1).split()).lower():
        failures.append(f"{name}: taste synthesis does not receive complete branch manifest")
    manifest_position = text.find("Branch Manifest")
    taste_position = taste.start() if taste else -1
    if manifest_position < 0 or taste_position < 0 or manifest_position > taste_position:
        failures.append(f"{name}: branch manifest is not built before synthesis")

assert not failures, "invalid Product Pulse fan-in coverage:\n" + "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 3: Run the contract and verify RED**

Run:

```bash
bats plugins/product-pulse/tests/harness-boundary.bats
```

Expected: FAIL for all three skills because they do not yet build or pass a complete
manifest and do not publish honest coverage.

- [ ] **Step 4: Add the same minimal manifest rule at each existing fan-in**

Immediately after consuming the last research/adjudication result that can feed taste
synthesis, add one of these exact `### Branch Manifest` paragraphs.

Daily:

```markdown
### Branch Manifest

Build the Branch Manifest before synthesis with one row for every configured domain.
Record branch identity, exact Harness `status`, evidence outcome, blockers, and elapsed
when available (`unavailable` otherwise). Only accepted/proven branches whose
verification seam Product Pulse reproduced may contribute content. Keep every other
expected branch in the manifest and exclude its claims.
```

Weekly:

```markdown
### Branch Manifest

Build the Branch Manifest before synthesis with one row for the five analyst roles plus
every required adjudication. Record branch identity, exact Harness `status`, evidence
outcome, blockers, and elapsed when available (`unavailable` otherwise). Only
accepted/proven branches whose verification seam Product Pulse reproduced may
contribute content. Keep every other expected branch in the manifest and exclude its
claims.
```

Deep dive:

```markdown
### Branch Manifest

Build the Branch Manifest before synthesis with one row for every scheduled resource,
concept bundle, and adjudication. Record branch identity, exact Harness `status`,
evidence outcome, blockers, and elapsed when available (`unavailable` otherwise). Only
accepted/proven branches whose verification seam Product Pulse reproduced may
contribute content. Keep every other expected branch in the manifest and exclude its
claims.
```

Do not create a shared reference; the three short paragraphs are cheaper than a fourth
runtime file and three new routing instructions.

- [ ] **Step 5: Pass the complete manifest into each existing taste request**

Add `complete branch manifest` to each taste request's `context.state`. Add one synthesis
constraint with this behavior:

```markdown
Report coverage as expected, accepted/proven, failed, blocked, abandoned, and unproven.
Count an accepted/unproven result as unproven, not accepted. Mark degraded coverage
whenever accepted/proven is fewer than expected. Never describe a failed, blocked,
abandoned, unproven, or missing branch as scanned, researched, or covered.
```

Also extend each synthesis verification seam so it checks the manifest totals and the
degraded-coverage disclosure.

- [ ] **Step 6: Add compact coverage to existing outputs without editing templates**

- Daily: replace `Domains scanned` with `Research Coverage: {accepted}/{expected}
  accepted/proven; {failed} failed; {blocked} blocked; {abandoned} abandoned;
  {unproven} unproven` in the report and summary.
- Weekly: require the same `Research Coverage` line under the title in both the strategy
  brief and recommendations, and add it to the Phase 6 summary.
- Deep dive: add `### Research Coverage` before `### Resource Summary` in chat and the
  identical saved report body; show counts plus the failed/blocked branch identities.

Append `— degraded coverage` whenever accepted is fewer than expected. Do not modify
`strategy-brief-template.md` or `report-template.md`; the skill's output instruction is
the single scoped override.

- [ ] **Step 7: Run targeted and full structural verification**

Run:

```bash
bats plugins/product-pulse/tests/harness-boundary.bats
plugins/product-pulse/tests/run-tests.sh
plugins/harness/tests/run-tests.sh
```

Expected: every command passes. Harness remains unchanged.

- [ ] **Step 8: Rerun the exact fresh-context pressure scenario for GREEN**

Use the Step 1 prompt unchanged. Expected:

- Daily says `1/3 accepted/proven` and degraded; failed and blocked domains remain named.
- Weekly says `3/5 accepted/proven` and degraded; the accepted/unproven role is counted
  as unproven and excluded.
- Deep dive says `1/3 accepted/proven` and degraded; the failed concept and blocked
  adjudication remain named.
- Every taste state contains all expected branch identities and no unsuccessful branch
  contributes a claim.

- [ ] **Step 9: Commit the complete research-coverage slice**

```bash
git add plugins/product-pulse/tests/harness-boundary.bats \
  plugins/product-pulse/skills/daily-research/SKILL.md \
  plugins/product-pulse/skills/weekly-strategist/SKILL.md \
  plugins/product-pulse/skills/deep-dive/SKILL.md
git commit -m "fix(product-pulse): expose degraded research coverage"
```

---

## Completion Check

- [ ] Confirm `git diff --stat` names only the four approved Product Pulse files.
- [ ] Confirm no Harness, PM, template, or Shelby file changed.
- [ ] Paste the exact Product Pulse and Harness suite summaries into the handoff.
- [ ] Report the fresh-context pressure result separately from structural Bats results.
