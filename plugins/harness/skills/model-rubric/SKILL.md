---
name: model-rubric
description: >-
  Create or refresh this developer's user-global model-routing rubric — the file
  that decides which model does which work (cheap models for bulk/mechanical work,
  the strongest for ambiguous or taste-sensitive work). Lives at
  ${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml, one per
  developer; on machines with an agents repo the folder is a symlink into it,
  so the rubric syncs across machines. Trigger: "set up my model rubric",
  "refresh my rubric", "which model should agents use", "my rubric is stale",
  or /harness:model-rubric.
  Do NOT use to route a specific task right now (just read the rubric), or to
  configure a project's issue tracker (that's /pm:setup). Harness setup invokes
  this skill internally after discovering the current machine's capabilities.
effort: medium
allowed-tools: "Bash Read Write Edit WebFetch"
---

# Harness — Model Rubric

Owns creating and refreshing the per-developer model-routing rubric.

When invoked by `harness:setup`, treat its `command -v` inventory as current
machine evidence. A current rubric does not stop this skill: first reconcile
CLI-backed `capabilities`, show the changes, and derive `routing` fresh whenever
reachability changed. Do not retain a route to an executor known to be absent.
Preserve non-CLI subscription facts, taste, and cost semantics. Return the path,
reviewed date, whether reconciliation ran, whether the file changed, validation
checks, and any blocker to Setup.

## 1. Check current state

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/rubric-path.sh" --check
```

- `set` → read the file's `reviewed:` stamp and listed models. For an ordinary
  invocation, current (≤14 days, no superseded model) means report it and stop.
  When invoked by `harness:setup`, a current rubric does not stop this skill:
  continue through capability reconciliation, then stop only if reconciliation
  and validation prove that no write is needed.
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
  `/harness:sync` verifies this link on every run (it is one of the eight tracked entries).
- **`plain`** → no repo on this machine; write to `$config/studio-moser/` as a real
  directory (`mkdir -p`). Everything else proceeds identically.

**Never replace the symlink with a real file/folder when writing or refreshing** — edit
the file through the link. An atomic-replace of the directory severs sync silently.

## 2. Gather current model evidence

Use live sources because model availability, pricing, and benchmarks change.
Start with the existing fetcher:

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/fetch-model-data.sh"
```

- Exit 0 → use its normalized pricing and intelligence rows.
- Exit 3 → no `ARTIFICIAL_ANALYSIS_API_KEY`. Offer the developer the free
  Artificial Analysis models API, but never ask them to paste a key into chat.
  They may decline; use official provider documentation plus judgment and record
  that source.
- Exit 4 or 5 → the configured fetch failed or its response shape yielded no
  usable row. Report it, retry once, then use official provider documentation
  plus judgment only if it still fails; record the failure reason under
  `sources`, without credential values.

Read the current DeepSWE leaderboard for agentic software-engineering quality at
each effort level. If it is unavailable, record that and use provider evidence
plus judgment. Rows are keyed by `(model, effort)` because effort can move
agentic quality more than model tier.

## 3. Establish developer-specific inputs

On first-time setup, ask one focused question at a time. Cover trust for hard
problems explicitly; do not infer it from benchmark scores:

1. **Capabilities and providers:** which native runtimes, providers, and CLIs are
   usable, and which subscriptions or metered APIs back them? Verify every
   CLI-backed claim with `command -v`. A Setup-provided inventory is evidence for
   this step, not permission to infer subscriptions.
2. **Cost semantics:** per provider, decide whether `cost` represents metered
   dollars or, for a flat subscription, quota burn plus latency.
3. **Trust for hard problems:** identify models the developer trusts or refuses
   for ambiguous unsupervised work.
4. **Taste:** identify models whose UI, copy, and public API judgment needs the
   least editing.
5. **Working style:** decide whether latency matters for attended work and whether
   slow, high-quality rows are useful for unattended batches.

On an ordinary data refresh, keep capabilities, taste, trust, working style, and
cost semantics; update data-sourced axes and `reviewed:` without re-interviewing.
On a Setup invocation, reconcile each CLI-backed capability with the supplied
inventory. Preserve non-CLI facts, show additions/removals, and continue even
when the existing rubric is otherwise current.

## 4. Build or refresh the rubric

For first-time setup, copy
`skills/model-rubric/Default_Rubric.yml` from this plugin to the path returned by
`scripts/rubric-path.sh`, writing through the config-directory symlink when one
exists. Treat it only as a seed:

1. remove rows whose provider/executor is unavailable;
2. add current candidate `(model, effort)` rows for newly available providers;
3. fill `cost` using the developer's cost semantics;
4. update data-backed `intelligence` and `swe`, preserving user-owned `taste`;
5. mark cross-provider CLI rows with `via: <cli>`;
6. derive `routing` fresh from the reachable rows;
7. remove `seed: true`, replace `reviewed:` with today's date, and record the
   actual sources used.

For a Setup reconciliation, add/drop affected model rows and derive `routing`
fresh whenever a CLI-backed capability changed. For an ordinary stale-data
refresh, retain the reachable row set unless current evidence says a model was
superseded.

The routing table uses exact `<model>@<effort>` values:

- `routing.default`: best ordinary quality/cost balance;
- `routing.bulk`: clear-spec mechanical work;
- `routing.quick`: low-latency short work;
- `routing.explore`: cheapest capable native read-only agent;
- optional `routing.batch`: unattended fan-out only;
- `routing.taste_min`: minimum taste score for user-facing work;
- `routing.review`: strongest non-wasteful fixed-target review row;
- optional `routing.independent`: a different provider from the daily driver,
  only when two providers are available and cost approval remains required.

`via` is executor metadata interpreted by Harness. Consumers never branch on it.
Every eventual dispatch still passes model and effort explicitly.

The completed file has this shape:

```yaml
reviewed: YYYY-MM-DD
sources: [source-name]
capabilities:
  claude: true
  codex: true
models:
  - { name: model-name, effort: high, cost: 5, intelligence: 8, taste: 8, swe: 60, via: codex }
routing:
  default: model-name@high
  bulk: model-name@high
  quick: model-name@low
  explore: native-model@low
  taste_min: 9
  review: review-model@high
```

Show the draft before writing on first-time setup. Developer edits override seed
judgment. Never write a credential, secret-bearing profile, absolute machine
path, or temporary evidence into the rubric.

## 5. Confirm

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/rubric-path.sh" --check
```

Expected: `set`. Report the path and the `reviewed:` date.

Also verify that `seed: true`, `cost: null`, and `routing: {}` are absent; each
route names an existing row with the same model and effort; `via` executors match
current capabilities; and a Setup invocation reports `reconciled: true` even
when the file did not change.
