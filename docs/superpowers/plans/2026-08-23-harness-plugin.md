# Harness Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Machine with a provider-neutral Harness plugin, move universal routing/execution/verification out of PM and Product Pulse, migrate the private agents configuration, and prove the new behavior against the old behavior with Anthropic's official skill-evaluation workflow.

**Architecture:** Harness is the control plane: it owns personal setup and sync, semantic route resolution, bounded execution, computer use, handoffs, and evidence. PM and Product Pulse remain workflow consumers that construct a Harness Request and consume a Harness Result; Shelby is an optional state provider whose absence never changes authority or blocks otherwise-correct work.

**Tech Stack:** Claude Code plugins and skills (Markdown/YAML/JSON), POSIX shell, Bats, Python 3 standard library for structural checks, Anthropic `skill-creator` eval scripts, Git/GitHub CLI.

**Spec:** docs/superpowers/specs/2026-08-23-harness-plugin-design.md

## Global Constraints

- Remove `machine` completely. Do not add aliases, redirects, compatibility skills, or dual-install instructions.
- Subsume and delete `studio-baseline/`; Harness is the sole source of universal rules, templates, setup, and rubric guidance.
- Keep the personal rubric at `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`; never store a developer's resolved rubric in a project repository.
- Harness alone may read the rubric, interpret `via:`, choose a provider/executor, or define universal evidence behavior.
- PM retains issue/tracker, readiness, delivery-slice, PR, and development-review semantics; Product Pulse retains source, synthesis, and publication semantics.
- Shelby is optional enrichment. Never copy Shelby memory, run state, credentials, approval records, or temporary evidence into Git.
- Preserve explicit working-directory, allowed-path, tool, permission, and approval boundaries across every executor.
- An `accepted` result requires a delivered outcome and current independently reproduced proof; exit zero and worker claims are insufficient.
- Use no new runtime dependency. Test dependencies may use Bats and Anthropic's official `skill-creator` scripts.
- Keep changes to `skills-n-stuff` and the private `agents` repository on separate branches and in separate pull requests.
- Do not commit raw eval transcripts that contain absolute paths, prompts with private context, tokens, or environment data; commit reusable eval definitions and a redacted benchmark summary only.

---

## File Map

### `skills-n-stuff`

- `plugins/harness/`: renamed Machine plugin plus the universal Harness control plane.
- `plugins/harness/skills/{setup,sync,model-rubric,execute,review,computer-use}/SKILL.md`: user-facing operations.
- `plugins/harness/references/{harness-contract,routing,handoff,verification,context,shelby-integration}.md`: single sources of truth consumed progressively by skills and workflows.
- `plugins/harness/tests/`: renamed Machine tests plus contract, boundary, and fixture tests.
- `docs/superpowers/evals/harness/evals.json`: reusable behavioral cases in Anthropic's official schema, kept outside both plugin variants.
- `plugins/pm/`: domain-only development workflow after provider/rubric mechanics move to Harness.
- `plugins/product-pulse/`: domain-only research workflow using semantic Harness routes.
- `plugins/harness/references/house-rules.md`: universal engineering discipline migrated from Studio Baseline.
- `plugins/harness/templates/AGENTS_Baseline.md`: project instruction block migrated from Studio Baseline.
- `studio-baseline/`: deleted after its unique content and callers move into Harness.
- `.claude-plugin/marketplace.json`, root/plugin READMEs: distribution identity and installation documentation.

### private `agents` repository

- `README.md`, `claude/CLAUDE.md`, generated `codex/AGENTS.md`: resolved personal Harness instructions.
- `skills.manifest`: personal third-party skill declarations; unchanged unless sync legitimately changes it.
- `config/studio-moser/model-rubric.yml`: existing private resolved rubric, kept private and linked by Harness sync.
- `.skill-lock.json`: machine-local generated state; remains ignored and untracked.

---

### Task 1: Freeze the Old Behavior and Install the Test Prerequisite

**Files:**
- Create: `docs/superpowers/evals/harness/evals.json` (after the snapshot, before candidate edits)
- Create: `docs/superpowers/evals/harness-baseline-summary.md`
- Local only: `${TMPDIR:-/tmp}/studio-harness-eval/baseline-snapshot/`
- Local only: `${TMPDIR:-/tmp}/studio-harness-eval/baseline-runs/`

**Interfaces:**
- Consumes: current `plugins/machine`, `plugins/pm`, `plugins/product-pulse`, `studio-baseline`, and `/Users/timmoser/.agents` state.
- Produces: immutable baseline snapshot, official-schema eval cases `eval_id`, `prompt`, `expected_output`, and baseline metrics used unchanged in Task 9.

- [ ] **Step 1: Record the fixed baseline revisions and snapshot only the files under evaluation**

```bash
EVAL_ROOT="${TMPDIR:-/tmp}/studio-harness-eval"
mkdir -p "$EVAL_ROOT/baseline-snapshot" "$EVAL_ROOT/baseline-runs"
git rev-parse HEAD > "$EVAL_ROOT/baseline-snapshot/skills-n-stuff.commit"
git -C /Users/timmoser/.agents rev-parse HEAD > "$EVAL_ROOT/baseline-snapshot/agents.commit"
cp -R plugins/machine plugins/pm plugins/product-pulse studio-baseline \
  "$EVAL_ROOT/baseline-snapshot/"
cp -R /Users/timmoser/.agents/claude /Users/timmoser/.agents/codex \
  /Users/timmoser/.agents/README.md /Users/timmoser/.agents/skills.manifest \
  "$EVAL_ROOT/baseline-snapshot/agents/"
```

Expected: both revision files contain 40-character commit IDs; no rubric, credentials, `.skill-lock.json`, or Shelby data exists in the snapshot.

- [ ] **Step 2: Make Bats available without changing product dependencies**

Run: `command -v bats || brew install bats-core`

Expected: `bats --version` exits 0. If Homebrew is unavailable, run the suites in CI or another environment with Bats and record that environment; do not mark a missing runner as a pass.

- [ ] **Step 3: Run and record the old repository baseline**

```bash
plugins/machine/tests/run-tests.sh | tee "$EVAL_ROOT/baseline-runs/machine-bats.txt"
plugins/pm/tests/run-tests.sh | tee "$EVAL_ROOT/baseline-runs/pm-bats.txt"
```

Expected: record the actual pass/fail counts and failures. Existing failures become baseline facts, not candidate exemptions.

- [ ] **Step 4: Add the official behavioral eval cases**

Create `docs/superpowers/evals/harness/evals.json` with these stable IDs and observable expectations:

```json
{
  "skill_name": "harness",
  "evals": [
    {"id": 1, "eval_id": "pm-cross-vendor-implementation", "prompt": "Implement one bounded ready PM delivery slice using the configured bulk route and return proof.", "expected_output": "PM supplies development constraints; the executor receives explicit model, effort, cwd, authority, and verification seam; the parent reproduces proof."},
    {"id": 2, "eval_id": "fixed-target-independent-review", "prompt": "Independently review a fixed commit and prove the relevant checks.", "expected_output": "The fixed target and fresh context are preserved; prior proof is invalidated if the target changes; independent route approval is explicit."},
    {"id": 3, "eval_id": "product-pulse-fanout-synthesis", "prompt": "Research multiple sources using cheap fan-out and judgment-heavy synthesis, then publish the normal Product Pulse artifact.", "expected_output": "Product Pulse owns source quality and publication while requesting bulk and taste semantic routes without reading the rubric."},
    {"id": 4, "eval_id": "standalone-computer-use", "prompt": "Verify a local app behavior outside a PM workflow and return screenshot-backed proof.", "expected_output": "Harness computer-use handles capability, permissions, working directory, and proof without invoking PM."},
    {"id": 5, "eval_id": "missing-rubric", "prompt": "Execute a bounded task when the personal model rubric is absent.", "expected_output": "Harness reports setup or an explicit documented fallback; the consumer does not inspect the rubric or silently invent a route."},
    {"id": 6, "eval_id": "missing-required-executor", "prompt": "Execute a task whose requested provider CLI is unavailable and no provider change is authorized.", "expected_output": "Harness returns a typed blocked result or an explicitly permitted fallback without widening authority."},
    {"id": 7, "eval_id": "missing-shelby", "prompt": "Execute and verify a bounded task with Shelby tools unavailable.", "expected_output": "Correct execution continues from repository and temporary state; only memory and run enrichment are omitted."},
    {"id": 8, "eval_id": "non-development-execution", "prompt": "Perform a bounded non-code file transformation with verification.", "expected_output": "Harness executes and verifies the task without PM lifecycle behavior."}
  ]
}
```

- [ ] **Step 5: Run old-plugin and no-skill baselines with the official skill-creator workflow**

Use the installed official `skill-creator` at `/Users/timmoser/.claude/plugins/marketplaces/claude-plugins-official/plugins/skill-creator/skills/skill-creator/`. For every eval, launch the frozen old-plugin run and a no-skill run in the same turn, save `outputs/`, `transcript.md`, `timing.json`, and `grading.json` below `$EVAL_ROOT/baseline-runs/<eval-id>/{old,no-skill}/`, and grade with `agents/grader.md`. Do not invoke `/skill-test`.

Expected: eight old runs and eight no-skill runs have artifacts, timing, token counts when available, and graded assertions.

- [ ] **Step 6: Commit only reusable definitions and a redacted baseline summary**

```bash
git add docs/superpowers/evals/harness/evals.json docs/superpowers/evals/harness-baseline-summary.md
git commit -m "test: define harness behavioral baseline"
```

The summary must record fixed commits, runner versions, case IDs, aggregate results, and known baseline failures without raw private transcripts.

---

### Task 2: Rename Machine to Harness and Prove the Distribution Identity

**Files:**
- Rename: `plugins/machine/` → `plugins/harness/`
- Modify: `plugins/harness/.claude-plugin/plugin.json`
- Modify: `plugins/harness/README.md`
- Modify: `.claude-plugin/marketplace.json`
- Modify: root `README.md`
- Modify: all renamed files under `plugins/harness/scripts/`, `skills/`, and `tests/`
- Create: `plugins/harness/tests/distribution-boundary.bats`

**Interfaces:**
- Consumes: existing Machine sync/rubric behavior and marketplace schema.
- Produces: plugin identity `harness`, callable `harness:sync` and `harness:model-rubric`, and zero distributed `machine` paths or invocations.

- [ ] **Step 1: Rename the directory and write the failing identity test**

```bash
git mv plugins/machine plugins/harness
```

Add `plugins/harness/tests/distribution-boundary.bats`:

```bash
#!/usr/bin/env bats

setup() { REPO="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; }

@test "harness is the sole control-plane plugin" {
  [ -d "$REPO/plugins/harness" ]
  [ ! -e "$REPO/plugins/machine" ]
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
needles = ("plugins/machine", "/machine:", "machine:model-rubric", "machine:sync")
hits = []
for path in [root / ".claude-plugin/marketplace.json", root / "plugins/harness", root / "README.md"]:
    files = [path] if path.is_file() else [p for p in path.rglob("*") if p.is_file()]
    for file in files:
        text = file.read_text(errors="ignore")
        for needle in needles:
            if needle in text:
                hits.append(f"{file.relative_to(root)}: {needle}")
assert not hits, "\n".join(hits)
PY
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run the identity test and confirm the old names fail**

Run: `bats plugins/harness/tests/distribution-boundary.bats`

Expected: FAIL listing manifest, marketplace, documentation, script comments/messages, and tests that still name Machine.

- [ ] **Step 3: Update the plugin identity and every in-plugin path/invocation**

Set `plugins/harness/.claude-plugin/plugin.json` name to `harness`; replace the marketplace `machine` object with a `harness` object sourced from `./plugins/harness`; rename user invocations to `/harness:sync` and `/harness:model-rubric`; update plugin-root discovery and test fixture paths to `plugins/harness`. Preserve Git commit messages such as `machine: sync ...` only if they describe historical data; new generated messages use `harness:`.

- [ ] **Step 4: Run all renamed tests**

Run: `plugins/harness/tests/run-tests.sh`

Expected: all pre-existing Machine behaviors pass under Harness paths and names, including link planning, manifest reconciliation, portability lint, rendering, rubric path/audit, and plugin-root discovery.

- [ ] **Step 5: Commit the pure rename/identity slice**

```bash
git add -A plugins/harness plugins/machine .claude-plugin/marketplace.json README.md
git commit -m "feat: replace machine plugin with harness"
```

---

### Task 3: Define the Harness Contract, Routing, Context, Verification, and Optional Shelby Rules

**Files:**
- Create: `plugins/harness/references/harness-contract.md`
- Create: `plugins/harness/references/routing.md`
- Create: `plugins/harness/references/handoff.md`
- Create: `plugins/harness/references/verification.md`
- Create: `plugins/harness/references/context.md`
- Create: `plugins/harness/references/shelby-integration.md`
- Create: `plugins/harness/tests/reference-contracts.bats`

**Interfaces:**
- Consumes: rubric routing values in `model@effort` form and optional model-row `via` metadata.
- Produces: exact `HarnessRequest` and `HarnessResult` YAML contracts from the spec; route resolution outcome `resolved | fallback | blocked`; handoff fields used by Tasks 4–7.

- [ ] **Step 1: Write the failing contract test**

Create `plugins/harness/tests/reference-contracts.bats` with Python assertions that every required reference exists and that:

```python
request_fields = ["operation", "route", "outcome", "context", "authority", "constraints", "verification"]
result_fields = ["status", "route", "artifacts", "evidence", "telemetry", "shelby", "blockers"]
routes = ["bulk", "quick", "default", "taste", "batch", "review", "independent"]
statuses = ["accepted", "failed", "blocked", "abandoned"]
context_modes = ["fresh", "fork", "hybrid"]
```

The test must also assert: `accepted` requires `evidence.outcome: proven`; independent review defaults to `fresh` and needs explicit cost approval; missing Shelby is not blocking; missing required capability returns `fallback` only when authorized, otherwise `blocked`; secrets and unbounded logs are forbidden.

- [ ] **Step 2: Run the test and verify all six references are missing**

Run: `bats plugins/harness/tests/reference-contracts.bats`

Expected: FAIL on missing references.

- [ ] **Step 3: Write the six focused references from the spec without duplicating consumer policy**

Use the exact schemas and enum values above. `routing.md` owns rubric lookup, explicit model+effort dispatch, `via` interpretation, escalation, and typed fallback. `verification.md` owns fixed targets, direct/supporting/unproven evidence, invalidation, parent reproduction, and accepted-state gating. `shelby-integration.md` defines runtime tool discovery, canonical project resolution before reads/writes, stable brief plus targeted lookup, plan/checkpoint/run events for substantial work, and a repository/temp-only fallback.

- [ ] **Step 4: Run the focused and full Harness suites**

```bash
bats plugins/harness/tests/reference-contracts.bats
plugins/harness/tests/run-tests.sh
```

Expected: PASS.

- [ ] **Step 5: Commit the contract**

```bash
git add plugins/harness/references plugins/harness/tests/reference-contracts.bats
git commit -m "feat: define the harness contract"
```

---

### Task 4: Add Harness Setup and Provider-Neutral Execution Skills

**Files:**
- Create: `plugins/harness/skills/setup/SKILL.md`
- Create: `plugins/harness/skills/execute/SKILL.md`
- Create: `plugins/harness/skills/review/SKILL.md`
- Create: `plugins/harness/skills/computer-use/SKILL.md`
- Modify: `plugins/harness/skills/sync/SKILL.md`
- Modify: `plugins/harness/skills/model-rubric/SKILL.md`
- Move implementation knowledge from: `plugins/pm/skills/codex-{implementation,review,computer-use}/SKILL.md`
- Create: `plugins/harness/tests/skill-contracts.bats`
- Modify: `plugins/harness/tests/skill-plugin-root.bats`

**Interfaces:**
- Consumes: `HarnessRequest`, semantic route, six references from Task 3, installed runtime capabilities, optional Shelby tools.
- Produces: `HarnessResult`; `harness:setup`, `harness:execute`, `harness:review`, and `harness:computer-use`; Codex CLI remains an internal capability-gated adapter, not a public workflow name.

- [ ] **Step 1: Write failing frontmatter and behavioral contract tests**

Test that each new skill has valid `name` and `description`, references only the documents it needs, accepts a Harness Request, returns every Harness Result field, passes resolved model and effort explicitly, preserves `authority.working_directory`, and never marks `accepted` before parent verification. Test `setup` in two fixtures: with Shelby-tool names present and absent; both must finish setup, while only the former returns Shelby IDs.

- [ ] **Step 2: Run the focused test and confirm the skills are absent**

Run: `bats plugins/harness/tests/skill-contracts.bats`

Expected: FAIL on missing `setup`, `execute`, `review`, and `computer-use` skills.

- [ ] **Step 3: Implement `harness:setup` as orchestration, not duplicate setup logic**

Its ordered contract is: discover or create the personal agents-repo relationship using the existing sync mechanics; reconcile portable links; discover runtime capabilities with `command -v`; create/refresh the rubric through `harness:model-rubric`; detect optional Shelby tools; print what is version-controlled versus local-only; return a setup Harness Result. It delegates mechanics to existing scripts and skills rather than copying them.

- [ ] **Step 4: Implement `harness:execute` with provider-neutral input and an internal Codex adapter**

Resolve the semantic route inside Harness, validate authority before dispatch, select `fresh` by default for delegated implementation, translate `via: codex` into the existing guarded CLI command, and otherwise use the native runtime. External CLI prompts must include the bounded outcome, cwd, allowed paths, constraints, verification seam, and required return schema. Never interpolate secrets or broaden sandbox/approval scope.

- [ ] **Step 5: Implement `harness:review` and `harness:computer-use`**

Review requires an immutable target, uses `review` or approved `independent`, treats the worker report as a claim, and reproduces relevant checks. Computer use verifies the requested runtime capability and preserves its confirmation policy; if unavailable and no equivalent is authorized, return `blocked`.

- [ ] **Step 6: Remove the three PM vendor skills after their behavior exists in Harness**

```bash
git rm -r plugins/pm/skills/codex-implementation \
  plugins/pm/skills/codex-review plugins/pm/skills/codex-computer-use
```

Expected: no public `pm:codex-*` skill remains; Codex-specific invocation text exists only inside Harness.

- [ ] **Step 7: Run Harness tests and a temporary-fixture sync**

```bash
plugins/harness/tests/run-tests.sh
fixture="$(mktemp -d "${TMPDIR:-/tmp}/harness-agents.XXXXXX")"
git init -q "$fixture"
plugins/harness/scripts/link-plan.sh "$fixture"
plugins/harness/scripts/portability-lint.sh "$fixture"
```

Expected: suites pass; fixture planning/linting does not write outside the fixture or expose secrets.

- [ ] **Step 8: Commit the executable Harness surface**

```bash
git add -A plugins/harness plugins/pm/skills
git commit -m "feat: add provider-neutral harness execution"
```

---

### Task 5: Make PM a Pure Harness Consumer

**Files:**
- Delete: `plugins/pm/references/model-orchestration.md`
- Modify: `plugins/pm/skills/{dev-task,sprint-dev,ingest,setup}/SKILL.md`
- Modify: `plugins/pm/agents/code-reviewer.md`
- Modify: `plugins/pm/references/{triage-scorecard,work-readiness,review-proof}.md`
- Modify: `plugins/pm/README.md`
- Modify: `plugins/pm/tests/{skill-contracts,skill-frontmatter}.bats`
- Create: `plugins/pm/tests/harness-boundary.bats`

**Interfaces:**
- Consumes: `harness:execute` and `harness:review` with the Task 3 request/result schema.
- Produces: unchanged PM lifecycle with domain constraints embedded in `context`/`constraints`, no direct rubric/provider/executor logic.

- [ ] **Step 1: Add the failing ownership-boundary test**

The test scans `plugins/pm` excluding tests and asserts none of these appear:

```python
forbidden = [
    "model-rubric.yml", "references/model-orchestration.md", "via:",
    "codex-implementation", "codex-review", "codex-computer-use",
    "command -v codex", "routing.bulk", "routing.review", "model@effort"
]
```

It separately asserts that `dev-task`, `sprint-dev`, `ingest`, `triage-scorecard`, and `code-reviewer` name a semantic Harness operation and preserve PM-specific readiness, blocker, testing-seam, spec-fidelity, and blast-radius language.

- [ ] **Step 2: Run the boundary test and confirm current ownership violations**

Run: `bats plugins/pm/tests/harness-boundary.bats`

Expected: FAIL listing all direct rubric, routing, `via`, and `pm:codex-*` references.

- [ ] **Step 3: Replace PM dispatch instructions with complete Harness Requests**

Use `bulk` for clear-spec/mechanical work and scorecard evaluation, `quick` only for latency-sensitive steps, `taste` for user-facing design/copy/API work, `review` for ordinary fixed-target review, and approved `independent` for adversarial fresh-context review. PM supplies delivery-slice outcomes, blockers, files, testing seams, fixed commits, spec-fidelity criteria, and blast-radius constraints; Harness resolves execution.

- [ ] **Step 4: Keep PM setup limited to the workflow layer**

`pm:setup` checks whether Harness is configured and points to `/harness:setup` when absent. It does not inspect/create the rubric, install executors, or restate Harness mechanics. It continues configuring the issue-tracker backend and stamping the shared baseline block.

- [ ] **Step 5: Update readiness and review references**

`work-readiness.md` defines whether a development slice is assignable; `review-proof.md` defines PM's Quality, Spec Fidelity, and Blast Radius axes. Both link to Harness for fixed-target, authority, execution, and evidence semantics.

- [ ] **Step 6: Run PM and Harness tests**

```bash
plugins/pm/tests/run-tests.sh
plugins/harness/tests/run-tests.sh
```

Expected: PASS; the boundary test finds no forbidden ownership.

- [ ] **Step 7: Commit the PM migration**

```bash
git add -A plugins/pm
git commit -m "refactor: layer pm workflows on harness"
```

---

### Task 6: Make Product Pulse a Pure Harness Consumer

**Files:**
- Modify: `plugins/product-pulse/skills/{daily-research,weekly-strategist,deep-dive,setup}/SKILL.md`
- Modify: `plugins/product-pulse/agents/{market-scout,competitor-tracker,audience-analyst,growth-analyst,product-scout}.md`
- Modify: `plugins/product-pulse/README.md`
- Create: `plugins/product-pulse/tests/run-tests.sh`
- Create: `plugins/product-pulse/tests/harness-boundary.bats`
- Create: `plugins/product-pulse/tests/skill-frontmatter.bats`

**Interfaces:**
- Consumes: Harness semantic execution/review routes.
- Produces: unchanged reports and publication flow; Product Pulse supplies research questions, source requirements, credibility checks, and report paths.

- [ ] **Step 1: Write the failing Product Pulse boundary test**

Scan the plugin for concrete model names, `model@effort`, rubric paths, `via:`, direct provider CLI instructions, and phrases that tell consumers to pick cheap/strong models. Assert daily scanning/extraction requests `bulk`, judgment-heavy synthesis requests `taste`, adjudication requests `review`, and setup points to `/harness:setup` without reproducing it.

- [ ] **Step 2: Run the new suite and verify the current direct model language fails**

Run: `plugins/product-pulse/tests/run-tests.sh`

Expected: FAIL with the exact direct-routing locations.

- [ ] **Step 3: Rewrite each workflow as a domain packet plus semantic route**

Daily research uses `bulk` for independent source scans and `taste` for final synthesis. Weekly Strategist uses `bulk` for five analyst packets and `taste` for strategy synthesis; contradictory/high-impact claims may use `review`. Deep Dive uses `bulk` for extraction/comparison and `taste` for recommendations. Product Pulse continues enforcing source credibility, citations, project comparison, report path, and publication checks.

- [ ] **Step 4: Run Product Pulse, PM, and Harness suites**

```bash
plugins/product-pulse/tests/run-tests.sh
plugins/pm/tests/run-tests.sh
plugins/harness/tests/run-tests.sh
```

Expected: PASS.

- [ ] **Step 5: Commit the Product Pulse migration**

```bash
git add plugins/product-pulse
git commit -m "refactor: layer product pulse on harness"
```

---

### Task 7: Subsume Studio Baseline and Remove the Parallel Source of Truth

**Files:**
- Move: `studio-baseline/House_Rules.md` → `plugins/harness/references/house-rules.md`
- Move: `studio-baseline/AGENTS_Baseline.md` → `plugins/harness/templates/AGENTS_Baseline.md`
- Delete after migration: `studio-baseline/{Machine_Setup,Rubric_Setup,README}.md`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `plugins/{harness,pm,product-pulse}/README.md`
- Create: `plugins/harness/tests/studio-baseline.bats`

**Interfaces:**
- Consumes: Harness Contract and setup surface.
- Produces: one Harness-owned universal rules reference and baseline template; no `studio-baseline/` remains; marketplace contains Harness and no Machine.

- [ ] **Step 1: Write a failing baseline test**

Assert `plugins/harness/references/house-rules.md` and `plugins/harness/templates/AGENTS_Baseline.md` exist, `studio-baseline/` does not, the template names Harness Request/Result responsibilities without embedding route values or provider mechanics, all setup/rubric callers point into Harness, and the marketplace contains exactly one `harness` entry and zero `machine` entries.

- [ ] **Step 2: Run the test and confirm legacy setup references fail**

Run: `bats plugins/harness/tests/studio-baseline.bats`

Expected: FAIL because `studio-baseline/` still exists and callers still point to its Machine/Rubric setup documents.

- [ ] **Step 3: Move the universal rules and template, then fold setup prose into the owning skills**

```bash
mkdir -p plugins/harness/templates
git mv studio-baseline/House_Rules.md plugins/harness/references/house-rules.md
git mv studio-baseline/AGENTS_Baseline.md plugins/harness/templates/AGENTS_Baseline.md
```

Keep the existing safe sync mechanics and portability boundary by moving their unique instructions into `harness:setup` and `harness:sync`. Move rubric interview/refresh guidance into `harness:model-rubric` and its focused reference. Rewrite the template's model-routing paragraph as the semantic contract: consumers select route, Harness resolves model/executor and propagates authority, workers return evidence, parent agents reproduce proof. Update `pm:setup` and Harness rendering/stamping scripts to read `plugins/harness/templates/AGENTS_Baseline.md`.

- [ ] **Step 4: Delete Studio Baseline and prove every caller has moved**

```bash
git rm -r studio-baseline
rg -n --hidden --glob '!.git' \
  'studio-baseline|Machine_Setup\.md|Rubric_Setup\.md' \
  README.md .claude-plugin plugins
```

Expected: `rg` exits 1 with no matches. Harness-owned paths use `plugins/harness/references/house-rules.md` and `plugins/harness/templates/AGENTS_Baseline.md`.

- [ ] **Step 5: Run every public repository suite and JSON validation**

```bash
python3 -m json.tool .claude-plugin/marketplace.json >/dev/null
python3 -m json.tool plugins/harness/.claude-plugin/plugin.json >/dev/null
python3 -m json.tool plugins/pm/.claude-plugin/plugin.json >/dev/null
python3 -m json.tool plugins/product-pulse/.claude-plugin/plugin.json >/dev/null
plugins/harness/tests/run-tests.sh
plugins/pm/tests/run-tests.sh
plugins/product-pulse/tests/run-tests.sh
```

Expected: PASS.

- [ ] **Step 6: Commit public distribution and baseline migration**

```bash
git add -A .
git commit -m "refactor: subsume studio baseline into harness"
```

---

### Task 8: Migrate the Private Agents Repository as a Separate Change

**Files:**
- Modify: `/Users/timmoser/.agents/README.md`
- Modify: `/Users/timmoser/.agents/claude/CLAUDE.md`
- Regenerate: `/Users/timmoser/.agents/codex/AGENTS.md`
- Inspect only unless sync changes it: `/Users/timmoser/.agents/skills.manifest`
- Preserve: `/Users/timmoser/.agents/config/studio-moser/model-rubric.yml`
- Preserve ignored/untracked: `/Users/timmoser/.agents/.skill-lock.json`

**Interfaces:**
- Consumes: public Harness plugin from Tasks 2–7 and `render-codex-agents.sh`.
- Produces: personal resolved Harness setup in its own Git branch/PR; no private state enters `skills-n-stuff`.

- [ ] **Step 1: Create an isolated branch without discarding existing private changes**

```bash
git -C /Users/timmoser/.agents status --short
git -C /Users/timmoser/.agents switch -c feature/harness-contract
```

Expected: pre-existing changes are identified and preserved; if that branch exists, use its existing worktree rather than overwriting it.

- [ ] **Step 2: Write a local failing boundary check**

```bash
python3 - <<'PY'
from pathlib import Path
root = Path('/Users/timmoser/.agents')
files = [root/'README.md', root/'claude/CLAUDE.md', root/'codex/AGENTS.md', root/'skills.manifest']
hits = [(str(p), n) for p in files for n in ('/machine:', 'machine:sync', 'machine:model-rubric') if n in p.read_text()]
assert not hits, hits
assert not (root/'.skill-lock.json').is_file() or '.skill-lock.json' in (root/'.gitignore').read_text()
PY
```

Expected before migration: FAIL on legacy Machine text if present; `.skill-lock.json` remains ignored.

- [ ] **Step 3: Run Harness sync against the agents repository and approve only expected portable changes**

Invoke `/harness:sync` from the public plugin checkout. Accept changes to shared instructions, manifests, and links; reject credentials, absolute host-specific paths, eval artifacts, approval records, or Shelby state. Do not replace the existing private rubric with the public seed.

- [ ] **Step 4: Regenerate Codex instructions from the canonical Claude sources**

Run the relocated `plugins/harness/scripts/render-codex-agents.sh` with the same arguments documented by `harness:sync`, targeting `/Users/timmoser/.agents/codex/AGENTS.md`.

Expected: generated header names `harness:sync`; House Style and personal Claude instructions remain represented once.

- [ ] **Step 5: Verify the private repository boundary and diff**

```bash
git -C /Users/timmoser/.agents diff --check
git -C /Users/timmoser/.agents status --short
git -C /Users/timmoser/.agents ls-files .skill-lock.json
```

Expected: `diff --check` passes; `.skill-lock.json` prints nothing; the rubric remains tracked only in this private repository; no unrelated files changed.

- [ ] **Step 6: Commit and push the separate private change**

```bash
git -C /Users/timmoser/.agents add README.md claude/CLAUDE.md codex/AGENTS.md skills.manifest
git -C /Users/timmoser/.agents commit -m "feat: adopt the harness plugin"
git -C /Users/timmoser/.agents push -u origin feature/harness-contract
```

Expected: one agents-repo commit and branch; do not include `.skill-lock.json` or transient evidence.

---

### Task 9: Run the Official Old/New Evaluation and Fix Behavioral Regressions

**Files:**
- Modify as failures require: `plugins/harness/skills/**`, `plugins/harness/references/**`, PM/Product Pulse consumer skills
- Modify: `docs/superpowers/evals/harness-baseline-summary.md` into a redacted final comparison
- Local only: `${TMPDIR:-/tmp}/studio-harness-eval/candidate-runs/`
- Local only: `${TMPDIR:-/tmp}/studio-harness-eval/benchmark/`

**Interfaces:**
- Consumes: identical Task 1 eval prompts/assertions, frozen baseline runs, candidate plugin.
- Produces: grader results, benchmark aggregate, official viewer, blind comparator results, analyzer report, and a redacted committed conclusion.

- [ ] **Step 1: Launch paired old/new runs for every eval in the same turn**

For each case in `docs/superpowers/evals/harness/evals.json`, run the frozen old snapshot and current candidate concurrently under comparable environment state. Save candidate outputs, transcript, timing, token/tool-call data, and grading beneath `$EVAL_ROOT/candidate-runs/<eval-id>/`. Use `agents/grader.md`; do not grade by phrase matching.

Expected: all eight pairs have complete artifacts and observable assertions for semantic ownership, explicit dispatch, authority, proof reproduction, fixed-target invalidation, Shelby fallback, capability blocker/fallback, and preserved domain outputs.

- [ ] **Step 2: Aggregate and inspect variance with official scripts**

From the official skill-creator directory, run its documented `scripts.aggregate_benchmark` command against the paired workspace, then use `agents/analyzer.md` to flag high variance and nondiscriminating assertions.

Expected: aggregate includes pass rate, time, tokens, tool calls, and variance for old and new; assertions passing equally without testing the new boundary are revised and rerun.

- [ ] **Step 3: Generate the official eval viewer and perform human artifact review**

Run `eval-viewer/generate_review.py` with the paired workspace and open the generated viewer. Inspect each output for actual workflow quality, missing proof, authority drift, or private-data leakage.

Expected: every case has a recorded human disposition; a grader pass cannot override visible failure.

- [ ] **Step 4: Blind old/new labels and run comparator plus post-hoc analyzer**

Use `agents/comparator.md` on blinded outputs, then unblind only for `agents/analyzer.md` causal analysis.

Expected: candidate retains or improves success and demonstrates the ownership split without unexplained material time/token regression. Any blocker returns to its owning task with a new failing regression assertion before the instruction is changed.

- [ ] **Step 5: Evaluate trigger descriptions only after behavior passes**

Create 20 realistic should-trigger and near-miss should-not-trigger queries per new skill family, review them manually, then run the official description optimizer with a 60/40 train/test split, three repetitions, and at most five iterations. Distinguish Harness setup/execution from PM lifecycle and ordinary tasks needing neither.

Expected: held-out trigger accuracy improves or stays equal without broad false positives; apply only description changes supported by held-out results.

- [ ] **Step 6: Record the redacted comparison and commit any evidence-backed fixes**

```bash
git add plugins/harness plugins/pm plugins/product-pulse docs/superpowers/evals/harness-baseline-summary.md
git commit -m "test: validate harness behavior against baseline"
```

Expected: committed summary contains aggregate numbers and conclusions but no raw private transcripts, secrets, absolute personal paths, or mutable Shelby state.

---

### Task 10: Final Verification, Independent Review, and Two Pull Requests

**Files:**
- Inspect: complete `skills-n-stuff` branch diff against `origin/main`
- Inspect: complete private `agents` branch diff against its base
- Modify only for verified blockers found by final review

**Interfaces:**
- Consumes: fixed final commits from both repositories.
- Produces: green repository gates, independent fixed-target review, one public PR and one private agents PR.

- [ ] **Step 1: Prove the public repository contains no legacy or leaked ownership**

```bash
rg -n --hidden --glob '!.git' 'plugins/machine|/machine:|machine:model-rubric|machine:sync' README.md .claude-plugin plugins
test ! -e studio-baseline
rg -n --hidden --glob '!.git' 'model-rubric\.yml|model@effort|via:|codex-(implementation|review|computer-use)' plugins/pm plugins/product-pulse
```

Expected: both `rg` commands exit 1 with no matches and `test` exits 0. Test fixtures may express forbidden strings only by assembling fragments so the scan remains meaningful.

- [ ] **Step 2: Run the full stable verification surface**

```bash
python3 -m json.tool .claude-plugin/marketplace.json >/dev/null
plugins/harness/tests/run-tests.sh
plugins/pm/tests/run-tests.sh
plugins/product-pulse/tests/run-tests.sh
git diff --check origin/main...HEAD
```

Expected: every command exits 0.

- [ ] **Step 3: Fix the public target and obtain independent review**

Commit any remaining verified changes, record `PUBLIC_TARGET="$(git rev-parse HEAD)"`, and dispatch `harness:review` with route `independent`, context mode `fresh`, fixed target `$PUBLIC_TARGET`, and the spec completion criteria. The reviewer must reproduce the full stable suites and inspect security/authority boundaries.

Expected: no unresolved BLOCKER. If the target changes, discard the old proof, rerun verification, and review the new commit.

- [ ] **Step 4: Verify and independently review the private agents target**

Run the Task 8 boundary check, `git diff --check`, and Harness sync dry-run/read-only planning against the committed agents branch. Fix the target and review it separately for private-state leakage and correct Harness installation.

Expected: no unresolved blocker; Machine is absent; personal rubric remains private; `.skill-lock.json` remains ignored.

- [ ] **Step 5: Push and open two pull requests**

```bash
git push -u origin feature/harness-contract
gh pr create --base main --head feature/harness-contract \
  --title "Create the Harness control-plane plugin" \
  --body-file docs/superpowers/specs/2026-08-23-harness-plugin-design.md

git -C /Users/timmoser/.agents push -u origin feature/harness-contract
gh pr create --repo Studio-Moser/agents --base main --head feature/harness-contract \
  --title "Adopt the Harness plugin" \
  --body "Migrates the private resolved agent configuration from Machine to Harness after the public control-plane change."
```

Expected: two distinct PR URLs, each scoped to one repository. If the actual agents remote is not `Studio-Moser/agents`, derive the repository with `gh repo view --json nameWithOwner` and use that exact value.

- [ ] **Step 6: Report completion with fixed evidence**

Report both PRs, fixed commit IDs, exact passing suite counts, eval old/new success/time/token aggregates, independent-review result, and any explicitly blocked/abandoned requirement. Do not describe the migration as complete until both repositories and the official evaluation satisfy the spec's eight completion criteria.
