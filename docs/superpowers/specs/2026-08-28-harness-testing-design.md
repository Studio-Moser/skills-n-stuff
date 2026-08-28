# Harness Testing Design

**Date:** 2026-08-28
**Status:** Approved

## Purpose

Create a public `Studio-Moser/harness-testing` repository that measures whether changes
to agent instructions, skills, plugins, tools, and routing improve software-development
outcomes without introducing unnecessary tests, plans, reviews, subagents, tool calls,
time, tokens, or cost.

The benchmark evaluates complete agent harnesses, not models in isolation. Its initial
subjects are Claude Code and Codex running stock, Superpowers, Studio Harness, and
combined configurations. Shelby is not connected in the initial release, but the
architecture preserves a documented custom-agent seam for it.

All trials run against versioned test projects. They never run against Studio Moser's
live repositories, user-global agent configuration, or Shelby memory.

## Decision Summary

1. Use Harbor as the evaluation runner, sandbox, task format, agent adapter layer,
   trajectory format, result format, and local trial viewer.
2. Store locally authored frozen test projects inside Harbor tasks in the public
   repository. Resolve the capability pack from its immutable upstream commit into an
   ignored local cache; do not create a companion fixtures repository or vendor
   third-party task content without an in-tree license.
3. Use Harbor RewardKit and separate verifiers for deterministic outcome grading and
   policy checks. Use ATIF trajectories for diagnostic workflow and efficiency metrics.
4. Keep correctness, workflow compliance, and efficiency as separate dimensions. Do
   not produce a composite score that can hide a correctness regression.
5. Run cheap deterministic task and scorer validation continuously. Run paid agent
   trials only at explicit smoke, checkpoint, release, calibration, or research gates.
6. Use Harbor regrading when only a verifier or scorer changes so the recorded agent
   execution is not repeated.
7. Use Harbor's viewer for local trajectory inspection and a sanitized static dashboard
   for longitudinal public results.
8. Exclude agent-belt, OpenBench, and a custom runner from the initial runtime. They may
   remain methodology references.

## Goals

1. Detect correctness regressions caused by harness, skill, plugin, or prompt changes.
2. Detect testing churn, especially full-suite runs after small edits or between TODOs
   in a grouped implementation.
3. Measure accepted-task runtime, tokens, cost, tool calls, turns, and workflow overhead.
4. Compare Claude Code and Codex under equivalent, pinned candidate configurations.
5. Make benchmark tasks stable, repeatable, auditable, and safe to run publicly.
6. Provide a fast local smoke path and a deliberate, budget-visible comprehensive path.
7. Preserve a clean future integration seam for Shelby's Rust agent implementation.
8. Show correctness and efficiency trends over time without publishing private traces,
   hidden verifier logic, reasoning, credentials, or user repository contents.

## Non-Goals

- Benchmark frontier models generally or publish a universal coding-agent leaderboard.
- Reimplement Harbor execution, sandboxing, task packaging, trajectory capture, grading,
  registry, job storage, or result viewing.
- Exercise Studio Moser's live projects, personal agent configuration, or Shelby memory.
- Connect Shelby in the initial implementation.
- Cover native Swift or macOS application development.
- Enforce one exact sequence of tool calls for a successful implementation.
- Treat fewer tests, fewer tokens, or faster execution as better when correctness fails.
- Launch live model trials after every implementation TODO or every benchmark task edit.

## Best-Practice Basis

This design follows the common agent-evaluation model used by Anthropic, OpenAI, and
Harbor:

- A task defines an instruction, environment, and success criteria.
- A trial is one stochastic attempt at a task.
- The outcome is the final state of the environment.
- A trajectory records the actions taken during the trial.
- Deterministic graders are preferred when the outcome can be executed or inspected.
- Multiple trials are used when a release decision depends on stochastic behavior.
- Human transcript review periodically checks whether graders are fair and still
  measure the intended behavior.

Outcome grading is primary. Anthropic specifically cautions that exact tool-call paths
are brittle because agents can find valid approaches that the evaluator did not
anticipate. The benchmark therefore uses trajectory rules as:

1. hard failures only for explicit integrity or task-policy violations;
2. workflow-compliance signals for required or forbidden gates; and
3. diagnostic efficiency measurements for all other behavior.

OpenAI's continuous-evaluation guidance is implemented as continuous deterministic
validation plus appropriately gated live trials. It does not mean running every paid
agent and task combination after each edit.

## Architecture and Ownership

```text
Harness Testing repository
  task packs + experiment arms + policy + sanitized exports + dashboard
            |
            v
Harbor
  isolated execution + Claude/Codex adapters + trials + ATIF + RewardKit + results
            |
            +--------------------------+
            |                          |
            v                          v
Candidate harness bundles        Frozen task containers
stock / Superpowers / Studio      React / TypeScript / HTML / Rust
Harness / combined
            |
            v
Sanitized longitudinal export
            |
            v
Static GitHub Pages dashboard

Future Shelby integration -> Harbor custom installed-agent or external-agent boundary
```

### Harness Testing owns

- Task instructions and versioned fixture projects.
- Reference solutions and deterministic verifiers.
- Dataset composition and task-pack metadata.
- Experiment arms and the exact harness bundles assigned to them.
- Change-class verification envelopes and recognized project commands.
- Churn classification and baseline-relative efficiency analysis.
- Trial cadence, budget caps, release policy, and dry-run previews.
- Sanitized result export, historical result retention, and the public dashboard.
- Benchmark QA and periodic human transcript-audit policy.

### Harbor owns

- Task schema and local-dataset resolution.
- Container and network isolation.
- Agent installation and execution.
- Claude Code and Codex adapters.
- The future custom-agent interface used by Shelby.
- Skill injection and provenance recording.
- ATIF trajectory capture.
- RewardKit verifier execution.
- Trial/job storage, regrading, and the local results viewer.

### Candidate repositories own

- Superpowers, Studio Harness, and their distributable skills, plugins, instructions,
  tools, and configuration.
- Their own tests and release processes.
- No benchmark-specific branches or behavior.

Harness Testing consumes immutable commits or release tags from candidate repositories.
It does not copy and silently modify candidate bundles.

## Repository Shape

The public repository follows current Harbor task and dataset conventions rather than
the unmaintained `harbor-framework/benchmark-template` repository.

```text
harness-testing/
  tasks/
    contract/
    workflow/
  arms/
    Definitions.toml
    materialized/ (ignored)
  policy/
    command-classification.*
    verification-envelopes.*
  scorer/
    rewardkit criteria and deterministic tests
  images/
    pinned agent and verifier base images
  runs/
    Profiles.toml and checked-in run policy, not credentials or raw private jobs
  src/harness_testing/
    thin arm, run, validation, regrade, and result adapters
  dashboard/
    static site and sanitized data contract
  results/
    sanitized, finalized public result snapshots
  docs/
    task authoring, methodology, interpretation, and release policy
```

Harbor treats a local dataset as a directory whose immediate children are valid task
directories. Contract and workflow task directories are therefore flat beneath their
pack directory; checked-in Harbor `JobConfig` YAML selects those paths and task names.
There is no benchmark-owned local `dataset.toml` format.

Each locally authored Harbor task contains:

- `instruction.md` with one observable assignment;
- `task.toml` using Harbor schema `1.4`, with a stable `org/name` identity and task
  package version;
- an isolated `environment/` containing the frozen project;
- an optional `solution/solve.sh` for oracle validation; and
- `tests/` containing a separate verifier environment and its checks.

Dependencies and the selected Claude Code and Codex CLI versions are pinned and baked
into task or verifier base images so isolated trials do not reinstall an agent for every
attempt. Environment setup may use public networking only while building those pinned
images. Agent execution switches to a provider-specific allowlist, and the separate
verifier runs with `network_mode = "no-network"`.

## Evaluation Packs

### Contract pack

The contract pack converts the existing Studio Harness behavioral evals into Harbor
tasks. It verifies that candidate bundles preserve their declared boundaries and
workflow contracts. The initial pack includes the eight existing Harness eval scenarios
and selected setup, routing, evidence, change-class, and optional-Shelby cases that can
be evaluated without a live project or memory store.

Contract tasks grade observable behavior or artifacts. They do not require the agent to
repeat specific prose from a skill.

### Workflow pack

The workflow pack measures representative Studio Moser development work:

| ID | Stack | Assignment class | Primary signal |
| --- | --- | --- | --- |
| W1 | React/TypeScript | Polish | Correct visual change without unrelated logic or a full-suite run |
| W2 | React/TypeScript | Small bug | Root-cause fix with one targeted regression check |
| W3 | React/TypeScript | Grouped TODOs | Several independent edits followed by one final comprehensive pass |
| W4 | React/TypeScript | Feature | Cross-file behavior, focused development checks, final release gate |
| W5 | Static HTML/CSS | Polish | Copy/style result with browser- or DOM-level proof only |
| W6 | Static HTML/CSS/JS | Small behavior | Interaction and accessibility outcome with targeted proof |
| W7 | Static web | Grouped TODOs | Several page updates without repeated global validation |
| W8 | Rust | Small parser bug | Correct edge-case behavior with a focused test |
| W9 | Rust workspace | Feature | Cross-crate behavior with targeted checks and one final workspace pass |

Tasks use small purpose-built projects that are realistic enough to expose tool and test
selection decisions but cheap enough for repeated trials. They must not be copied from
private Studio Moser client repositories.

### Capability pack

The capability pack uses DeepSWE v1.1 at commit
`8cae5984d5dd0ee37445beff0e928dc10c331116`. Its six-task cohort is:

| Language | Difficulty band | Task ID |
| --- | --- | --- |
| TypeScript | easier | `happy-dom-abort-pending-body-reads` |
| TypeScript | harder | `quill-shared-toolbar-focus` |
| JavaScript | easier | `yjs-map-conflict-detection` |
| JavaScript | harder | `katex-multicolumn-array-spans` |
| Rust | easier | `wasmi-trap-coredumps` |
| Rust | harder | `pest-character-class-coalescing` |

The pinned DeepSWE tree does not contain a license file, although GitHub currently
classifies the repository as Apache-2.0. Harness Testing therefore does not redistribute
the task files. A deterministic materializer fetches only the named directories at the
pinned commit into an ignored cache, records the original digests, and derives local
images that preinstall the pinned provider CLIs. It preserves task instructions,
solutions, verifiers, and starting repositories byte-for-byte. Any generated Harbor
compatibility metadata and derived-image digest are recorded separately from the
upstream task digest.

This subset is a deliberate, manually triggered research lane rather than ordinary CI.

## Experiment Arms

The benchmark defines four candidate arms:

| Arm | Configuration |
| --- | --- |
| A0 | Stock provider agent with benchmark-required configuration only |
| A1 | Stock agent plus Superpowers |
| A2 | Stock agent plus Studio Harness |
| A3 | Stock agent plus Superpowers and Studio Harness |

Each arm can run with Claude Code or Codex. Every run records:

- provider agent and version;
- model and reasoning-effort setting;
- candidate repository URL, commit, and content digest;
- injected skill provenance;
- task and dataset digests;
- Harbor and RewardKit versions;
- environment image digest;
- trial count, concurrency, timeout, and network policy; and
- scorer and dashboard schema versions.

Arms use each provider's real distribution path:

| Provider | Superpowers delivery | Studio Harness delivery |
| --- | --- | --- |
| Claude Code | Official plugin seed, including its `SessionStart` hook | Official Studio Moser plugin seed plus a public, benchmark-safe project instruction file |
| Codex | Official native Codex plugin cache and marketplace config; the package is skills-only because its manifest has no hook | Public Harness skills in `.agents/skills` plus the corresponding project `AGENTS.md` instructions |

The benchmark does not pretend those provider packages have identical surfaces.
Provenance and the dashboard label Claude's hook-capable Superpowers bundle separately
from Codex's skills-only bundle.

The complete eight-cell matrix is a calibration experiment, not the default change
workflow. Ordinary Studio Harness work compares the current A2 baseline with an A2
candidate. A3 is included only when the change could interact with Superpowers.

## Isolation and Fair Comparison

Every trial receives:

- a fresh task container;
- a fresh agent/configuration home inside the sandbox;
- only the arm's pinned instructions, skills, plugins, tools, and allowed credentials;
- no live repository mounts;
- no host user-global instructions or skills;
- no Shelby memory or project scope;
- no prior trial worktree, Git history, cache, or result artifacts; and
- a separate verifier environment.

Harbor v0.22.0 installs agents during environment setup and switches network policy at
the agent phase. Locally authored tasks use a no-network runtime baseline with the exact
CLIs already present in pinned images, a provider API allowlist for `agent.run()`, and a
no-network separate verifier. Capability tasks keep DeepSWE's no-network runtime and use
derived images with the same pinned CLIs already installed.

Authentication needed to invoke Claude Code or Codex is injected through Harbor's
supported secret mechanism and is never written to task, result, or dashboard files.

Candidate comparisons use paired task sets and interleave baseline and candidate trials
to reduce time-of-day and provider effects. A release run captures a fresh baseline in
the same window; historical results are for trends, not a substitute control.

Infrastructure failures are reported separately from task failures. One automatic retry
is allowed for a classified infrastructure failure. Task failures are not automatically
rerun until green.

## Verification Envelopes

Each workflow task declares a change class and an allowed verification envelope. The
envelope describes observable gates without requiring an exact implementation path.

### Polish

- Correct artifact and scope are required.
- One direct visual, DOM, compile, or local rendering check is sufficient.
- A repository-wide suite before the batch checkpoint is a churn signal and may be an
  explicit task-policy violation when the prompt forbids it.
- No test creation is required for a trivial style or copy edit.

### Small

- One focused regression check is required for new behavior or a bug fix.
- The task's final checkpoint may require the smallest relevant project suite.
- Repeating that suite without an intervening relevant change is churn.

### Grouped

- Focused checks may run while individual items are implemented.
- A comprehensive pass runs once after the grouped work is complete.
- A comprehensive pass between TODOs is the primary premature-testing signal.

### Feature

- New behavior receives focused executable checks during implementation.
- The relevant complete suite runs at the final checkpoint.
- Additional suites are justified only by a changed dependency or observed failure.

### No-op and already-satisfied tasks

- The correct result may be no source change.
- Unnecessary edits, tests, plans, or generated files count against efficiency and scope.
- The verifier distinguishes legitimate no-op behavior from failure to attempt the task.

## Scoring Model

### Correctness

Correctness is the primary Harbor reward and is determined from the final workspace or
published task artifacts using deterministic execution and inspection wherever possible.
It includes:

- requested behavior;
- regression protection appropriate to the task;
- build/type/lint health when relevant;
- scope and protected-file integrity; and
- absence of verifier, test, or result tampering.

Only a correct trial participates in comparative efficiency claims.

### Workflow compliance

Workflow compliance is a separate reward dimension. It includes only explicit policy
that can be evaluated fairly:

- a required focused regression check was omitted;
- a comprehensive suite was explicitly forbidden before the checkpoint but was run;
- the agent modified protected tests, verifier inputs, or benchmark metadata;
- the agent escaped the allowed workspace or network policy; or
- a required final gate was omitted.

The benchmark does not fail a correct trial merely because the agent used a plan,
reviewer, subagent, worktree, or different valid command sequence. Those are measured as
diagnostics unless the task instruction establishes a specific boundary.

### Efficiency

Efficiency remains a vector, not a reward that can compensate for incorrect work:

- elapsed agent time and verifier time;
- prompt, completion, reasoning, and cached tokens when reported;
- execution cost when reported by the provider/agent;
- tool calls, turns, commands, and command wall time;
- targeted, package, workspace, and comprehensive test invocations;
- test wall time and share of total time;
- comprehensive tests before later source edits;
- exact or semantically duplicate checks without an intervening relevant change;
- plans, reviews, subagents, worktrees, and context/checkpoint events;
- files changed, generated files, and diff size; and
- retries, timeouts, and infrastructure errors.

Unknown provider telemetry is stored as `null`; it is never estimated or silently
treated as zero.

Efficiency comparisons are baseline-relative and reported only among correct paired
trials. Absolute structural violations remain visible regardless of baseline behavior.

### Command classification

Each task declares recognized commands and their scope using benchmark-owned policy:

- direct check;
- targeted test;
- package or crate test;
- workspace/repository comprehensive suite;
- lint, typecheck, build, browser, or formatting gate; and
- unknown command.

Classification operates on ATIF tool calls and executable task metadata. Unknown
commands remain visible for human review rather than being guessed into a favorable
class.

RewardKit programmatic criteria live in top-level `tests/reward/`, `tests/workflow/`,
and `tests/efficiency/` directories and therefore emit `{reward, workflow, efficiency}`.
`reward` is correctness/integrity and is labelled **Correctness** in reports.
`efficiency` is only the absolute policy dimension (for example, a forbidden premature
suite run); the full efficiency vector remains raw diagnostic data and is never collapsed
into a composite ranking.

## Benchmark Task QA

Every task must pass these deterministic gates before it can consume model budget:

1. The repository's deterministic validator loads `task.toml`, checked-in job YAML, and
   ATIF fixtures through Harbor v0.22.0's Pydantic models and trajectory validator.
2. Agent and verifier container images build from pinned inputs.
3. The oracle solution passes the verifier.
4. The untouched project fails the task verifier when the task is not a legitimate
   no-op case.
5. The verifier runs in a separate environment and cannot be modified by the agent.
6. Canned ATIF trajectories prove command classification and churn metrics.
7. A deliberate near-miss proves the verifier rejects incomplete implementations.
8. A deliberate adversarial attempt checks for reward-hacking or test-tampering paths.
9. Tests execute behavior instead of depending on fragile source-string matches.
10. A human reviewer confirms the instruction, oracle, verifier, and verification
    envelope describe the same task.

Terminal-Bench runs build, oracle, and no-op validation automatically while reserving
agent and cheat trials for maintainer-triggered workflows. Harness Testing adopts that
cost boundary rather than copying Terminal-Bench's full infrastructure.

Periodic transcript audits sample passes, failures, unusually efficient trials, and
outliers. If a valid solution is rejected or an invalid solution passes, the task is
quarantined until its verifier is corrected and prior compatible trials are regraded.

## Run Cadence and Budget Control

### Validate

- Runs on every benchmark repository pull request.
- Uses no agent model.
- Runs schemas, static checks, scorer tests, container build as affected, oracle, no-op,
  and deterministic verifier tests.

### Smoke

- Runs current versus candidate on a small sentinel set.
- Uses one trial per task/arm/provider.
- Intended for local iteration after a coherent candidate change.

### Checkpoint

- Runs current versus candidate on affected packs.
- Uses one paired trial initially.
- Runs when the developer requests commit, PR, checkpoint, or final QA.
- Does not run between implementation TODOs.

### Release

- Runs the complete paired contract and workflow suites.
- Adds repeat trials for sentinels, failures, and material anomalies.
- Requires a fresh same-window baseline.
- Publishes a finalized sanitized result only after task and infrastructure review.

### Calibration

- Runs A0 through A3 for both Claude Code and Codex.
- Uses enough repeated trials to expose meaningful variance.
- Runs manually when establishing a baseline, changing the benchmark methodology, or
  evaluating Superpowers interaction.

### Research

- Runs the pinned DeepSWE subset.
- Is manual and budgeted.
- Does not block ordinary Harness changes unless explicitly selected as a release gate.

### Regrade

- Runs when verifier, scorer, or classification policy changes without changing the task
  instruction or recorded agent artifacts.
- Uses Harbor's immutable regrade output; it never overwrites the source job.
- Requires fresh trials only when the changed oracle needs evidence absent from the old
  artifacts or trajectory.

Before any live run, a dry-run report shows the exact providers, arms, tasks, trials,
estimated session count, timeouts, and configured budget caps. No implicit command runs
the full matrix.

## Results, Privacy, and Publication

Raw Harbor job directories remain local or in access-controlled storage because they
can contain trajectories, model reasoning, command output, repository artifacts, and
configuration details.

A fail-closed sanitizer emits the only files eligible for the public `results/` tree.
Its explicit schema allowlists:

- finalized run identity and timestamp;
- provider agent, model, and pinned candidate identifiers;
- task and dataset IDs/digests;
- correctness and workflow dimensions;
- efficiency counters and durations;
- token and cost aggregates when available;
- infrastructure status; and
- links to public source commits and methodology versions.

It excludes raw prompts beyond the public task instruction, trajectories, reasoning,
tool output, environment variables, auth material, home-directory paths, unpublished
candidate content, and arbitrary Harbor `extra` fields.

Results with different task, dataset, scorer, environment, provider-agent, or material
methodology versions are not placed on one continuous trend line without an explicit
compatibility declaration. The dashboard visibly splits incomparable series.

## Dashboard

Harbor's built-in viewer is the source for local job inspection, trajectory playback,
token/timing analysis, verifier output, and job comparisons. Harness Testing does not
rebuild those capabilities.

The public dashboard is a static longitudinal report generated from sanitized result
JSON and deployed to GitHub Pages. Its initial pages are:

1. **Latest:** most recent finalized comparison and release decision.
2. **Trends:** correctness, workflow violations, runtime, tokens, cost, and testing churn
   across compatible runs.
3. **Comparisons:** current versus candidate by provider and experiment arm.
4. **Task matrix:** per-task correctness and efficiency with failure and infra states.
5. **Run detail:** pinned provenance, methodology, metrics, and public artifacts.
6. **Quality versus efficiency:** correct trials only, without a composite ranking.

Observable Framework and Observable Plot are the preferred thin rendering layer because
they produce a static data-driven site without a backend. Before the implementation plan
commits to their APIs, it must read their current official project structure, data-loader,
deployment, and licensing guidance. If their current supported path conflicts with this
design, the plan must prefer Harbor's supported result/leaderboard components or another
existing static renderer rather than inventing a dashboard framework.

The approved implementation pins Observable Framework `1.13.4` and Observable Plot
`0.6.17`. The site uses Framework's supported `src/` project root, static data loaders,
and `dist/` output with Observable's documented GitHub Pages Actions flow. Framework's
current `base` option affects only a custom 404 page, so the dashboard does not misuse it
as a project-site prefix. The built artifact must prove navigation and assets work at the
repository's Pages URL. GitHub Actions are pinned by full commit SHA and receive only the
least privileges needed to build and deploy Pages.

## Future Shelby Integration

Shelby is outside the first implementation. The current Rust direction is a
provider-neutral runtime with typed, append-only turn and tool events, cancellation, and
durable state. No private Shelby source is copied into this public repository. The
repository reserves these requirements for a later adapter:

- implement Harbor's current custom external-agent or installed-agent interface without
  forking Harbor;
- install the Rust Shelby runtime inside the same isolated task environment;
- accept the same task instruction, timeout, network, artifact, and secret boundaries;
- emit a valid ATIF trajectory or a lossless supported Harbor equivalent;
- report available token, cost, timing, tool, subagent, and checkpoint events;
- accept arm-specific skills, tools, instructions, and configuration through pinned
  benchmark inputs; and
- run without Shelby's production memory or user project data unless a future benchmark
  explicitly supplies synthetic memory as part of a task fixture.

The seam is a documented future `BaseInstalledAgent`: `install()`, headless `run()`,
`populate_context_post_run()`, and `SUPPORTS_ATIF = True`. A future adapter maps Shelby's
native runtime events into ATIF v1.7 and populates Harbor `AgentContext`; the initial
release contains a contract document and sample manifest only, not executable Shelby
code.

Claude, Codex, and Shelby results are comparable only when they use the same task and
verifier versions and expose sufficient telemetry for the dimension being compared.

## Integration Conformity Gate

The implementation plan may be written only after checking the current authoritative
documentation, source, tests, schemas, and examples for every selected integration.
At minimum it must resolve and pin:

1. Harbor stable release, task schema, dataset manifest, agent configuration kwargs,
   environment provider, network policy, secrets, skills, artifacts, ATIF, RewardKit,
   regrade, result files, and viewer behavior.
2. Claude Code's supported headless invocation, configuration home, plugin/skill
   discovery, authentication, result/usage output, and sandbox interaction.
3. Codex's supported headless invocation, `AGENTS.md` and skill discovery, configuration
   home, authentication, result/usage output, and sandbox interaction.
4. Superpowers' exact release contents, mandatory skill routing, planning, TDD,
   verification, review, worktree, and subagent instructions.
5. Studio Harness' current distributable plugin/skill surface, setup/sync output,
   change-class rules, model routing, optional Shelby behavior, and test commands.
6. DeepSWE's current Harbor dataset identity, stable task IDs, task licenses, environment
   requirements, and supported subset selection.
7. Observable Framework, Observable Plot, GitHub Pages, and any Harbor leaderboard code
   used by the public dashboard.

For each integration, the plan must name exact supported APIs, files, schemas, and
commands. It must prefer the upstream mechanism and add only the smallest adapter needed
to connect it. An unresolved integration is not deferred as an implementation TODO.

If current source contradicts this design, amend and reapprove the affected design
section before implementation. Stop rather than creating a fork or parallel framework
to preserve an invalid assumption.

## Resolved Integration Pins

The implementation plan is based on these inspected releases and supported surfaces:

| Integration | Pin | Supported surface used |
| --- | --- | --- |
| Harbor | `v0.22.0`, commit `4407eb5227a2ff4f0d3f16b2eb48849382fdf276` | Task schema 1.4, top-level `JobConfig`, Docker mounts/network phases, built-in `claude-code` and `codex`, ATIF v1.7, artifacts, separate verifiers, regrade, viewer |
| RewardKit | `0.1.7` | Folder-based programmatic criteria and `reward-details.json`; no model judge |
| Claude Code | `2.1.236` initial baseline | `claude --print --verbose --output-format=stream-json`, `--settings`, `CLAUDE_CONFIG_DIR`, read-only `CLAUDE_CODE_PLUGIN_SEED_DIR` |
| Codex CLI | `0.150.1` initial baseline | `codex exec --json`, `CODEX_HOME`, native `config.toml`, native plugins, `.agents/skills`, `AGENTS.md` |
| Initial model baseline | Claude `claude-sonnet-4-6`; OpenAI `gpt-5.6-terra`; effort `high` | Fixed model IDs and same-window baseline/candidate comparisons; model changes create a new compatibility series |
| Superpowers | `v6.3.0`, commit `b36e0829c6d0140e93cfef2ca599b1b07d4a7797` | Provider-native manifests; Claude `SessionStart` hook; Codex skills-only package |
| Studio Harness | `0.8.1`, source commit `ff8852e737a43a7e23f2cad423905f9361fde8ae` | Claude plugin, public skills, public house rules and project baseline, generated Codex instruction/skill delivery model |
| DeepSWE | v1.1 content commit `8cae5984d5dd0ee37445beff0e928dc10c331116` | Six exact task directories resolved by commit; no vendoring |
| Observable Framework / Plot | `1.13.4` / `0.6.17` | Static loaders, `src/`, `dist/`, GitHub Pages |
| Computer-use fixture | Python MCP SDK `2.1.1`; Playwright `1.62.0`; image manifest `sha256:aa81288e738725378becba5b3e06cb0f3a7f012a610e87e8d767a090ea3f740d` | Task-only streamable-HTTP MCP sidecar, real local browser interaction, protected event/screenshot collection |

Harbor's root `harbor check` command invokes a model-based task-quality checker. It is
not part of `validate`, CI, or automatic checkpoints. Harbor runs use `harbor run -c`,
oracle/no-op validation uses `harbor trial start`, regrades use `harbor job regrade`, and
local inspection uses `harbor view`.

## Failure Handling

- Distinguish agent task failure, verifier failure, task-definition failure, provider
  failure, authentication failure, rate limiting, timeout, and sandbox failure.
- Never convert missing telemetry into a passing efficiency result.
- Never publish an incomplete or unreviewed run as a finalized baseline.
- Quarantine invalid tasks and retain the reason in public methodology metadata.
- Preserve the original job and result when regrading.
- Make task, scorer, or methodology version breaks visible instead of rewriting history.
- Stop a run at its declared cost, time, or trial cap and report partial coverage.

## Completion Criteria

The initial Harness Testing release is complete when:

1. The public repository uses current Harbor task and dataset formats without a custom
   runner or companion fixtures repository.
2. Contract and workflow packs pass schema, build, oracle, no-op, verifier, canned-trace,
   and adversarial QA.
3. Claude Code and Codex can run A0 and A2 in isolated tasks with pinned provenance.
4. A3 demonstrates that Superpowers interaction can be selected without being imposed
   on ordinary Studio Harness comparisons.
5. Correctness, workflow compliance, and efficiency are separately exported and shown.
6. A deliberate grouped-task trial detects a comprehensive suite run between TODOs.
7. A verifier change can regrade a prior job without rerunning its agent phase.
8. Raw jobs fail the public sanitizer while allowlisted finalized summaries pass it.
9. The local Harbor viewer and public historical dashboard both work from the same
   recorded job results for their respective audiences.
10. The repository documents, but does not implement, the future Shelby adapter seam.
11. A full calibration run produces reviewed baselines for Claude Code and Codex.
12. An independent fixed-target review finds no unresolved correctness, isolation,
    privacy, or methodology blocker.

## Sources

- [Anthropic: Demystifying evals for AI agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)
- [OpenAI: Evaluation best practices](https://developers.openai.com/api/docs/guides/evaluation-best-practices)
- [Harbor documentation](https://www.harborframework.com/docs)
- [Harbor agents and custom-agent interfaces](https://www.harborframework.com/docs/agents)
- [Harbor task structure and separate verifiers](https://www.harborframework.com/docs/tasks)
- [Harbor datasets and publishing](https://www.harborframework.com/docs/datasets/publishing)
- [Harbor skill injection and provenance](https://www.harborframework.com/docs/run-jobs/skills)
- [Harbor RewardKit](https://www.harborframework.com/docs/rewardkit)
- [Harbor regrading](https://www.harborframework.com/docs/run-jobs/regrade)
- [Harbor job results and viewer](https://www.harborframework.com/docs/run-jobs/run-evals)
- [Harbor Agent Trajectory Interchange Format](https://github.com/harbor-framework/harbor/blob/main/rfcs/0001-trajectory-format.md)
- [Terminal-Bench task review automation](https://github.com/harbor-framework/terminal-bench/blob/main/docs/TASK_REVIEW_AUTOMATION.md)
- [Harbor benchmark-template deprecation notice](https://github.com/harbor-framework/benchmark-template)
- [agent-belt](https://github.com/jfrog/agent-belt)
- [Claude model IDs and versioning](https://platform.claude.com/docs/en/about-claude/models/model-ids-and-versions)
- [Claude Code CLI reference](https://docs.anthropic.com/en/docs/claude-code/cli-usage)
- [OpenAI model catalog](https://platform.openai.com/docs/models)
- [Superpowers v6.3.0 source](https://github.com/obra/superpowers/tree/v6.3.0)
- [Studio Harness pinned source](https://github.com/Studio-Moser/skills-n-stuff/tree/ff8852e737a43a7e23f2cad423905f9361fde8ae/plugins/harness)
- [DeepSWE pinned source](https://github.com/datacurve-ai/deep-swe/tree/8cae5984d5dd0ee37445beff0e928dc10c331116)
- [Observable Framework project structure](https://observablehq.com/framework/project-structure)
- [Observable Framework configuration](https://observablehq.com/framework/config)
- [Observable Framework GitHub Pages deployment](https://observablehq.com/framework/deploying)
- [GitHub Pages custom workflows](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
