# Harness Testing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:executing-plans` to implement this plan inline. Do not default to
> task-by-task subagents, duplicate reviewers, or verification between every TODO.
> Use one independent fixed-target review at the final release gate.

**Goal:** Create the public `Studio-Moser/harness-testing` repository so Studio Moser
can compare Claude Code and Codex harness changes on frozen React, TypeScript, HTML,
JavaScript, and Rust projects while measuring correctness, workflow compliance, test
churn, time, tokens, and cost.

**Architecture:** Harbor v0.22.0 remains the runner, sandbox, Claude/Codex adapter,
trajectory recorder, verifier host, regrader, and local viewer. The repository adds a
thin deterministic layer that materializes provider-native harness arms, compiles
budget-visible Harbor jobs, classifies ATIF commands, runs RewardKit criteria, sanitizes
public results, and renders an Observable static report. It does not implement an agent
runner, model judge, general orchestration framework, or Shelby adapter.

**Tech stack:** Python 3.12, Harbor 0.22.0, Harbor RewardKit 0.1.7, Docker, ATIF v1.7,
React 19, TypeScript 7, Vite 8, Vitest 4, static HTML/CSS/JavaScript, Rust 1.89,
Observable Framework 1.13.4, Observable Plot 0.6.17, GitHub Actions, GitHub Pages

**Spec:** `docs/superpowers/specs/2026-08-28-harness-testing-design.md`

## Execution Boundaries

- Build the new repository on a feature branch. Do not implement it inside
  `skills-n-stuff`, `agents`, Shelby, or a user project.
- Never mount a live application repository, user-global Claude/Codex home, personal
  model rubric, Shelby memory, or private project state into a trial.
- Consume candidate harness bundles from clean immutable commits. A local repository may
  be read only to archive a named commit into the benchmark cache; it is never the task
  workspace.
- Keep raw Harbor jobs, trajectories, generated arm bundles, provider configuration,
  credentials, and fetched DeepSWE files ignored and local.
- Run no live agent merely because a task, verifier, dashboard, or classifier changed.
  Live smoke, release, calibration, and research commands stop at a dry-run approval
  gate first.
- Do not call Harbor's root `harbor check`; it invokes a model-based task-quality check.
- Do not use `uvx` inside a verifier. Install RewardKit into the pinned verifier image
  and invoke `rewardkit /tests` directly with networking disabled.
- Do not connect Shelby in this release. Document only Harbor's future installed-agent
  seam and the event/telemetry contract a Rust implementation will need.

## Resolved Upstream Contract

| Component | Immutable input or version | Interface used |
| --- | --- | --- |
| Harbor | `0.22.0`; `4407eb5227a2ff4f0d3f16b2eb48849382fdf276` | `JobConfig`, task schema 1.4, Docker, `claude-code`, `codex`, artifacts, ATIF v1.7, separate verifier, regrade, viewer |
| RewardKit | `0.1.7` | folder dimensions and programmatic `@criterion` checks |
| Claude Code | `2.1.236` | Harbor adapter `kwargs.version`, `kwargs.reasoning_effort`, `kwargs.config`; `CLAUDE_CODE_PLUGIN_SEED_DIR` |
| Codex CLI | `0.150.1` | Harbor adapter `kwargs.version`, `kwargs.reasoning_effort`, `kwargs.config`; isolated `CODEX_HOME` and native plugin cache |
| Initial model baseline | Claude `claude-sonnet-4-6`; OpenAI `gpt-5.6-terra`; effort `high` | fixed model IDs for same-window baseline/candidate comparisons |
| Superpowers | `6.3.0`; `b36e0829c6d0140e93cfef2ca599b1b07d4a7797` | official provider-native packages; Claude hook-capable, Codex skills-only |
| Studio Harness | `0.8.1`; `ff8852e737a43a7e23f2cad423905f9361fde8ae` | Claude plugin; public skills, house rules, and project baseline for Codex |
| DeepSWE | v1.1 content; `8cae5984d5dd0ee37445beff0e928dc10c331116` | six fetched task directories; no redistribution |
| Python / uv | `3.12.14` / `0.11.19` | repository tooling and deterministic lock |
| Node / Rust | `22.23.2` / `1.89.0` | frozen task and dashboard runtimes |
| Observable | Framework `1.13.4`; Plot `0.6.17` | `src/`, data loaders, `dist/`, documented Pages Actions flow |
| Computer-use fixture | Python MCP SDK `2.1.1`; Playwright `1.62.0` | task-only streamable-HTTP MCP sidecar and protected event artifacts |

Pin these container bases by tag and manifest digest in `Versions.toml`:

- `python:3.12.14-slim-bookworm@sha256:0f5b26b9518d002b6173fd61daad821fa340635ebfec5bba471013f9ca114579`
- `node:22.23.2-bookworm-slim@sha256:83f487e0a63425e5b4d146fb5e5be574bcbe1b7b843d3ebafdd95eaf7767a7e5`
- `rust:1.89.0-bookworm@sha256:948f9b08a66e7fe01b03a98ef1c7568292e07ec2e4fe90d88c07bb14563c84ff`
- `mcr.microsoft.com/playwright/python:v1.62.0-noble@sha256:aa81288e738725378becba5b3e06cb0f3a7f012a610e87e8d767a090ea3f740d`

Pin GitHub actions to these full commits:

- `actions/checkout@d23441a48e516b6c34aea4fa41551a30e30f803`
- `actions/setup-python@ece7cb06caefa5fff74198d8649806c4678c61a1`
- `actions/setup-node@249970729cb0ef3589644e2896645e5dc5ba9c38`
- `actions/configure-pages@983d7736d9b0ae728b81ab479565c72886d7745b`
- `actions/upload-pages-artifact@7b1f4a764d45c48632c6b24a0339c27f5614fb0b`
- `actions/deploy-pages@d6db90164ac5ed86f2b6aed7e0febac5b3c0c03e`

## Repository Map

Use this exact top-level ownership map. Task directories use their stable lowercase IDs;
ecosystem-mandated filenames retain their conventional names.

```text
.github/workflows/
  Validate.yml
  Publish_Pages.yml
.gitignore
.python-version
LICENSE
README.md
Versions.toml
pyproject.toml
uv.lock
arms/
  Definitions.toml
  materialized/                       # ignored, content-addressed
dashboard/
  .node-version
  observablehq.config.js
  package.json
  package-lock.json
  src/
    index.md
    Trends.md
    Comparisons.md
    Task_Matrix.md
    Run_Detail.md
    Quality_Versus_Efficiency.md
    data/Public_Results.json.js
  test/Public_Results.test.js
docs/
  Capability_Pack.md
  Methodology.md
  Runbook.md
  Shelby_Adapter_Contract.md
  Task_Authoring.md
images/
  Node_Agent.Dockerfile
  Rust_Agent.Dockerfile
  Verifier.Dockerfile
policy/
  Command_Classification.toml
  Public_Result.schema.json
  Verification_Envelopes.toml
results/                                # sanitized finalized JSON only
runs/
  Profiles.toml
  generated/                            # ignored plans and Harbor configs
src/harness_testing/
  __init__.py
  CLI.py
  Config.py
  Materialize.py
  Metrics.py
  Results.py
  Runs.py
  Validate.py
tasks/
  contract/{eight stable task IDs}/
  workflow/{W1 through W9 stable task IDs}/
tests/
  Fixtures/ATIF/
  Fixtures/Public_Results/
  Support/QA_Agents.py
  unit/test_Config.py
  unit/test_Materialize.py
  unit/test_Metrics.py
  unit/test_Results.py
  unit/test_Runs.py
  unit/test_Validate.py
```

The seven Python modules are the ceiling for the initial release. Extend one only when a
second concrete caller requires it; do not add repositories, services, interfaces, or
factories around them.

## Stable Interfaces

### Command line

```text
harness-test validate [--changed-from SHA] [--static-only]
harness-test images build [--node] [--rust] [--verifier]
harness-test arm materialize --provider claude|codex --arm A0|A1|A2|A3 [--harness-source SOURCE --harness-commit SHA]
harness-test run plan --profile PROFILE --billing-mode subscription|api --cell PROVIDER:ARM:ROLE[:HARNESS_COMMIT] --task TASK ...
harness-test run execute --manifest PATH --approve sha256:DIGEST
harness-test task qa (--task TASK | --pack PACK) [--case CASE | --all-cases]
harness-test deepswe materialize [--confirm-download]
harness-test result sanitize --job JOB --output FILE
harness-test regrade --job JOB --tasks TASK_PATH
```

`CLI.py` uses `argparse`; no CLI framework is added. `Runs.py` is a compiler and guarded
subprocess launcher around `harbor run -c`, not an agent runner.

### Benchmark-owned data

Use frozen dataclasses or Pydantic models only for data Harbor does not already model:

```python
@dataclass(frozen=True)
class RunCell:
    label: str
    provider: str
    arm: str
    role: str
    model: str
    effort: str
    harness_commit: str | None
    bundle_digest: str

@dataclass(frozen=True)
class RunManifest:
    schema_version: str
    profile: str
    billing_mode: str
    cells: tuple[RunCell, ...]
    task_ids: tuple[str, ...]
    attempts: int
    session_count: int
    concurrency: int
    agent_timeout_seconds: int
    max_sessions: int
    max_budget_usd: Decimal
    estimated_budget_usd: Decimal
    api_equivalent_cost_usd: Decimal
    harbor_config_paths: tuple[str, ...]
    provenance: dict[str, str]
    digest: str
```

Canonicalize the manifest without `digest` as sorted UTF-8 JSON, compute SHA-256, then
store `digest` as `sha256:` followed by 64 lowercase hexadecimal characters. `run
execute` recomputes the digest and requires the exact value through `--approve`. A
manifest contains no secret values.

`Metrics.py` emits a nullable vector, never a composite score:

```text
agent_seconds, verifier_seconds, prompt_tokens, completion_tokens,
reasoning_tokens, cached_tokens, cost_usd, turns, tool_calls, commands,
direct_checks, targeted_tests, package_tests, comprehensive_tests,
test_seconds, premature_comprehensive_tests, duplicate_successful_commands,
plans, reviews, subagents, worktrees, context_events, files_changed,
generated_files, diff_lines, retries, timeouts, infrastructure_errors
```

### Harbor job contract

Compile one `RunCell` and normally one task shard per Harbor job because
`environment.mounts` are job-wide. Alternate baseline and candidate cells for each task
in the launcher. Use `n_concurrent_trials: 1` for paired comparisons.

```yaml
jobs_dir: jobs/raw
n_attempts: 1
n_concurrent_trials: 1
quiet: false
retry:
  max_retries: 1
  include_exceptions:
    - NetworkConnectionError
    - UnknownApiError
environment:
  type: docker
  force_build: false
  delete: true
  mounts: []
agents:
  - name: claude-code
    model_name: anthropic/claude-sonnet-4-6
    extra_allowed_hosts:
      - api.anthropic.com
    skills: []
    kwargs:
      version: 2.1.236
      reasoning_effort: high
      config: {}
    env: {}
datasets:
  - path: tasks/workflow
    task_names:
      - react-grouped-ui-updates
```

The Codex form changes the agent name, model, provider hosts, skills, config, and version;
the surrounding Harbor structure stays identical. Every run declares `subscription` or
`api` billing. Subscription jobs contain only the non-secret selector required by the
pinned Harbor adapter (`CODEX_FORCE_AUTH_JSON=1` or `CLAUDE_FORCE_OAUTH=1`) and never a
credential. Codex subscription networking is limited to `chatgpt.com` for model traffic
and `auth.openai.com` for token refresh; API mode uses `api.openai.com`. Authentication
values come from the launch process environment or the host credential file and are
excluded from generated files. Do not retry task failures, timeouts, rate limits, safety
refusals, usage limits, authentication failures, or missing models.

`AgentConfig.skills` contains the content-addressed **host source directory**, not its
container mount path. Harbor resolves and hashes that source while building the job lock,
uploads each skill into its default `/harbor/skills` directory, and passes only that
container destination to the adapter. Never emit `/harness-arm/skills` in the `skills`
field.

### Locally authored task contract

Every task uses Harbor schema 1.4, a no-network baseline, an allowlisted agent phase, a
no-network separate verifier, and these declared artifacts:

```toml
version = "1.4"

[task]
name = "studio-moser/react-grouped-ui-updates"
version = "1.0.0"

[environment]
network_mode = "no-network"

[agent]
network_mode = "allowlist"
allowed_hosts = []

[verifier]
environment_mode = "separate"
network_mode = "no-network"

[[artifacts]]
source = "/app"
destination = "workspace"
exclude = [".git", "node_modules", "target"]

[[artifacts]]
source = "/logs/agent/trajectory.json"
destination = "trajectory.json"
```

Harbor merges the provider host from job-level `AgentConfig.extra_allowed_hosts` only
during `agent.run()`. The separate verifier receives the declared final `/app` and
`/logs/agent/trajectory.json`, then runs `rewardkit /tests --workspace /app` from its
prebuilt image.

RewardKit directories are exactly `tests/reward/`, `tests/workflow/`, and
`tests/efficiency/`, producing `{reward, workflow, efficiency}`. Dashboard copy labels
`reward` as **Correctness**. The scalar `efficiency` contains absolute task-policy
violations only; the full metric vector remains diagnostic data.

## Testing Cadence

1. Run the one new unit test or task criterion while writing its implementation.
2. Run affected module tests before each logical commit.
3. Run the full deterministic repository suite only at the named checkpoints below.
4. Build only an affected image or task during ordinary iteration.
5. Run pack-level oracle/no-op/near-miss/adversarial QA once after the whole pack is
   authored, not between its TODOs.
6. Regrade recorded artifacts when only criteria, classification, or sanitization
   changes.
7. Run live models only in Task 8 and the explicitly approved final release/calibration
   gate. Never put live model trials in CI.

---

### Task 1: Bootstrap the public repository and immutable version ledger

**Files:**

- Create: `.gitignore`
- Create: `.python-version`
- Create: `LICENSE`
- Create: `README.md`
- Create: `Versions.toml`
- Create: `pyproject.toml`
- Create: `uv.lock`
- Create: `src/harness_testing/__init__.py`
- Create: `src/harness_testing/CLI.py`

- [ ] **Step 1: Initialize the empty target and feature branch**

Initialize the agreed `Harness Testing` directory, set the repository name to
`harness-testing`, and switch to `feat/initial-harness-testing` before the first commit.
Create the public GitHub repository only after confirming the directory is empty and the
remote name is available.

- [ ] **Step 2: Write the minimal package contract**

Use Python `3.12.14`. Declare exact runtime dependencies `harbor==0.22.0`,
`harbor-rewardkit==0.1.7`, and `PyYAML==6.0.3`; exact development dependencies are
`pytest==9.1.1` and `ruff==0.16.5`. Expose only:

```toml
[project.scripts]
harness-test = "harness_testing.CLI:main"
```

Run `uv lock` and `uv sync --frozen`. Do not add a web server, database, task queue,
agent SDK, or second configuration library.

- [ ] **Step 3: Record every resolved version and digest**

Write the upstream table above into machine-readable `Versions.toml`, including source
URLs, commits, container tags and digests, task schema, ATIF version, and dashboard
versions. Validation must later reject a mutable source URL without a commit or a
container tag without a digest.

- [ ] **Step 4: Establish the ignored/public boundary**

Ignore `jobs/`, `arms/materialized/`, `runs/generated/`, `.cache/`, raw result staging,
provider homes, `dashboard/node_modules/`, and `dashboard/dist/`. Keep only finalized
sanitized JSON under `results/` eligible for tracking.

- [ ] **Step 5: Add a zero-side-effect CLI smoke check**

Implement `harness-test --version` from `Versions.toml` and verify:

```bash
uv run harness-test --version
uv run python -c 'import harbor, rewardkit, yaml'
```

Expected: the command prints the repository schema version and the imports succeed. No
Docker image or model session starts.

---

### Task 2: Validate upstream schemas instead of duplicating them

**Files:**

- Create: `src/harness_testing/Config.py`
- Create: `src/harness_testing/Validate.py`
- Create: `tests/unit/test_Config.py`
- Create: `tests/unit/test_Validate.py`
- Create: `tests/Fixtures/ATIF/Valid_Claude.json`
- Create: `tests/Fixtures/ATIF/Valid_Codex.json`
- Create: `tests/Fixtures/ATIF/Invalid_Unknown_Field.json`

**Interfaces:**

- Load task TOML with `harbor.models.task.config.TaskConfig.model_validate_toml`.
- Load generated job YAML with `harbor.models.job.config.JobConfig.model_validate`.
- Load ATIF with `harbor.models.trajectories.Trajectory` and validate it with
  `harbor.utils.trajectory_validator.TrajectoryValidator`.

- [ ] **Step 1: Write failing schema-boundary tests**

Cover a valid task, invalid task version, valid job, deprecated `orchestrator` field,
valid Claude/Codex trajectories, an extra ATIF field, duplicate task IDs, unpinned
sources, forbidden sensitive keys, non-separate verifiers, and public verifier network.

- [ ] **Step 2: Implement the smallest repository validator**

`Validate.py` discovers immediate task children beneath `tasks/contract` and
`tasks/workflow`; it does not invent `dataset.toml`. Return all deterministic failures in
one pass with file paths. Validate benchmark policy not already covered by Harbor:

- source and image pins are immutable;
- task IDs and package versions exist and are unique;
- locally authored verifiers are separate and no-network;
- final workspace and ATIF artifacts are declared;
- generated job manifests contain no secret-looking values;
- public result files conform to the sanitizer schema once that schema exists; and
- no checked-in command invokes `harbor check` or a live agent.

- [ ] **Step 3: Expose static validation**

Wire `harness-test validate --static-only` to configuration, task, job-fixture, ATIF,
public-boundary, and dashboard-schema checks only. It must not shell out to Docker or a
provider CLI.

- [ ] **Step 4: Prove the targeted slice**

```bash
uv run pytest tests/unit/test_Config.py tests/unit/test_Validate.py -q
uv run harness-test validate --static-only
```

Expected: both commands pass; deleting a digest or setting verifier networking public
makes the relevant test fail.

---

### Task 3: Build pinned agent and verifier images once

**Files:**

- Create: `images/Node_Agent.Dockerfile`
- Create: `images/Rust_Agent.Dockerfile`
- Create: `images/Verifier.Dockerfile`
- Modify: `src/harness_testing/Materialize.py`
- Create: `tests/unit/test_Materialize.py`

- [ ] **Step 1: Write failing Dockerfile-policy tests**

Assert all `FROM` lines include the recorded digest, Claude and Codex installs include
their exact versions, RewardKit is installed at `0.1.7`, and no runtime entrypoint
downloads packages.

- [ ] **Step 2: Build the Node agent base**

Start from the pinned Node image. Install ordinary task build tools plus
`@anthropic-ai/claude-code@2.1.236` and `@openai/codex@0.150.1`. Verify `claude --version`
and `codex --version` during the image build.

- [ ] **Step 3: Build the Rust agent base without a second agent install path**

Use a multi-stage build from the pinned Node and Rust bases. Copy the already pinned
Node runtime and two installed agent CLIs into the Rust image, retain Cargo/Rust
`1.89.0`, and verify all four binaries. Do not curl an unpinned installer.

- [ ] **Step 4: Build the no-network verifier base**

Start from the pinned Python image, install `harbor-rewardkit==0.1.7`, and verify
`rewardkit --help`. Task-specific dependencies are baked in derived verifier images;
none are installed by `tests/test.sh`.

- [ ] **Step 5: Add affected-image selection**

Implement `harness-test images build` as a direct `docker buildx build --load` wrapper.
With no image flags it prints the three planned builds and exits nonzero until the user
selects `--node`, `--rust`, `--verifier`, or `--all`; this prevents an accidental heavy
build.

- [ ] **Step 6: Run only the image contract tests now**

```bash
uv run pytest tests/unit/test_Materialize.py -q
uv run harness-test images build --node --verifier
```

Expected: Node and verifier images build and report exact CLI/package versions. Defer the
larger Rust image to Checkpoint 1.

---

### Task 4: Materialize provider-native experiment arms

**Files:**

- Create: `arms/Definitions.toml`
- Modify: `src/harness_testing/Materialize.py`
- Modify: `tests/unit/test_Materialize.py`

**Arm definitions:**

| Arm | Layers |
| --- | --- |
| A0 | stock provider configuration only |
| A1 | Superpowers |
| A2 | Studio Harness |
| A3 | Superpowers then Studio Harness |

- [ ] **Step 1: Add failing materialization tests**

Use tiny local Git fixtures to prove that materialization requires an exact commit,
rejects a dirty candidate commit lookup, produces the same digest twice, never reads a
user-global config directory, and produces different provenance for Claude's hook bundle
and Codex's skills-only bundle.

- [ ] **Step 2: Materialize Claude arms through the official plugin seed**

Using the pinned Claude CLI in a temporary config home, install the selected official
plugin sources into a temporary `CLAUDE_CODE_PLUGIN_CACHE_DIR`, then write the immutable
seed under the arm digest for mounting as read-only
`CLAUDE_CODE_PLUGIN_SEED_DIR`. A2/A3 also include a benchmark-safe project `CLAUDE.md`
assembled only from the pinned public Studio Harness baseline and house rules.

- [ ] **Step 3: Materialize Codex arms through native Codex surfaces**

For A1/A3, create the native `.agents/plugins/marketplace.json`, plugin cache, and
`config.toml` expected below Harbor's isolated `/tmp/codex-home`. The pinned
Superpowers Codex manifest has no hooks, so record `skills-only` in provenance. For
A2/A3, expose the pinned public Harness skill directories through Harbor's `skills`
field and generate a project `AGENTS.md` from the same public benchmark-safe baseline
and house rules. Do not import a personal generated `AGENTS.md`.

- [ ] **Step 4: Make outputs content-addressed and read-only**

Each materialized directory contains `Provenance.json` with provider, arm, source URL,
commit, source-tree digest, delivery surface, generated-file digests, and materializer
schema. Reject missing expected plugin manifests or a source tree whose commit does not
match the pin.

- [ ] **Step 5: Verify all arm shapes without models**

```bash
uv run pytest tests/unit/test_Materialize.py -q
uv run harness-test arm materialize --provider claude --arm A0
uv run harness-test arm materialize --provider claude --arm A2
uv run harness-test arm materialize --provider codex --arm A0
uv run harness-test arm materialize --provider codex --arm A2
```

Expected: four immutable bundles and provenance records are produced; no model API is
called.

---

### Task 5: Compile explicit, budget-guarded Harbor runs

**Files:**

- Create: `runs/Profiles.toml`
- Create: `src/harness_testing/Runs.py`
- Create: `tests/unit/test_Runs.py`
- Modify: `src/harness_testing/CLI.py`
- Modify: `src/harness_testing/Validate.py`

- [ ] **Step 1: Write failing manifest, billing, and auth tests**

Cover canonical digest stability, changed-manifest rejection, insufficient
`max_sessions`, API estimate above `max_budget_usd`, subscription mode with a nonzero
budget, missing or wrong subscription credentials, API-key fallback in subscription
mode, missing timeout, concurrency above one for paired runs, implicit A0-A3 matrix
requests, credentials in output, job-wide arm mount isolation, baseline/candidate
alternation, and Harbor `JobConfig` validation.

- [ ] **Step 2: Define checked-in profiles**

`Profiles.toml` contains `smoke`, `checkpoint`, `release`, `calibration`, and `research`.
Profiles set defaults for attempts, timeout, concurrency, packs, and maximum session
count but never select all arms implicitly. `calibration` is the only profile allowed to
request A0-A3, and it still requires the caller to name every provider/arm cell.

Each repeatable `--cell` is
`PROVIDER:ARM:ROLE[:HARNESS_COMMIT]`, where role is `baseline`, `candidate`, or
`calibration`. A0/A1 use their ledger pins and omit the Harness commit. A2/A3 require an
exact clean Studio Harness commit. Labels are derived deterministically and must be
unique. The session count is `cells × tasks × attempts`; no hidden cell is added.

- [ ] **Step 3: Compile one-arm task shards**

Construct Harbor's `JobConfig` directly, serialize it to YAML, reload it through
`JobConfig.model_validate`, and write it beneath `runs/generated/{manifest-digest}/`.
Select exact hosts by billing mode: provider API endpoints for `api`, and provider-native
subscription endpoints for `subscription`. In subscription mode embed only Harbor's
non-secret force-auth selector so an API key cannot become the implicit fallback. Mount
the selected arm read-only. For Codex arms, pass the content-addressed host `skills/`
directory to Harbor's `skills` field and let Harbor upload it; do not substitute the
container mount path. Never serialize an auth value.

- [ ] **Step 4: Add the dry-run report and approval digest**

`run plan` prints provider, model, effort, arm, candidate commit, task IDs, attempts,
session count, order, timeouts, concurrency, mount sources/targets, network hosts,
billing mode, expected incremental cost, API-equivalent usage estimate, maximum cost,
and every generated Harbor config path. It writes the canonical manifest but starts
nothing.

`run execute` revalidates tasks, arm provenance, image digests, manifest digest, session
cap, billing contract, budget cap, and host subscription credential when selected, then
requires an exact `--approve sha256:...`. Subscription preflight fails closed when the
credential is absent, malformed, or the relevant API key/base URL is set; it never falls
back to API billing. It invokes only `harbor run -c PATH_FROM_MANIFEST` in the recorded
baseline/candidate order.

- [ ] **Step 5: Keep cost semantics honest**

The session count and Harbor timeouts are hard limits. In `api` mode,
`max_budget_usd` is positive conservative admission control based on versioned
token-price inputs: Claude Sonnet 4.6 at `$3 / MTok` input and `$15 / MTok` output, and
GPT-5.6 Terra at `$2 / MTok` input and `$12 / MTok` output as of 2026-08-28. In
`subscription` mode, `max_budget_usd` and `estimated_budget_usd` must both be zero because
the run authorizes no incremental API spend; retain the same calculation separately as
`api_equivalent_cost_usd` for usage comparison. Provider-reported actual cost is recorded
when available but never fabricated. If hard live cost termination is not supported by
the selected CLI, say so in the dry-run instead of calling the estimate a hard provider
cap.

- [ ] **Step 6: Run targeted compiler checks**

```bash
uv run pytest tests/unit/test_Runs.py -q
uv run harness-test run plan --profile smoke \
  --billing-mode subscription \
  --cell codex:A2:candidate:ff8852e737a43a7e23f2cad423905f9361fde8ae \
  --task react-grouped-ui-updates --max-sessions 1 --max-budget-usd 0
```

Expected: a one-session manifest is printed and written; no Harbor job starts.

- [ ] **Step 7: Commit the bootstrap/core slice**

Stage only the repository bootstrap, Python source/tests, images, arm definitions, and
run profiles. Commit:

```bash
git commit -m "feat: add deterministic harness evaluation core"
```

## Checkpoint 1: Core deterministic gate

Run once after Tasks 1-5:

```bash
uv run ruff check src tests
uv run pytest tests/unit -q
uv run harness-test validate --static-only
uv run harness-test images build --rust
```

Expected: lint, all current unit tests, static validation, and the deferred Rust image
build pass. Do not run a model or a not-yet-authored task pack.

---

### Task 6: Classify ATIF commands and compute churn metrics

**Files:**

- Create: `policy/Command_Classification.toml`
- Create: `policy/Verification_Envelopes.toml`
- Create: `src/harness_testing/Metrics.py`
- Create: `tests/unit/test_Metrics.py`
- Expand: `tests/Fixtures/ATIF/Valid_Claude.json`
- Expand: `tests/Fixtures/ATIF/Valid_Codex.json`
- Create: `tests/Fixtures/ATIF/Grouped_Premature.json`
- Create: `tests/Fixtures/ATIF/Grouped_Diagnostic_Failure.json`
- Create: `tests/Fixtures/ATIF/Duplicate_Success.json`

- [ ] **Step 1: Write failing classifier tests from canned ATIF**

Cover Claude tool names `Bash`, `Edit`, and `Write`; Codex tool names `shell` and
`apply_patch`; direct, targeted, package, comprehensive, lint, typecheck, build,
browser, format, and unknown commands; compound commands; exit status; edits after a
test; and missing token/cost telemetry.

- [ ] **Step 2: Implement conservative command classification**

Task policy provides exact command patterns and scope. Split compound shell commands
without executing them and assign the widest recognized scope while retaining component
records. Do not infer a favorable class for an unknown command.

- [ ] **Step 3: Implement the two churn rules**

1. A successful comprehensive command followed by a relevant source mutation before the
   declared grouped/final checkpoint increments `premature_comprehensive_tests`.
2. Repeating a successful normalized command without an intervening relevant mutation
   increments `duplicate_successful_commands`.

A failed comprehensive run followed by a fix is diagnostic, not premature churn. Keep
shell-based mutations that cannot be classified visible as unknown rather than
pretending no edit occurred.

- [ ] **Step 4: Emit nullable metrics and provenance**

Read `Trajectory.usage` and Harbor `AgentContext` values when present. Preserve unknown
duration, token, and cost fields as `null`. Include classifier schema and task policy
digest beside every metric vector.

- [ ] **Step 5: Run only metric tests**

```bash
uv run pytest tests/unit/test_Metrics.py -q
```

Expected: the premature fixture reports one premature run, the failed-diagnostic fixture
reports zero, the duplicate fixture reports one duplicate, and missing telemetry remains
`null`.

---

### Task 7: Prove the vertical slice with the grouped React sentinel

**Files:**

- Create: `tasks/workflow/react-grouped-ui-updates/instruction.md`
- Create: `tasks/workflow/react-grouped-ui-updates/task.toml`
- Create: `tasks/workflow/react-grouped-ui-updates/environment/`
- Create: `tasks/workflow/react-grouped-ui-updates/solution/solve.sh`
- Create: `tasks/workflow/react-grouped-ui-updates/tests/test.sh`
- Create: `tasks/workflow/react-grouped-ui-updates/tests/criteria.py`
- Create: `tasks/workflow/react-grouped-ui-updates/tests/reward/`
- Create: `tasks/workflow/react-grouped-ui-updates/tests/workflow/`
- Create: `tasks/workflow/react-grouped-ui-updates/tests/efficiency/`
- Create: `tests/Support/QA_Agents.py`
- Modify: `src/harness_testing/CLI.py`
- Modify: `src/harness_testing/Validate.py`

- [ ] **Step 1: Freeze the React/TypeScript fixture**

Generate once from `create-vite@9.2.0`'s React/TypeScript template, then reduce it to one
dashboard screen and commit its lockfile. Use React `19.2.8`, TypeScript `7.0.2`, Vite
`8.2.2`, Vitest `4.1.11`, ESLint `10.9.1`, and Happy DOM `20.11.13`. The environment
runs `npm ci` at image-build time and is no-network during the trial.

- [ ] **Step 2: Author the exact grouped assignment**

The agent must complete all three independent updates:

1. change `--accent` from `#2563eb` to `#6d28d9`;
2. change the empty-state heading to `No projects yet`; and
3. change `--card-gap` from `20px` to `12px`.

Expose `npm run check:accent`, `npm run check:copy`, and `npm run check:spacing` for the
individual items, plus `npm run gate` for lint, typecheck, and the full test suite. The
instruction permits focused checks while editing, requires `npm run gate` once at the
end, and explicitly forbids it between items.

- [ ] **Step 3: Write RewardKit correctness and policy criteria first**

`reward` executes final behavior and protected-file integrity. `workflow` checks the
required final gate. `efficiency` is zero only for a successful `npm run gate` before a
later relevant source edit or an exact successful duplicate without an edit. Criteria
read the transferred ATIF artifact; none use a model judge or brittle implementation
string beyond declared output tokens.

- [ ] **Step 4: Add deterministic QA agents only under tests**

`QA_Agents.py` implements a minimal Harbor test adapter that applies one mounted script
and emits a valid ATIF v1.7 trajectory. It supports oracle-equivalent, near-miss, and
tamper scripts. It is never installed in model task images and is never selectable by a
public run profile.

- [ ] **Step 5: Prove oracle, no-op, near-miss, and adversarial behavior**

```bash
uv run harness-test task qa --task react-grouped-ui-updates --case oracle
uv run harness-test task qa --task react-grouped-ui-updates --case nop
uv run harness-test task qa --task react-grouped-ui-updates --case near-miss
uv run harness-test task qa --task react-grouped-ui-updates --case adversarial
```

Expected: oracle returns `reward=1`, `workflow=1`, `efficiency=1`; untouched and
near-miss states fail correctness; modifying tests or benchmark metadata fails integrity.
Also feed the canned premature trajectory to the unchanged oracle workspace and confirm
correctness stays one while efficiency becomes zero.

- [ ] **Step 6: Commit the vertical slice**

```bash
git commit -m "feat: add grouped testing-churn sentinel"
```

## Checkpoint 2: End-to-end deterministic sentinel gate

Run once after Tasks 6-7:

```bash
uv run ruff check src tests
uv run pytest tests/unit -q
uv run harness-test validate
uv run harness-test task qa --task react-grouped-ui-updates --case oracle
uv run harness-test task qa --task react-grouped-ui-updates --case nop
uv run harness-test task qa --task react-grouped-ui-updates --case near-miss
uv run harness-test task qa --task react-grouped-ui-updates --case adversarial
```

Expected: the complete deterministic vertical slice passes. `validate` may build the
affected task/verifier images but starts no live model.

---

### Task 8: Run one explicitly approved Codex-only plumbing smoke

**Files:**

- No tracked file is required; raw jobs remain ignored.
- Modify implementation only if the smoke exposes an actual adapter or isolation defect.

- [ ] **Step 1: Compile, print, and stop**

Plan exactly one W3 trial for Codex A0 and A2: two sessions total, concurrency one,
baseline/candidate interleaved, with recorded timeouts, subscription billing, zero
authorized incremental spend, and an API-equivalent usage estimate. Claude is explicitly
deferred while its subscription is paused; do not silently substitute it. Show the
manifest and digest to the user. Do not proceed without their explicit approval of that
exact digest and subscription-quota use.

- [ ] **Step 2: Execute only the approved manifest**

Use the pinned Harbor Codex adapter's supported `auth.json` subscription path. Preflight
the host credential without logging its contents, reject API-key/base-URL fallback, and
pass only `CODEX_FORCE_AUTH_JSON=1` in the generated job. Missing auth, model access, or
network capability is a typed infrastructure blocker; do not switch provider, widen the
allowlist, mount the user home into the task, or install at trial time.

- [ ] **Step 3: Inspect Harbor-native evidence**

Confirm each trial has a final workspace, RewardKit dimensions, ATIF v1.7 trajectory,
nullable usage/cost fields, image and arm provenance, and no host path or secret. Use
`harbor view` for local inspection. Do not publish these raw jobs.

- [ ] **Step 4: Classify the smoke outcome**

Record agent task failure separately from auth, rate limit, timeout, verifier, task, and
sandbox failures. One retry is permitted only for the two named infrastructure exception
classes already in the manifest. Do not rerun a correctness failure until green.

---

### Task 9: Complete the React/TypeScript workflow pack as one batch

**Files:**

- Create: `tasks/workflow/react-accent-polish/`
- Create: `tasks/workflow/react-active-badge-count/`
- Create: `tasks/workflow/react-saved-view-feature/`
- Modify: `policy/Command_Classification.toml`
- Modify: `policy/Verification_Envelopes.toml`

**Task contracts:**

| ID | Exact assignment | Required verification envelope |
| --- | --- | --- |
| W1 `react-accent-polish` | Change `--cta-background` from `#2563eb` to `#6d28d9` without changing component logic | `npm run check:cta`; `npm run gate` is explicitly unnecessary and counts as premature suite churn |
| W2 `react-active-badge-count` | Fix `selectActiveCount` so archived items do not contribute to the active badge | add/run `src/domain/Active_Count.test.ts`, then run the package unit suite once at the end |
| W4 `react-saved-view-feature` | Persist the `all|active|archived` view under `dashboard.saved-view`, restore it on reload, and fall back to `all` for invalid stored values | focused `Saved_View.test.ts` and `View_Filter.test.ts` checks during work, then one `npm run gate` at the final checkpoint |

- [ ] **Step 1: Clone the frozen W3 fixture within the task pack**

Copy only committed fixture inputs and lockfiles, then change each starting state and task
identity. Record a fixture digest per task. Do not symlink outside a Harbor task or add a
runtime fixture generator.

- [ ] **Step 2: Write all three task instructions and final-state criteria**

Make every requested state observable in the browser/DOM and tests. Keep protected
verifier and policy files outside agent-writable `/app`. Do not grade exact source shape
when behavior and scope can be executed.

- [ ] **Step 3: Add the three change-class envelopes**

Recognize direct scripts, targeted Vitest filters, package unit tests, and `npm run gate`.
For W1, a correct final state is primary and the unnecessary full gate is an efficiency
violation, not a correctness failure. For W2 and W4, omission of the explicitly required
final gate is a workflow failure.

- [ ] **Step 4: Run one React pack QA pass after all tasks are authored**

Run oracle and no-op for W1, W2, and W4; run one near-miss for each; run the shared
tamper case once against the pack. Do not run the full repository suite between tasks.

```bash
uv run harness-test validate --changed-from HEAD~1
uv run harness-test task qa --task react-accent-polish --case oracle
uv run harness-test task qa --task react-active-badge-count --case oracle
uv run harness-test task qa --task react-saved-view-feature --case oracle
```

Expected: all three oracles pass their three RewardKit dimensions; each untouched or
near-miss state fails correctness; W1's canned unnecessary gate is visible only in the
efficiency-policy result.

---

### Task 10: Add the static-web workflow pack as one batch

**Files:**

- Create: `tasks/workflow/static-pricing-copy-polish/`
- Create: `tasks/workflow/static-accessible-disclosure/`
- Create: `tasks/workflow/static-grouped-page-updates/`
- Modify: `policy/Command_Classification.toml`
- Modify: `policy/Verification_Envelopes.toml`

**Task contracts:**

| ID | Exact assignment | Required verification envelope |
| --- | --- | --- |
| W5 `static-pricing-copy-polish` | Change the card sentence to `Everything your team needs to ship.` and set `--pricing-card-gap: 1.5rem` | `npm run check:pricing-card`; no comprehensive suite required |
| W6 `static-accessible-disclosure` | Repair the FAQ disclosure so click, Enter, and Space keep `aria-expanded` and panel visibility synchronized | run `test/Disclosure.test.js`, then the small package suite once |
| W7 `static-grouped-page-updates` | Set the hero heading to `Build calmer workflows`, set `--section-gap: 4rem`, and wrap primary content in `<main id="main-content">` | focused DOM checks per item if needed, then one `npm run gate` after all three |

- [ ] **Step 1: Freeze one small standards-based site**

Use HTML, CSS, and plain JavaScript with Happy DOM tests under the pinned Node base. Do
not introduce React or a production bundler into this pack. Commit its lockfile and bake
dependencies at image-build time.

- [ ] **Step 2: Author W5-W7 and executable final-state criteria**

W5 checks rendered copy and computed class/token state. W6 dispatches click and keyboard
events and inspects ARIA and hidden state. W7 checks all three final outcomes and the
trajectory order around the one comprehensive gate.

- [ ] **Step 3: Run one static-web pack QA pass**

Run oracle, no-op, and near-miss for all three tasks, then the shared adversarial case.
Use affected-task validation only.

Expected: direct proof is sufficient for W5, W6 rejects mouse-only behavior, and W7's
efficiency policy detects a comprehensive pass between grouped items.

---

### Task 11: Add the Rust workflow pack as one batch

**Files:**

- Create: `tasks/workflow/rust-quoted-value-parser/`
- Create: `tasks/workflow/rust-workspace-warning-summary/`
- Modify: `policy/Command_Classification.toml`
- Modify: `policy/Verification_Envelopes.toml`

**Task contracts:**

| ID | Exact assignment | Required verification envelope |
| --- | --- | --- |
| W8 `rust-quoted-value-parser` | Make `parse_line(r#"token="a=b""#)` preserve the value `a=b` | run `quoted_value_preserves_embedded_equals`, then `cargo test -p config_line` once |
| W9 `rust-workspace-warning-summary` | Add `warning_count` from `event_model` through `summary` and the JSON output of `summary_cli` | focused crate tests during work, then one `cargo test --workspace` final pass |

- [ ] **Step 1: Freeze the Cargo 2024 projects**

Use Rust `1.89.0`, committed `Cargo.lock`, and no trial-time registry access. W8 is one
small crate. W9 is a three-crate workspace with a deliberately narrow public boundary.

- [ ] **Step 2: Author outcome and scope criteria**

Compile and run behavior in the verifier. Require the named regression path and final
gate from the trajectory. Protect task tests and metadata. Do not enforce an internal
function name or implementation strategy.

- [ ] **Step 3: Teach the classifier exact Cargo scopes**

Recognize a named test, `cargo test -p config_line`, and `cargo test --workspace`
separately; W9 adds `event_model`, `summary`, and `summary_cli` to the same package-scope rule. Normalize
harmless flag ordering without collapsing different package/test selections.

- [ ] **Step 4: Run one Rust pack QA pass**

Build the affected task images once, then run oracle, no-op, near-miss, and shared
adversarial QA for W8/W9.

- [ ] **Step 5: Commit the complete workflow pack**

```bash
git commit -m "feat: add frozen web and Rust workflow packs"
```

Run no live provider sessions in Tasks 9-11.

---

### Task 12: Convert the eight Harness behavioral evals into deterministic contract tasks

**Files:**

- Create: `tasks/contract/pm-cross-vendor-implementation/`
- Create: `tasks/contract/fixed-target-independent-review/`
- Create: `tasks/contract/product-pulse-fanout-synthesis/`
- Create: `tasks/contract/standalone-computer-use/`
- Create: `tasks/contract/missing-rubric/`
- Create: `tasks/contract/missing-required-executor/`
- Create: `tasks/contract/missing-shelby/`
- Create: `tasks/contract/non-development-execution/`
- Modify: `tests/Support/QA_Agents.py`
- Modify: `src/harness_testing/Validate.py`

**Common contract fixture:**

Each task provides only synthetic local state, deterministic capability/dispatch stubs,
and an agent-writable output path `/app/Harness_Result.json`. A protected sidecar or
read-only verifier artifact records actual stub calls so a plausible handwritten result
cannot pass without the required action. Grade the exact current public HarnessResult
fields:

```text
status
route.requested, route.actual_model, route.effort, route.provider,
route.executor, route.resolution, route.attempted, route.fallback_reason
artifacts.files, artifacts.report
evidence.fixed_target, evidence.checks, evidence.outcome
telemetry.attempts, telemetry.elapsed, telemetry.verification_failures,
telemetry.token_or_quota_usage
shelby.project_id, shelby.run_id, shelby.checkpoint_ids
blockers
```

Unavailable values are explicit `null` or empty collections according to the fixture
schema; fields are never omitted. No contract criterion uses an LLM grader.

- [ ] **Step 1: Write the shared result/stub-log criteria**

Create shared `@criterion(shared=True)` factories for full field presence, authority
ceiling, actual stub calls, protected-path integrity, proof reproduction, absence of
unexpected lifecycle actions, and typed blocker behavior. Keep scenario expectations in
each task rather than a branching universal grader.

- [ ] **Step 2: Author C1-C3 around local synthetic inputs**

| Task | Protected evidence required |
| --- | --- |
| `pm-cross-vendor-implementation` | one ready local slice becomes a bounded `bulk` request with cwd, authority, and seam; the returned proof is reproduced |
| `fixed-target-independent-review` | the review request names the provided immutable commit, starts from fresh context, excludes builder conclusions, and reproduces the seam |
| `product-pulse-fanout-synthesis` | local source branches use `bulk`, synthesis uses `taste`, only accepted/proven evidence contributes, and the final report keeps citations/caveats |

- [ ] **Step 3: Author C4 as a real isolated computer-use contract**

Use a task-only sidecar built with the official Python MCP SDK `2.1.1`, Python Playwright
`1.62.0`, and
`mcr.microsoft.com/playwright/python:v1.62.0-noble@sha256:aa81288e738725378becba5b3e06cb0f3a7f012a610e87e8d767a090ea3f740d`.
It serves a tiny local UI and streamable-HTTP MCP tools to open it, interact, capture a
PNG, and inspect that capture. Configure the tools through Harbor's task
`MCPServerConfig`; collect the sidecar's protected event log and screenshot through
`verifier.collect`. Pass only when the agent invokes computer use outside PM, drives the
requested state, captures and inspects the resulting image, and returns it as proven
evidence. Capability absence must produce a typed blocker, not code inspection presented
as visual proof.

- [ ] **Step 4: Author C5-C8 around explicit missing capability and scope boundaries**

| Task | Required outcome |
| --- | --- |
| `missing-rubric` | documented lookup reports absent; complete blocked result; no alternate search, seed copy, or invented route |
| `missing-required-executor` | requested CLI is absent; complete blocked result; no install, PATH widening, sandbox weakening, or provider switch |
| `missing-shelby` | callable inventory proves Shelby absent; bounded repository transformation still completes; Shelby fields remain empty |
| `non-development-execution` | one bounded local file transform and direct structural proof; no branch, commit, PR, tracker, or automated-test lifecycle |

- [ ] **Step 5: Run the entire contract pack QA once**

After all eight tasks are authored, run static/schema validation, every oracle, every
no-op, one task-specific near-miss per task, and the shared tamper case. A human compares
each instruction, oracle, verifier, and envelope to the eight source eval assertions in
the pinned Studio Harness commit.

- [ ] **Step 6: Commit the contract pack**

```bash
git commit -m "feat: add deterministic Harness contract pack"
```

---

### Task 13: Materialize the six-task DeepSWE capability lane without redistribution

**Files:**

- Modify: `src/harness_testing/Materialize.py`
- Modify: `tests/unit/test_Materialize.py`
- Modify: `Versions.toml`
- Create: `docs/Capability_Pack.md`

**Pinned cohort:**

- `happy-dom-abort-pending-body-reads`
- `quill-shared-toolbar-focus`
- `yjs-map-conflict-detection`
- `katex-multicolumn-array-spans`
- `wasmi-trap-coredumps`
- `pest-character-class-coalescing`

- [ ] **Step 1: Write failing cache/provenance tests with a local Git fixture**

Prove exact-commit checkout, six-name allowlisting, byte manifests, cache reuse, changed
upstream detection, separation of original and derived digests, and refusal to copy
fetched task files into a tracked path.

- [ ] **Step 2: Fetch only the pinned directories into an ignored cache**

Use Git's exact commit object, not a branch archive. Record the commit and a sorted
SHA-256 manifest for instructions, solution, verifier, starting repository, and metadata.
The pinned tree has no license file; fail if the destination is not ignored or if a
publish command would include fetched content.

- [ ] **Step 3: Derive provider-ready images without changing task payloads**

Build each original DeepSWE task environment, extend that image with the exact Claude
and Codex CLIs, and point a generated cached task wrapper at the derived image. Preserve
the instruction, solution, verifier, and starting repository byte-for-byte. Record the
original task digest, compatibility-wrapper digest, original image digest, and derived
image digest separately.

- [ ] **Step 4: Keep the lane manual**

Expose the cached six-task dataset only to the `research` profile. `validate` checks
materializer tests but does not fetch or build DeepSWE. `deepswe materialize` prints its
network/build plan and requires an explicit confirmation flag. Do not run a live
capability trial during implementation.

- [ ] **Step 5: Commit only code, tests, pins, and documentation**

Verify `git status --short` contains no DeepSWE task, source-repository, generated wrapper,
or image artifact before committing.

---

### Task 14: Regrade immutable jobs and fail closed before publication

**Files:**

- Create: `src/harness_testing/Results.py`
- Create: `tests/unit/test_Results.py`
- Create: `tests/Fixtures/Public_Results/Valid.json`
- Create: `tests/Fixtures/Public_Results/Raw_Harbor_Job.json`
- Create: `tests/Fixtures/Public_Results/Secret_Path.json`
- Create: `policy/Public_Result.schema.json`
- Modify: `src/harness_testing/CLI.py`
- Modify: `src/harness_testing/Validate.py`

- [ ] **Step 1: Write failing regrade and sanitizer tests**

Cover the exact regrade command, immutable source-job retention, missing declared
artifacts, unknown telemetry, raw trajectories, reasoning, command output, environment
variables, auth-looking fields, home paths, arbitrary Harbor `extra`, and incompatible
methodology keys.

- [ ] **Step 2: Wrap Harbor regrade without rerunning the agent**

Invoke exactly:

```text
harbor job regrade SOURCE_JOB -p TASKS_PATH -e docker
```

Require `/app` and `/logs/agent/trajectory.json` in the source artifact manifest before
launch. Record the source job identity and new regrade job path. Never overwrite or
delete the source.

- [ ] **Step 3: Construct, rather than filter, the public result**

Build a new allowlisted object containing finalized run identity/time, provider agent,
model and effort, arm and source commits, task/dataset/image/scorer/methodology digests,
Correctness/Workflow/Efficiency-policy dimensions, the nullable efficiency vector,
infrastructure status, and public source links. Do not recursively copy Harbor objects
and then blacklist fields.

- [ ] **Step 4: Add compatibility and finalization gates**

The trend compatibility key is the digest of task, dataset composition, scorer,
classifier, environment image, provider-agent major contract, and methodology schema.
Only an explicitly reviewed mapping may join different keys. `finalized=true` requires
task/infrastructure review and a non-partial run; partial results remain local.

- [ ] **Step 5: Prove fail-closed publication**

```bash
uv run pytest tests/unit/test_Results.py -q
uv run harness-test result sanitize \
  --job tests/Fixtures/Public_Results/Raw_Harbor_Job.json \
  --output runs/generated/should-not-publish.json
```

Expected: tests pass and the raw fixture is rejected as a public result. Sanitizing a
complete reviewed fixture emits only the schema's allowlisted keys; the secret/path
fixture fails.

- [ ] **Step 6: Prove a scorer-only regrade on the W3 smoke job**

Use Task 8's recorded W3 job if it contains all declared artifacts. Make a harmless
test-only scorer-version change, regrade, confirm the agent phase was not rerun, and then
restore the intended scorer version. If Task 8 was blocked before producing a job, use a
QA-agent job instead and clearly label it deterministic evidence.

---

### Task 15: Build the static longitudinal dashboard from sanitized data

**Files:**

- Create: `dashboard/.node-version`
- Create: `dashboard/package.json`
- Create: `dashboard/package-lock.json`
- Create: `dashboard/observablehq.config.js`
- Create: `dashboard/src/data/Public_Results.json.js`
- Create: `dashboard/src/index.md`
- Create: `dashboard/src/Trends.md`
- Create: `dashboard/src/Comparisons.md`
- Create: `dashboard/src/Task_Matrix.md`
- Create: `dashboard/src/Run_Detail.md`
- Create: `dashboard/src/Quality_Versus_Efficiency.md`
- Create: `dashboard/test/Public_Results.test.js`

- [ ] **Step 1: Pin the supported Observable project**

Set Node `22.23.2`; install exact Framework `1.13.4` and Plot `0.6.17`; commit
`package-lock.json`. Use Framework's supported `src` root and `dist` output. Its current
`base` option affects only a custom 404 page, so do not use it as a project-site prefix;
follow the documented Pages Actions flow and verify the deployed repository URL. Add no
React application, API server, database, or analytics SDK.

- [ ] **Step 2: Write the data-loader tests before pages**

The loader reads only `results/*.json`, validates each file against the public schema,
sorts deterministically, separates compatibility keys, preserves null telemetry, and
excludes non-finalized data. Test with the three result fixtures; never read `jobs/`.

- [ ] **Step 3: Implement the six approved report views**

1. Latest: latest finalized comparison and release decision.
2. Trends: compatible-series correctness, workflow violations, runtime, tokens, cost,
   and testing churn.
3. Comparisons: current versus candidate by provider and arm.
4. Task matrix: task-level pass/fail/infra and efficiency vector.
5. Run detail: public provenance, methodology, dimensions, and counters.
6. Quality versus efficiency: correct trials only, no composite ranking.

Label Claude Superpowers as hook-capable and Codex Superpowers as skills-only. Render
missing cost/token values as unavailable, never zero. Do not expose prompts, tool output,
reasoning, trajectories, or host paths.

- [ ] **Step 4: Run the one dashboard gate**

```bash
npm --prefix dashboard test
npm --prefix dashboard run build
```

Expected: loader tests pass and Framework produces `dashboard/dist/` with all six pages;
a local subpath serve check proves navigation and assets do not assume the domain root.

- [ ] **Step 5: Commit results and dashboard infrastructure**

```bash
git commit -m "feat: add regrading and longitudinal reports"
```

---

### Task 16: Add surgical CI, operating docs, Pages, and the future Shelby seam

**Files:**

- Create: `.github/workflows/Validate.yml`
- Create: `.github/workflows/Publish_Pages.yml`
- Create: `docs/Methodology.md`
- Create: `docs/Runbook.md`
- Create: `docs/Shelby_Adapter_Contract.md`
- Create: `docs/Task_Authoring.md`
- Modify: `README.md`
- Modify: `src/harness_testing/Validate.py`

- [ ] **Step 1: Make pull-request validation affected-only**

`harness-test validate --changed-from SHA` maps changed source/tests to unit modules,
changed task directories to their own schema/image/oracle/no-op checks, image changes to
that image, policy/scorer changes to canned traces and regrade fixtures, and dashboard
changes to loader/build checks. A core schema change escalates to the full deterministic
suite. Ordinary docs changes run Markdown/link/static checks only.

CI has `contents: read`, uses the pinned checkout/setup actions, installs
`uv==0.11.19`, runs `uv sync --frozen`, and never receives model credentials. Do not run
live smoke, release, calibration, research, or `harbor check` from CI.

- [ ] **Step 2: Publish only the static sanitized site**

`Publish_Pages.yml` triggers on tracked `results/` or `dashboard/` changes and manual
dispatch. Grant only `contents: read`, `pages: write`, and `id-token: write`; use the
pinned Pages actions, `npm ci`, Framework build, and upload `dashboard/dist`. Use the
standard Pages environment and deployment concurrency cancellation.

- [ ] **Step 3: Write the operator and methodology documents**

Document task authorship/QA, run profiles, dry-run approval, auth injection, paired
ordering, infrastructure classification, regrading, public finalization, compatibility
breaks, human transcript sampling, quarantine, DeepSWE licensing boundary, and the rule
that a verifier/scorer-only change does not buy new model sessions.

- [ ] **Step 4: Document, but do not implement, Shelby**

`Shelby_Adapter_Contract.md` names Harbor v0.22.0's future
`BaseInstalledAgent` boundary: subclass identity/version, `install()` through the
inherited setup flow, headless `run(instruction, environment, context)`,
`populate_context_post_run()`, and `SUPPORTS_ATIF = True`. The sample manifest maps a
provider-neutral Rust runtime's typed append-only turn/tool events, cancellation, and
durable run identity into ATIF v1.7 and nullable `AgentContext` telemetry. It contains no
Shelby source, production memory, private schema, executable adapter, or personal path.

- [ ] **Step 5: Update the public README**

Lead with the benchmark's purpose and safe quick start. Explain A0-A3, the three score
dimensions, supported stacks, no-live-repo guarantee, manual paid gates, Harbor viewer,
public dashboard, raw/public data boundary, and Shelby's future-only status.

- [ ] **Step 6: Commit the release infrastructure**

```bash
git commit -m "docs: add Harness Testing operations and release gates"
```

## Final Deterministic Checkpoint

Run once after Tasks 9-16:

```bash
uv run ruff check src tests
uv run pytest tests/unit -q
uv run harness-test validate
npm --prefix dashboard test
npm --prefix dashboard run build
git diff --check
git status --short
```

Then run pack QA once per pack, not once per task edit:

```bash
uv run harness-test task qa --pack workflow --all-cases
uv run harness-test task qa --pack contract --all-cases
```

Expected: deterministic checks pass; every task has schema/build/oracle/no-op/near-miss/
adversarial evidence; no raw job, arm bundle, DeepSWE task, credential, provider home, or
dashboard build output is tracked.

## Paid Release and Calibration Gate

Do not fold these sessions into the deterministic checkpoint.

1. Produce a release dry-run for the complete paired contract/workflow suite using the
   current A2 baseline and candidate, one attempt per provider/task initially.
2. Produce a separate calibration dry-run for A0-A3 on both providers, with repeat trials
   only for the W3 sentinel, failures, and material anomalies.
3. Show exact sessions, order, model/effort, timeouts, conservative estimated spend,
   configured maximum spend, and both manifest digests. Obtain explicit user approval
   for each manifest separately.
4. Execute only approved manifests. Capture a fresh same-window baseline and keep
   infrastructure failures out of task-failure counts.
5. Sample passes, failures, unusually efficient trials, and outliers in Harbor's viewer.
   Quarantine any unfair task before finalization and regrade compatible jobs after a
   verifier-only repair.
6. Sanitize and commit only reviewed finalized summaries. Build the dashboard from those
   files and verify the public artifact contains no raw trace material.
7. Pin the final commit and obtain one independent fresh-context review covering
   correctness, isolation, privacy, methodology, and the completion matrix below. Show
   its model/cost before dispatch; do not create per-task reviewers.

## Completion Matrix

| Approved design criterion | Evidence produced by |
| --- | --- |
| Harbor-native repo, no custom runner/fixture repo | Tasks 1-5 |
| Contract/workflow deterministic QA | Tasks 7, 9-12 and final checkpoint |
| Claude/Codex A0 and A2 isolation | Task 8 and release gate |
| Selectable A3/Superpowers interaction | Task 4 and calibration gate |
| Separate correctness/workflow/efficiency output | Tasks 6-7, 14-15 |
| Grouped premature-suite detection | Tasks 6-7 |
| Agent-free verifier regrade | Task 14 |
| Fail-closed raw/public boundary | Task 14 |
| Harbor viewer plus historical dashboard | Tasks 8 and 15 |
| Future Shelby seam only | Task 16 |
| Reviewed Claude/Codex baselines | paid release/calibration gate |
| One independent fixed-target review | final paid gate step 7 |

## Plan Self-Review Before Execution

- Confirm every source/interface above still exists at its pin before writing code; if a
  pin is unavailable, amend and reapprove the design instead of silently upgrading.
- Confirm every approved completion criterion maps to a task and observable command.
- Confirm Harbor owns agent execution, task parsing, ATIF, verification lifecycle,
  regrade, and local viewing; delete any duplicate implementation.
- Search the target repository for unfinished-marker tokens, mutable `latest` tags,
  unpinned Git refs, `harbor check`, trial-time package installs, secret-like values,
  personal paths, and raw result files.
- Confirm Python/JSON/TOML types agree for nullable telemetry, decimal budget values,
  reward dimensions, infrastructure states, and compatibility keys.
- Confirm `git diff --check` and the final deterministic checkpoint pass before any paid
  release manifest is proposed.
