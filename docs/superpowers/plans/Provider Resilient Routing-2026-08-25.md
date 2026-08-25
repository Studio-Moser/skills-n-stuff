# Provider-Resilient Harness Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every Harness semantic route automatically fail over to ordered, quality-compatible providers while suppressing repeated attempts against temporarily unavailable provider/executor endpoints.

**Architecture:** Keep scalar primary routes and add ordered `fallbacks.<route>` chains. A deterministic Python resolver reads the rubric through the already-required `yq`, selects a reachable candidate, and owns a locked machine-local circuit breaker; Harness retries only typed availability failures with unchanged authority and verification.

**Tech Stack:** Python 3 standard library, `yq`, Bash/Bats, Markdown/YAML Harness contracts, Claude Code plugin manifests.

**Spec:** `docs/superpowers/specs/Provider Resilient Routing Design-2026-08-24.md`

## Global Constraints

- Only an explicit ordered `fallbacks.<route>` chain authorizes automatic fallback.
- Fallback reasons are limited to `quota`, `authentication`, `rate_limit`, `provider_unavailable`, and preflight `missing_executor`.
- Task, output, verification, authority, and approval failures never change providers.
- Providers cannot repeat in one route chain.
- `taste` preserves `taste_min`; `independent` excludes every authoring provider.
- Every attempt preserves the original request's complete authority and verification seam.
- Health state is local at `${XDG_STATE_HOME:-$HOME/.local/state}/studio-moser/harness/provider-health.json`, never synced, and contains no raw error or secret-bearing value.
- Single-provider rubrics remain valid without fallbacks.
- Legacy `routing.fallback` never grants automatic authorization.
- Do not add an executor adapter without an enforceable authority boundary.
- Use RED/GREEN TDD and stage only each task's named files.

## File Structure

- Create `plugins/harness/scripts/resolve-route.py` for validation, selection, cooldowns, probe claims, and JSON results.
- Create `plugins/harness/tests/resolve-route.bats` for rubric, clock, state, and concurrency fixtures.
- Modify Harness references, execution/setup/model-rubric skills, structural tests, and `setup-result.py` for the new contract.
- Modify Harness README and its two version fields for release `0.8.0`.

---

### Task 1: Deterministic Primary and Fallback Resolution

**Files:**
- Create: `plugins/harness/scripts/resolve-route.py`
- Create: `plugins/harness/tests/resolve-route.bats`

**Interfaces:**
- Consumes: rubric YAML, route, native provider, callable executors, authoring-provider exclusions, attempted candidates, state path, and clock.
- Produces: JSON operations `validate`, `select`, `record-failure`, and `record-success`; later tasks consume `status`, `resolution`, `candidate`, `model`, `effort`, `provider`, `executor`, `reason`, `skipped`, and `blockers`.

- [ ] **Step 1: Write failing selection tests**

Create a fixture with Claude and Codex rows, scalar primaries, `taste_min: 9`, and `fallbacks.taste: [gpt-5.6-sol@high]`. Add these representative assertions plus separate cases for all listed boundaries:

```bash
@test "matching provider uses native even when the row declares via" {
  run "$SCRIPT" select --rubric "$RUBRIC" --state "$STATE" \
    --route default --native-provider openai --executors "" \
    --now 2026-08-25T12:00:00Z
  [ "$status" -eq 0 ]
  RESULT_JSON="$output" python3 - <<'PY'
import json, os
r = json.loads(os.environ["RESULT_JSON"])
assert (r["status"], r["resolution"]) == ("resolved", "primary")
assert (r["candidate"], r["executor"]) == ("gpt-5.6-sol@high", "native")
PY
}

@test "native mismatch selects the ordered cross-provider fallback" {
  run "$SCRIPT" select --rubric "$RUBRIC" --state "$STATE" \
    --route taste --native-provider openai --executors codex \
    --now 2026-08-25T12:00:00Z
  [ "$status" -eq 0 ]
  RESULT_JSON="$output" python3 - <<'PY'
import json, os
r = json.loads(os.environ["RESULT_JSON"])
assert r["status"] == "fallback"
assert (r["candidate"], r["provider"], r["executor"]) == (
    "gpt-5.6-sol@high", "openai", "native"
)
assert r["reason"] == "missing_executor"
PY
}
```

Additional executable tests must prove: fallback below `taste_min` blocks; `independent` rejects an authoring provider; duplicate providers fail `validate`; exhausted/malformed/unresolved chains block; `routing.fallback` alone never authorizes; and a single-provider rubric without `fallbacks` validates.

- [ ] **Step 2: Run tests to verify RED**

Run: `bats plugins/harness/tests/resolve-route.bats`

Expected: FAIL because `resolve-route.py` does not exist.

- [ ] **Step 3: Implement YAML loading and candidate selection**

Use `yq -o=json` plus Python's standard library. Preserve these interfaces:

```python
AVAILABILITY_REASONS = {
    "quota", "authentication", "rate_limit",
    "provider_unavailable", "missing_executor",
}
EXIT_BLOCKED = 4

@dataclass(frozen=True)
class Candidate:
    ref: str
    model: str
    effort: str
    provider: str
    executor: str
    taste: int | None

def split_ref(value: str) -> tuple[str, str]:
    model, separator, effort = value.rpartition("@")
    if not separator or not model or not effort:
        raise ValueError(f"invalid model-effort reference: {value}")
    return model, effort

def resolve_executor(row: dict, native_provider: str,
                     executors: set[str]) -> tuple[str | None, str | None]:
    if row["provider"] == native_provider:
        return "native", None
    via = row.get("via")
    return (via, None) if via in executors else (None, "missing_executor")
```

Implement exact `(name, effort)` row validation, unique-provider chains, candidate order `[routing[route], *fallbacks.get(route, [])]`, attempted-candidate exclusion, taste/independence checks, and compact JSON. Exit `0` for resolved/fallback, `4` for blocked, and `2` for argument errors. Do not print raw `yq` stderr.

- [ ] **Step 4: Verify GREEN and regressions**

```bash
chmod +x plugins/harness/scripts/resolve-route.py
bats plugins/harness/tests/resolve-route.bats
bats plugins/harness/tests/rubric-path.bats plugins/harness/tests/model-rubric-contracts.bats
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add plugins/harness/scripts/resolve-route.py plugins/harness/tests/resolve-route.bats
git commit -m "feat(harness): resolve per-route provider fallbacks"
```

### Task 2: Persistent Availability Circuit Breaker

**Files:**
- Modify: `plugins/harness/scripts/resolve-route.py`
- Modify: `plugins/harness/tests/resolve-route.bats`

**Interfaces:**
- Consumes: Task 1's CLI, `Candidate`, and route selection.
- Produces: state keyed by `provider|executor`; adaptive `record-failure`; clearing `record-success`; half-open claims consumed by `select`.

- [ ] **Step 1: Add failing clock and concurrency tests**

Add executable tests for these exact observations:

```bash
# quota defaults to 24 hours
run "$SCRIPT" record-failure --state "$STATE" \
  --provider anthropic --executor native --reason quota \
  --now 2026-08-25T12:00:00Z
[ "$status" -eq 0 ]
[[ "$output" == *'"unavailable_until":"2026-08-26T12:00:00Z"'* ]]

# immediate selection skips the circuit and preserves its reason
run "$SCRIPT" select --rubric "$RUBRIC" --state "$STATE" \
  --route taste --native-provider anthropic --executors codex \
  --now 2026-08-25T12:01:00Z
[ "$status" -eq 0 ]
[[ "$output" == *'"resolution":"fallback"'* ]]
[[ "$output" == *'"reason":"quota"'* ]]

# success closes the exact endpoint
run "$SCRIPT" record-success --state "$STATE" \
  --provider anthropic --executor native --now 2026-08-26T12:00:01Z
[ "$status" -eq 0 ]
STATE_PATH="$STATE" python3 - <<'PY'
import json, os
state = json.load(open(os.environ["STATE_PATH"]))
assert "anthropic|native" not in state["circuits"]
PY
```

Add separate tests for: supplied quota reset timestamp; authentication at 24 hours; rate-limit/outage delays of 15 minutes, 1 hour, 6 hours, and 24 hours; cap at 24 hours; exactly one of two concurrent selectors claiming an expired probe; stale 15-minute probe lease reclamation; state mode `0600`; and malformed state blocking without overwrite.

- [ ] **Step 2: Run cooldown tests to verify RED**

Run: `bats --filter 'quota|authentication|outage|probe|malformed state' plugins/harness/tests/resolve-route.bats`

Expected: FAIL because circuit operations do not exist.

- [ ] **Step 3: Implement locked atomic state and schedules**

Add:

```python
OUTAGE_DELAYS = (900, 3600, 21600, 86400)
DAY_SECONDS = 86400
PROBE_LEASE_SECONDS = 900

def circuit_key(provider: str, executor: str) -> str:
    return f"{provider}|{executor}"

def cooldown_seconds(reason: str, failure_count: int) -> int:
    if reason in {"quota", "authentication"}:
        return DAY_SECONDS
    if reason in {"rate_limit", "provider_unavailable"}:
        index = min(max(failure_count, 1) - 1, len(OUTAGE_DELAYS) - 1)
        return OUTAGE_DELAYS[index]
    raise ValueError(f"not a timed availability failure: {reason}")
```

Use `fcntl.flock` on a sibling lock file. Write through `tempfile.mkstemp`, `os.fchmod(fd, 0o600)`, and `os.replace`. Missing state means `{"version":1,"circuits":{}}`; malformed state is never replaced. Reset the counter when category changes. A future `--retry-at` wins for quota. `select` claims expired circuits atomically and sets `probe: true`; only a stale lease may be reclaimed.

When `--state` is omitted, resolve the path without writing until state is needed:

```python
def default_state_path() -> Path:
    root = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    return root / "studio-moser/harness/provider-health.json"
```

- [ ] **Step 4: Verify GREEN and state safety**

```bash
bats plugins/harness/tests/resolve-route.bats
git diff --check
```

Expected: all resolver tests pass and formatting is clean.

- [ ] **Step 5: Commit**

```bash
git add plugins/harness/scripts/resolve-route.py plugins/harness/tests/resolve-route.bats
git commit -m "feat(harness): persist provider cooldown circuits"
```

### Task 3: Contract and Execution Integration

**Files:**
- Modify: `plugins/harness/references/routing.md`
- Modify: `plugins/harness/references/harness-contract.md`
- Modify: `plugins/harness/skills/execute/SKILL.md`
- Modify: `plugins/harness/skills/review/SKILL.md`
- Modify: `plugins/harness/skills/computer-use/SKILL.md`
- Modify: `plugins/harness/scripts/setup-result.py`
- Modify: `plugins/harness/tests/reference-contracts.bats`
- Modify: `plugins/harness/tests/skill-contracts.bats`
- Modify: `plugins/harness/tests/setup-result.bats`

**Interfaces:**
- Consumes: Task 2's resolver and typed reasons.
- Produces: every Harness operation uses one bounded selection loop and returns `route.resolution`, `route.attempted`, and `route.fallback_reason`.

- [ ] **Step 1: Change structural tests first**

Make `reference-contracts.bats` expect these entries after `route.executor`:

```python
("route.resolution", "primary | fallback"),
("route.attempted", "ordered model-effort dispatches"),
("route.fallback_reason", "typed availability reason or empty"),
```

Replace old generic-fallback assertions with exact clauses for ordered standing authorization, availability-only switching, native-provider preference, preserved authority, and circuit cooldowns. Require all three execution skills to name `resolve-route.py`, `record-failure`, `record-success`, `--attempted`, and all five availability reasons.

Make `setup-result.bats` expect:

```python
"resolution": "primary",
"attempted": ["setup-model@medium"],
"fallback_reason": None,
```

- [ ] **Step 2: Run tests to verify RED**

```bash
bats plugins/harness/tests/reference-contracts.bats \
  plugins/harness/tests/skill-contracts.bats \
  plugins/harness/tests/setup-result.bats
```

Expected: FAIL against the old contract and skill prose.

- [ ] **Step 3: Update canonical references**

Document candidate order as `routing.<route>` then `fallbacks.<route>`. A matching native provider uses native execution even when `via` exists; otherwise `via` must be callable. Document unique providers, taste/independent gates, typed failures, cooldowns, one probe, chain exhaustion, and separation from escalation.

Add to `harness-contract.md`:

```yaml
  resolution: primary | fallback
  attempted: ordered model-effort dispatches
  fallback_reason: typed availability reason or empty
```

- [ ] **Step 4: Integrate one resolver loop into all execution skills**

Each skill calls:

```bash
ROUTE_RESULT="$($harness/scripts/resolve-route.py select \
  --rubric "$RUBRIC_PATH" \
  --route "$HARNESS_ROUTE" \
  --native-provider "$HARNESS_NATIVE_PROVIDER" \
  --executors "$HARNESS_EXECUTORS" \
  --attempted "$HARNESS_ATTEMPTED")"
```

For `independent`, pass every authoring provider. Success calls `record-success`; typed availability calls `record-failure`, appends the candidate, and repeats with the unchanged HarnessRequest. Any other failure stops. Preserve every existing sandbox, approval, fixed-target, computer-use, memory, and proof rule. Keep the guarded Codex adapter; do not add a Claude CLI adapter.

- [ ] **Step 5: Expand setup-result provenance**

Add:

```python
"resolution": "primary",
"attempted": [f"{args.model}@{args.effort}"],
"fallback_reason": None,
```

Setup describes its already-running executor and never fabricates fallback.

- [ ] **Step 6: Verify GREEN and authority regressions**

```bash
bats plugins/harness/tests/reference-contracts.bats \
  plugins/harness/tests/skill-contracts.bats \
  plugins/harness/tests/setup-result.bats \
  plugins/harness/tests/codex-dispatch.bats \
  plugins/harness/tests/consumer-memory-boundary.bats
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add plugins/harness/references/routing.md \
  plugins/harness/references/harness-contract.md \
  plugins/harness/skills/execute/SKILL.md \
  plugins/harness/skills/review/SKILL.md \
  plugins/harness/skills/computer-use/SKILL.md \
  plugins/harness/scripts/setup-result.py \
  plugins/harness/tests/reference-contracts.bats \
  plugins/harness/tests/skill-contracts.bats \
  plugins/harness/tests/setup-result.bats
git commit -m "feat(harness): route availability failures across providers"
```

### Task 4: Rubric Derivation, Migration, and Setup Validation

**Files:**
- Modify: `plugins/harness/skills/model-rubric/SKILL.md`
- Modify: `plugins/harness/skills/model-rubric/Default_Rubric.yml`
- Modify: `plugins/harness/skills/setup/SKILL.md`
- Modify: `plugins/harness/tests/model-rubric-contracts.bats`
- Modify: `plugins/harness/tests/skill-contracts.bats`

**Interfaces:**
- Consumes: Task 2's non-mutating `validate` and Task 3's canonical semantics.
- Produces: new/refreshed rubrics contain validated cross-provider chains; Setup status validates without mutating health state.

- [ ] **Step 1: Add failing derivation and Setup tests**

Require Model Rubric to contain these normalized clauses:

```python
required = (
    "derive an ordered `fallbacks.<route>` chain",
    "every fallback provider differs from every earlier provider in its chain",
    "`taste` fallback meets `routing.taste_min`",
    "`independent` fallback remains distinct from every named authoring provider",
    "legacy `routing.fallback` is never automatic authorization",
    "remove `routing.fallback` only after every replacement chain validates",
    "single-provider rubrics remain valid with no fallback chains",
    "show the fallback chains before writing",
)
```

Require `Default_Rubric.yml` to contain `fallbacks: {}` and no concrete fallback. Require Setup status to call `resolve-route.py validate`, report missing dependencies, and remain read-only.

- [ ] **Step 2: Run tests to verify RED**

Run: `bats plugins/harness/tests/model-rubric-contracts.bats plugins/harness/tests/skill-contracts.bats`

Expected: FAIL because derivation, migration, and resolver-backed validation are absent.

- [ ] **Step 3: Implement derivation and migration instructions**

After choosing each primary, filter other-provider rows by the same trust, latency, batch, computer-use, taste, independence, and operation constraints. Preserve developer preference order, permit empty chains, show the complete chains, and require accepted `validate` output before writing.

Migration preserves primary routes and user scores, treats `routing.fallback` as legacy data only, derives and validates route-specific replacements, then removes it. Add this completed example:

```yaml
fallbacks:
  orchestrator: [backup-model@high]
  default: [backup-model@high]
  quick: [backup-model@high]
  review: [backup-model@high]
```

Add `fallbacks: {}` to the seed with a comment that Setup derives values only after the developer interview.

- [ ] **Step 4: Integrate non-mutating Setup validation**

Configured-status mode runs:

```bash
"$harness/scripts/resolve-route.py" validate \
  --rubric "$RUBRIC_PATH" \
  --native-provider "$HARNESS_NATIVE_PROVIDER" \
  --executors "$HARNESS_EXECUTORS"
```

It never supplies a health-state path. Missing `python3`, `yq`, or the resolver is a blocker. Ordered Setup passes the same inventory to Model Rubric and syncs only after validated writes.

- [ ] **Step 5: Verify GREEN**

```bash
bats plugins/harness/tests/model-rubric-contracts.bats \
  plugins/harness/tests/skill-contracts.bats \
  plugins/harness/tests/rubric-path.bats \
  plugins/harness/tests/setup-result.bats
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add plugins/harness/skills/model-rubric/SKILL.md \
  plugins/harness/skills/model-rubric/Default_Rubric.yml \
  plugins/harness/skills/setup/SKILL.md \
  plugins/harness/tests/model-rubric-contracts.bats \
  plugins/harness/tests/skill-contracts.bats
git commit -m "feat(harness): derive provider fallback chains"
```

### Task 5: Release and Full Verification

**Files:**
- Modify: `plugins/harness/README.md`
- Modify: `plugins/harness/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Verify: all Harness, Product Pulse, and PM tests

**Interfaces:**
- Consumes: Tasks 1–4 as one complete behavior.
- Produces: releasable Harness `0.8.0` with matching docs, manifests, consumers, and proof.

- [ ] **Step 1: Document provider-resilient routes**

Add a README section explaining ordered `fallbacks`, availability-only changes, unchanged authority/verification, machine-local cooldowns, and one post-cooldown probe. Add `scripts/resolve-route.py` and its four operations to the scripts table.

- [ ] **Step 2: Bump only Harness to `0.8.0`**

Set the version in `plugins/harness/.claude-plugin/plugin.json` and the Harness marketplace entry. Do not change marketplace metadata or another plugin version.

- [ ] **Step 3: Run scope, formatting, and secret checks**

```bash
git diff --check
git diff --name-only origin/main...HEAD
rg -n '(sk-|ghp_|AKIA|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|raw_error|request_content)' \
  plugins/harness/scripts/resolve-route.py \
  plugins/harness/references plugins/harness/skills plugins/harness/tests
```

Expected: formatting succeeds; only planned paths changed; matches are deliberate prohibition/test text, never credentials or persisted raw errors.

- [ ] **Step 4: Run every relevant suite**

```bash
./plugins/harness/tests/run-tests.sh
./plugins/product-pulse/tests/run-tests.sh
./plugins/pm/tests/run-tests.sh
```

Expected: every suite exits `0`; Product Pulse and PM remain provider-neutral.

- [ ] **Step 5: Reproduce the original failure with temporary fixtures**

Copy Tim's rubric to a temporary file, replace legacy `routing.fallback` with `fallbacks.taste: [gpt-5.6-sol@high]`, and create temporary quota-open state for `anthropic|native`. Run:

```bash
plugins/harness/scripts/resolve-route.py select \
  --rubric "$TEMP_RUBRIC" \
  --state "$TEMP_STATE" \
  --route taste \
  --native-provider anthropic \
  --executors codex \
  --now 2026-08-25T12:00:00Z
```

Expected result fields:

```json
{"status":"fallback","candidate":"gpt-5.6-sol@high","provider":"openai","executor":"codex","reason":"quota"}
```

Keep fixtures outside Git and remove them after inspection.

- [ ] **Step 6: Commit the release**

```bash
git add plugins/harness/README.md \
  plugins/harness/.claude-plugin/plugin.json \
  .claude-plugin/marketplace.json
git commit -m "chore: release harness 0.8.0"
```

- [ ] **Step 7: Run final branch verification**

```bash
git status --short
git log --oneline origin/main..HEAD
git diff --check origin/main...HEAD
./plugins/harness/tests/run-tests.sh
./plugins/product-pulse/tests/run-tests.sh
./plugins/pm/tests/run-tests.sh
```

Expected: clean worktree; only the design, plan, resolver, Harness contracts/skills/tests/docs, and two Harness version fields differ from `origin/main`; every suite exits `0`.

After implementation and review, publish the branch through the repository PR workflow, install Harness `0.8.0`, run `harness:model-rubric` to migrate Tim's live rubric, and resume the pending Shelby deep dive. Those live configuration and research writes are separate accepting workflows and must not be committed to this plugin branch.

## Final-review correction — 2026-08-25

The completed implementation is amended by one final fix wave: external Codex
dispatch uses the typed App Server terminal contract rather than raw CLI status;
`validate` checks every routed row individually; and both validation and
selection enforce the persistent orchestrator-provider boundary plus optional
named authoring providers for `independent`. The final-review ledger contains the
authoritative rulings and acceptance gates; completed task history above remains
unchanged.

PR review adds a second bounded correction: external Codex review validates and
materializes the exact commit in an ephemeral clone; every selection holds the
circuit lock through the missing-state transition; `--attempted` exclusions
require matching recorded typed availability state; and rubric validation
rejects the circuit-key delimiter in provider or executor fields.
