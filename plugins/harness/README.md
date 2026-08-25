# Harness

Owns universal agent rules, personal setup, provider-neutral execution, and
evidence-bearing results.

Your config lives in **your own private repo** — this plugin never contains it.
The plugin is public and generic; the data is yours.

## Skills

- **`/harness:setup`** — create or connect the personal agents repository,
  reconcile portable links and runtime capabilities, and establish the personal
  model rubric.
- **`/harness:sync`** — make this machine match your personal agent repo. Clones on
  first run or safely adopts existing loose configuration. Preflight ingests the
  remote before reconciliation; the finalizer commits once and pushes once with
  an exact compare-and-swap lease. Sync also re-links drifted paths, lints
  portability, and optionally updates other machines.
- **`/harness:model-rubric`** — create or refresh your user-global model-routing
  rubric at `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`.
- **`/harness:execute`** — resolve a semantic route and run one bounded request
  with explicit authority, context, and verification.
- **`/harness:review`** — independently review a fixed target, reproduce its
  checks, and return evidence without changing the target.
- **`/harness:computer-use`** — operate a local app, browser, simulator, or other
  screenshot-capable UI with explicit capability and proof.

The rubric separates the preferred top-level orchestrator from delegated routes.
Setup derives both from the models and executors actually available on that
machine; Claude plus Codex enables cross-provider delegation, while either
provider alone still produces a valid rubric. Software-work efficiency uses
benchmark cost per successful task rather than token list price alone.

## Provider-resilient routes

The rubric may define an ordered `fallbacks.<route>` list for a semantic route.
Harness switches only when the selected provider or executor has a typed
availability failure; authority, verification, and all other request constraints
stay unchanged. Route health is machine-local: timed failures open cooldowns,
and after a cooldown exactly one post-cooldown half-open probe may run before
the route is considered healthy again. Without an explicit ordered fallback,
Harness does not switch providers or executors.

## Migrating from Machine

Migrate in this order so there is never a gap in control-plane ownership:

1. From a canary project on every machine, install Harness at official local
   project scope: `claude plugin install harness@studio-moser --scope local`.
   Claude records that project-specific, gitignored install in
   `.claude/settings.local.json`. Keep Machine installed while the fleet is in
   transition.
2. Verify Harness works on every machine by starting a fresh session and running
   `/harness:sync --dry-run`; do not change the shared settings yet.
3. After every machine can load Harness, merge and pull the private agents migration.
   This is the **tracked setting removal**: it enables
   `"harness@studio-moser": true` and removes `machine@studio-moser` from the
   shared repository without uninstalling the cached Machine plugin.
4. Rerun `/harness:sync` on every machine and require its clean remote-SHA report.
5. Only then perform the **cached plugin uninstall** on every machine:
   `/plugin uninstall machine@studio-moser`. Reload active sessions afterward.

Product Pulse and PM depend on Harness for provider-neutral execution and review;
install or migrate Harness before running either consumer.

## Universal project instructions

- [`references/house-rules.md`](references/house-rules.md) is the single source
  for engineering discipline and change classes.
- [`templates/AGENTS_Baseline.md`](templates/AGENTS_Baseline.md) is the managed
  project instruction block. It states only the semantic Harness contract;
  personal route values and provider mechanics stay in user-global configuration.

PM setup stamps this Harness-owned template into a repository without keeping a
second copy. Consumers select a semantic route and provide authority; Harness
resolves execution and returns evidence for the parent to reproduce.

## Third-party skills are declared, not vendored

`/harness:sync` (Phase 2.6) reconciles third-party skills — the ones installed
with `npx skills` (vercel-labs) rather than authored in your repo — against
a generated `skills.manifest`. It only works when your repo **is**
`$HOME/.agents` — `npx skills` hardcodes that install path regardless of
`$AGENTS_REPO`, so an overridden repo location skips this phase entirely
rather than produce wrong output. Vendoring a skill instead of declaring it
(committing its code into your repo) bloats the repo and drifts from
upstream. To move an already-vendored skill to manifest management:

1. `git -C "$repo" rm -r --cached skills/<name>` — untrack it; the file
   stays on disk.
2. Run `/harness:sync`. Phase 2.6 sees it installed with a real `source`,
   offers to add it to `skills.manifest`, and `skills-manifest.sh` adds a
   `skills/<name>/` line to the generated `.gitignore` block — the untracked
   files are now deliberately ignored, not lost.
3. Verify: `npx skills list -g --json` should still report the skill, with
   a non-null `source`.

**`.skill-lock.json` must never be tracked either.** `npx skills list` reads
a skill's `source` back from that lockfile, not from the skill itself — a
tracked copy lets one machine's removal silently reappear as "no source" on
another, and this phase would then un-declare and re-vendor it. Phase 2.6's
step 0 detects a tracked `.skill-lock.json` and offers a one-time
`git rm --cached` to fix it; `skills-manifest.sh` keeps it gitignored going
forward.

## Schedule it, or it won't happen

**Nothing runs `/harness:sync` for you.** This plugin detects drift; it does not
watch for it. Your config diverges the moment a tool upgrades a skill, a plugin
toggle rewrites `settings.json`, or you edit a skill on one machine — and an
unsynced repo silently hands the *old* state to the next machine that clones it.

Set up a recurring `/harness:sync` with whatever scheduler you already use — your
agent tool's scheduled tasks, `cron`, `launchd`, CI. Daily is plenty. There is
deliberately no scheduler in this plugin: you already have one, and a background
job that reorganizes your config is something you should own rather than inherit.

Two rules whichever you pick:

- **Report, don't act silently.** `/harness:sync` asks before removing, re-linking,
  or discarding. An unattended run must not answer those prompts for you.
- **It preflights, commits, and compare-and-swap pushes.** Sync fetches and
  fast-forwards the current remote before any reconciliation writer runs. The
  finalizer then commits once and pushes once with the exact remote state captured
  by preflight — otherwise the repo goes stale and the next machine to clone gets
  the old state. Everything is recoverable from git history. It stops without
  overwriting if another machine changes the branch; it never rebases or uses
  unconditional force.

## First-machine setup

Run `/harness:setup`. It can clone an existing private agents repository or safely
adopt loose configuration on the current machine. The adoption path backs up live
entries first, keeps machine-local and secret state out of Git, verifies portability,
and confirms a remote is private before the first push.

## Scripts

| | |
|---|---|
| `scripts/link-plan.sh [repo]` | read-only drift report; exit 1 if any link needs work |
| `scripts/sync-preflight.sh <repo>` | query and ingest the remote before any reconciliation writer runs |
| `scripts/reconcile_shared_settings.py [--check] <settings.json> [...]` | enable Harness and remove the retired Machine setting atomically |
| `scripts/mcp-manifest.sh <runtime-mcp.json> <mcp.manifest>` | generate or validate the names-only portable MCP inventory |
| `scripts/stamp-baseline.sh <target> [body]` | idempotently stamp the Harness project block; defaults to the bundled template |
| `scripts/portability-lint.sh [repo]` | fail on machine-specific absolute paths |
| `scripts/rubric-path.sh [--check]` | resolve the rubric path / report `set`\|`unset` |
| `scripts/resolve-route.py validate\|select\|record-failure\|record-success ...` | validate a rubric, select an authorized route, and record local availability health |
| `scripts/fetch-model-data.sh` | current model cost + intelligence as TSV (exit 3 = no API key) |
| `scripts/skills-reconcile.sh <repo>` | read-only diff of `skills.manifest` vs. reality (reads `npx skills list -g --json` on stdin) |
| `scripts/skills-manifest.sh <repo>` | regenerate `skills.manifest` and the `.gitignore` block from reality (same stdin) |
| `scripts/sync-finalize.sh <repo> <message>` | stage, scan, commit, exact-lease push, and prove a clean actual remote SHA once |

## Tests

```bash
./tests/run-tests.sh
```
