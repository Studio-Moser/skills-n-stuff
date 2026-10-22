---
name: model-rubric
description: >-
  Creates or refreshes this developer's user-global model-routing rubric, which decides which model does which work, at ${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml (synced through the agents repo when present). Use when asked to set up or refresh the model rubric, when it is stale, or from Harness setup. Not for routing one task or configuring a project's issue tracker.
effort: medium
allowed-tools: "Bash Read Write Edit WebFetch"
disable-model-invocation: true
---

# Harness — Model Rubric

Owns creating and refreshing the per-developer model-routing rubric.

When invoked by `harness:setup`, treat its `command -v` inventory as current
machine evidence, including its native provider and callable executors. Return
the path, reviewed date, whether reconciliation ran, whether the file changed,
validation checks, and any blocker to Setup.

Read these references only when their step needs them:
[references/model-evidence.md](../../references/model-evidence.md) when
refreshing evidence,
[references/rubric-fallbacks.md](../../references/rubric-fallbacks.md) when
deriving fallback chains, and
[references/rubric-migration.md](../../references/rubric-migration.md) when
migrating an older rubric.

## 1. Check current state

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/rubric-path.sh" --check
```

- `set` → read the file's `reviewed:` stamp, listed models, and delegation limits.
  For an ordinary invocation, current (≤14 days, no superseded model, and positive
  `delegation.max_children`, `delegation.max_depth`, and
  `delegation.default_token_budget`) means report it and stop.
  When invoked by `harness:setup`, a current rubric does not stop this skill:
  first reconcile CLI-backed `capabilities` with Setup's inventory, show the
  changes, and derive `routing` fresh whenever reachability changed, because a
  route to an absent executor fails at dispatch. Preserve non-CLI subscription
  facts, taste, and billing semantics. Stop only if reconciliation and
  validation prove that no write is needed.
- `unset` → first-time setup.

## 1.5 Decide where the rubric physically lives

The read path is always `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`.
Storage depends on whether this developer has an agents repo:

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
if [ -d "$repo/.git" ]; then echo "repo"; else echo "plain"; fi
```

- **`repo`** → the folder belongs in the repo so it syncs across machines. Ensure
  `$config/studio-moser` is a symlink to `$repo/config/studio-moser`:
  - Already a correct symlink → nothing to do.
  - A real directory → move it into the repo, then link:
    `mkdir -p "$repo/config" && mv "$config/studio-moser" "$repo/config/studio-moser" && ln -s "$repo/config/studio-moser" "$config/studio-moser"`.
    Then ensure `$repo/.gitignore` contains `config/studio-moser/*.bak*`, and commit + push the repo.
  - Absent → `mkdir -p "$repo/config/studio-moser" && ln -s "$repo/config/studio-moser" "$config/studio-moser"`.
  `/harness:sync` verifies this link on every run (it is one of the tracked entries).
- **`plain`** → no repo on this machine; write to `$config/studio-moser/` as a real
  directory (`mkdir -p`). Everything else proceeds identically.

**Edit the file through the symlink when writing or refreshing.** Replacing the
link with a real file or folder, as an atomic replace does, severs sync silently.

## 2. Gather current model evidence

Use live sources because model availability, pricing, and benchmarks change.
Start with the existing fetcher:

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/fetch-model-data.sh"
```

- Exit 0 → use its normalized pricing and intelligence rows.
- Exit 3 → no `ARTIFICIAL_ANALYSIS_API_KEY`. Offer the developer the free
  Artificial Analysis models API at https://artificialanalysis.ai/data-api, but
  never ask them to paste a key into chat. If they accept, have them store it in
  their own terminal with `"$harness/scripts/agent-secrets.py" set
  ARTIFICIAL_ANALYSIS_API_KEY` (the fetch reads it from the secret store, so agents
  launched from GUI apps get it too) and `copy-to` their other machines. Never write
  or commit it. They may
  decline; use official provider documentation plus judgment, record that source,
  and offer the API again on the next refresh.
- Exit 4 or 5 → the configured fetch failed or its response shape yielded no
  usable row. Report it, retry once, then use official provider documentation
  plus judgment only if it still fails; record the failure reason under
  `sources`, without credential values.

Rows are keyed by `(model, effort)` because effort can move agentic quality more
than model tier. A row's benchmark records cost per successful task as
`mean_task_cost_usd / pass_at_1`, with both observed inputs kept so the division
can be checked. Benchmark efficiency applies only to delegated software
implementation routes. Read
[references/model-evidence.md](../../references/model-evidence.md) for the
DeepSWE and Slopalytics method before choosing candidate rows.

## 3. Establish developer-specific inputs

On first-time setup, ask one focused question at a time. Cover trust for hard
problems explicitly; do not infer it from benchmark scores:

1. **Capabilities and providers:** which native runtimes, providers, and CLIs are
   usable, and which subscriptions or metered APIs back them? Verify every
   CLI-backed claim with `command -v`. Codex counts as callable only after
   `codex-app-server.py check` proves the Codex App Server typed-error seam;
   a missing or incompatible seam removes Codex from reachability without
   creating a timed provider circuit. A Setup-provided inventory is evidence for this step,
   not permission to infer subscriptions. Carry any named authoring-provider
   exclusions from Setup through draft and final validation.
2. **Billing and efficiency semantics:** per provider, record whether billing is
   metered dollars or a flat subscription whose constraints are quota burn and
   latency. Use `efficiency` for the developer-specific synthesis of those
   constraints and the observed software-work evidence. In a completed row,
   `efficiency` is an integer from 1 through 10.
3. **Trust for hard problems:** identify models the developer trusts or refuses
   for ambiguous unsupervised work.
4. **Orchestration preference:** identify the trusted model the developer wants
   for top-level context, judgment, and delegation.
5. **Taste:** identify models whose UI, copy, and public API judgment needs the
   least editing.
6. **Working style:** decide whether latency matters for attended work and whether
   slow, high-quality rows are useful for unattended batches.
7. **Delegation limits:** choose the default maximum children, maximum nested depth,
   and bounded token budget for one delegated track. Recommend one child and one level
   unless the developer has a measured need for wider fan-out.

User-owned trust and preferences govern orchestration, taste, exploration, and
review; benchmark data is supporting evidence only. Do not treat an absent
preference as permission for benchmark efficiency to choose those routes. On an
ordinary data refresh, keep capabilities, taste, trust, orchestration preference,
working style, and billing semantics; update data-sourced axes and `reviewed:`
without re-interviewing.

## 4. Build or refresh the rubric

For first-time setup, copy
`skills/model-rubric/Default_Rubric.yml` from this plugin to the path returned by
`scripts/rubric-path.sh`, writing through the config-directory symlink when one
exists. Treat it only as a seed:

1. remove rows whose provider/executor is unavailable;
2. add current candidate `(model, effort)` rows for newly available providers;
3. fill `provider`, `trust`, and `efficiency` from verified capabilities and the
   developer interview; the seed's values are the house defaults, so keep them when
   the developer has no preference;
4. update data-backed `intelligence` and `benchmark`, preserving user-owned
   `taste`;
5. mark cross-provider CLI rows with `via: <cli>`;
6. derive the scalar `routing` primaries from the reachable rows; the seed carries
   commented house routing for cross-provider, Claude-only, and Codex-only
   capabilities, so offer the block matching this developer's capabilities as the
   default when every row it names is reachable;
7. record positive `delegation.max_children`, `delegation.max_depth`, and
   `delegation.default_token_budget` from the developer's limits;
8. derive an ordered `fallbacks.<route>` chain for each route using
   [references/rubric-fallbacks.md](../../references/rubric-fallbacks.md);
9. remove `seed: true`, replace `reviewed:` with today's date, and record the
   actual sources used.

For a Setup reconciliation, add or drop the affected model rows. For an ordinary
stale-data refresh, retain the reachable row set unless current evidence says a
model was superseded.

The routing table uses exact `<model>@<effort>` values:

- required `routing.orchestrator`: preferred trusted top-level row;
- required `routing.default`: ordinary delegated work;
- required `routing.quick`: short latency-sensitive delegated work;
- required `routing.review`: strongest trusted non-wasteful fixed-target reviewer;
- optional `routing.bulk`, `routing.explore`, `routing.batch`, `routing.taste`,
  and `routing.independent` when their semantics are reachable.

`orchestrator`, `default`, `quick`, and `review` are required. Keep
`routing.taste_min` as the developer's input for choosing a reachable
`routing.taste`; it is not itself a runtime route.

Derive and degrade from the observed capability inventory exactly as follows:

- Claude and Codex -> cross-provider routes are allowed but not required.
- Claude only -> derive required routes from Claude and omit `routing.independent`.
- Codex only -> derive required routes from Codex, omit `routing.independent`, and
  require no native-Claude explore route.
- one reachable model-effort row -> reuse it for required routes and omit optional routes.
- no reachable model-effort row -> block and do not write a valid-looking rubric.

Provider diversity is an optimization, not a setup prerequisite; every
single-provider setup must omit `routing.independent`. When present,
`routing.independent` must resolve to a provider distinct from
the provider of `routing.orchestrator` and from the provider of any named
authoring model.

`via` is executor metadata interpreted by Harness; consumers do not branch on it,
so the executor choice stays in one place.
Every eventual dispatch still passes model and effort explicitly.
When a resolved candidate equals the active `model@effort`, Harness executes in the
current context instead of delegating back to itself. Rubric routes select capability;
they do not force a child process.

Existing rubrics without `delegation` remain readable for routing compatibility, but
they are incomplete for Lite execution, the bounded delegation mode that relies on
those limits. On the next setup or rubric refresh, ask for the missing
limits and write them before reporting the rubric current.

The completed file has this shape:

```yaml
reviewed: YYYY-MM-DD
sources: [source-name]
capabilities:
  claude: true
  codex: true
models:
  - name: model-name
    effort: high
    provider: anthropic
    intelligence: 8
    taste: 8
    trust: trusted
    efficiency: 8
    benchmark: { suite: deepswe, version: "X.Y", observed: YYYY-MM-DD, pass_at_1: 0.5, mean_task_cost_usd: 1.0, cost_per_success_usd: 2.0, mean_output_tokens: 1000, mean_steps: 10, mean_duration_seconds: 60 }
  - name: backup-model
    effort: high
    provider: openai
    via: codex
    intelligence: 8
    taste: 8
    trust: trusted
    efficiency: 8
routing:
  orchestrator: model-name@high
  default: model-name@high
  quick: model-name@high
  review: model-name@high
fallbacks:
  orchestrator: [backup-model@high]
  default: [backup-model@high]
  quick: [backup-model@high]
  review: [backup-model@high]
delegation:
  max_children: 1
  max_depth: 1
  default_token_budget: 80000
```

Build the complete candidate document at a local temporary path. Show the complete
draft to the developer, including the fallback chains, so they can correct it;
always show the fallback chains before writing. Developer edits override seed judgment. Validate the draft with
the same native-provider and callable-executor inventory used for derivation:

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/resolve-route.py" validate \
  --rubric "$DRAFT_RUBRIC" \
  --native-provider "$HARNESS_NATIVE_PROVIDER" \
  --executors "$HARNESS_EXECUTORS" \
  --authoring-providers "$HARNESS_AUTHORING_PROVIDERS"
```

This command takes no health-state path. Require exit 0 and
`{"status":"valid"}` before writing through the config-directory symlink. A
missing resolver, `python3`, or `yq`, malformed output, or blocked result stops
the write; do not reproduce or guess the resolver's semantics. The validator is
the single structural gate. Validate both `provider` and `via` reachability for
every routed row through it, against the inventory used for derivation, and
block or rederive when either is unavailable. It also checks that every route
names an exact row, rejects `routing.independent` when its provider matches
either the orchestrator's provider or a named authoring provider, and enforces
`routing.taste_min`, fallback-chain provider uniqueness, and positive delegation
limits. The optional
`--authoring-providers "$HARNESS_AUTHORING_PROVIDERS"` input uses the same
CSV/JSON-list contract as request selection; the validator always enforces the
persistent `routing.orchestrator` provider boundary even when that optional list
is empty. Never write a credential, secret-bearing profile, absolute machine
path, or temporary evidence into the rubric.

To migrate a rubric that lacks `routing.orchestrator`, still scores `cost`, or
still contains `routing.fallback`, read
[references/rubric-migration.md](../../references/rubric-migration.md) first.

A running agent cannot replace itself. `routing.orchestrator` guides a future
top-level session when its host supports explicit model selection; it never
causes the current setup agent to relaunch or hand off itself.

## 5. Confirm

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/rubric-path.sh" --check
```

Expected: `set`. Report the path and the `reviewed:` date.

Then check what the validator does not: `seed: true` and `cost: null` are
absent; `orchestrator`, `default`, `quick`, and `review` routes are present;
every benchmark division is consistent within rounding; every completed model
row's `efficiency` is an integer from 1 through 10; and no `routing.fallback`
remains. Optional unavailable routes are omitted. A Setup invocation reports
`reconciled: true` even when the file did not change.
