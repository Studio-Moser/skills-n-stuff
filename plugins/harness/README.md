# Harness

Owns universal agent rules, personal setup, provider-neutral execution, and
evidence-bearing results.

Your config lives in **your own private repo** — this plugin never contains it.
The plugin is public and generic; the data is yours.

## Skills

- **`/harness:setup`** — create or connect the personal agents repository,
  reconcile portable links and runtime capabilities, and establish the personal
  model rubric.
- **`/harness:sync`** — run `scripts/sync` to make this machine match your personal
  agent repo. The script previews safely with `--dry-run`, stops with typed exit
  codes for choices and destructive conflicts, ingests the remote before
  reconciliation, and commits once and pushes once through the guarded finalizer.
- **`/harness:model-rubric`** — create or refresh your user-global model-routing
  rubric at `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`.
- **`/harness:risk-gate`** — classify repository work from observable risk triggers
  and decide whether it needs structure or independent review.
- **`/harness:delegate`** — route one bounded execution, fixed-target review, or
  computer-use request with explicit authority, context, and proof.
- **`/harness:fleet`** — run commands on your other machines over SSH. The host
  inventory (`ssh/config`) and one public key per machine live in your private
  repo; each machine includes the inventory and authorizes those keys.
- **`/harness:audit`** — answer questions about real usage and gaps: which skills
  and rules run, which shims still fire or could retire, how delegations turn out,
  and what keeps failing. It reads `scripts/usage-report.py`, the delegation ledger,
  shim events, and `Component_Catalog.toml`.

## Telemetry

Harness records two event streams on each machine: every delegation result
(`Results`) and every shim firing (`Shim_Events`, e.g. the zsh glob guard hook).
Writers append only to `${XDG_STATE_HOME:-~/.local/state}/studio-moser/harness/telemetry/`,
so the agents repository stays clean between syncs. Each `/harness:sync` merges
those files by record id into `telemetry/<host>/` in your private agents repository
and writes that month's `Usage-YYYY-MM.json` counts. Records hold typed fields and
counts only; home paths are redacted, and transcripts never leave the machine.

`Component_Catalog.toml` lists every behavior rule and shim with its kind, source
anchor, reason, detector, and retirement test. Add an entry with each new rule, shim,
or hook.

Claude Code and Codex both load `hooks/hooks.json` from this plugin. Codex skips
plugin hooks until you review and trust them once with `/hooks`, and it does not
apply hook denials under its `read-only` sandbox. In Codex, the zsh glob guard always
denies with a quoting reason; Codex only accepts a rewrite together with an `allow`
decision, which would skip its approval policy.

Any main model chooses direct execution or a rubric worker using
[Execution choice](references/routing.md#execution-choice): capability, verifiability,
and total cost including handoff and verification. Tiny edits stay local; clear
bounded work can use cheaper workers. Risk still determines verification and review.
Delegation is capped by child/depth/token limits and short-circuits when a route
resolves to the active model and effort. Classification and routine routing stay internal.

The rubric separates the preferred top-level orchestrator from delegated routes.
Setup derives both from the models and executors actually available on that
machine; Claude plus Codex enables cross-provider delegation, while either
provider alone still produces a valid rubric. Software-work efficiency uses
benchmark cost per successful task rather than token list price alone.

## One source for every agent tool (rulesync)

A personal agents repo that contains `rulesync.jsonc` hands per-tool generation to
[rulesync](https://github.com/dyoshikawa/rulesync) (pinned in
`scripts/rulesync-generate.py`). `/harness:sync` then:

- renders the Harness profile into `.rulesync/rules/Global_Instructions.md`; your own
  text outside the markers lives there too, and rulesync writes `CLAUDE.md`,
  Codex `AGENTS.md`, and every other tool's instruction file from it;
- runs `rulesync install` for the third-party skills declared under `sources`
  (pinned by `rulesync.lock`) only when the config, lockfile, or installed skills
  changed, with your `gh` login token so GitHub's anonymous rate limit does not apply;
  an install that only refreshes the lock's `resolvedAt` timestamps leaves the
  committed `rulesync.lock` alone;
- runs `rulesync generate --global` for instructions, MCP servers
  (`.rulesync/mcp.jsonc`), hooks (`.rulesync/hooks.jsonc`), skills, subagents, and
  commands;
- merges this machine's untracked `.rulesync.local/mcp.jsonc` servers and
  `hooks.jsonc` entries (app-bundled tools, machine paths) into a temporary source,
  so they never reach git; machine-only Claude hooks are refused, since Claude's
  `settings.json` is shared through the repo. A server in `.rulesync.local` that an
  app installs and rewrites itself (a command inside an `.app` bundle, like Codex's
  `node_repl` from ChatGPT.app) is re-read from the tool before each generate, so an
  app update is not reverted (a refresh rewrites that file without its comments);
- moves broken symlinks out of a tool's folder (for example skills pointing at a
  deleted folder) into `~/.local/state/studio-moser/harness/backups/` when rulesync
  cannot write through them, then generates again;
- keeps the generated skill copies under `skills/` out of git with a generated
  `.gitignore` block, and reports any that are already tracked;
- removes the generated folders of skills dropped from the source since this
  machine's last run, and nothing else;
- skips its own MCP manifest and `npx skills` steps.

### Adopting it

`scripts/rulesync-bootstrap.py <repo>` (offered by `/harness:setup`) previews building
the source from the agent tools on this machine: each tool's MCP servers and hooks,
imported with rulesync, become one shared list with per-tool blocks where definitions
differ; anything with a home-folder path, or a credential-looking value under an
ordinary name, in a URL, or in an argument, stays in `.rulesync.local`; secret values move
to the secret store and their servers start through `bin/with-secrets`; skills from
`skills.manifest` become `sources`, and your own committed skills move into
`.rulesync/skills`. `--write` applies it; the next Sync generates every tool. A secret that no rule can
move (for example a key in an HTTP server's `env`) stops `--write` and names the field.
Launchers find `bin/with-secrets` at the repo's path under your home folder, so keep the
repo at the same path on every machine (the default `~/.agents`).

On every other machine, the first managed Sync keeps that machine's own servers and
hooks the shared source does not define in its `.rulesync.local` (it reports them), and
the first generate for a repo backs up every live file it will write to
`~/.local/state/studio-moser/harness/backups/`.

### Keeping rulesync and skills current

Both are pinned, so every machine generates the same files: rulesync by version in
`scripts/rulesync-generate.py`, third-party skills by commit in `rulesync.lock`.
Nothing updates on its own; Sync tells you when something can:

- each Sync prints `Updates:` with a newer rulesync release and any skill source whose
  upstream moved past the lock (checked at most once a day, read-only);
- `/harness:sync --update-skills` re-resolves every source to its latest commit and
  commits the new `rulesync.lock`, so other machines install the same commits on their
  next Sync;
- to move the rulesync pin, run `scripts/rulesync-rehearse.py <version>`: it generates
  this machine's real config with the pinned and the candidate version into two
  temporary HOMEs and diffs every file either writes. Bump the pin in a Harness
  release once the differences are understood.

Keep `delete` off in `rulesync.jsonc`: rulesync's sweep would also remove folders
other installers own, such as `~/.claude/skills/synced`. Permissions are not
generated: rulesync's translation would change Codex's sandbox. Plugins stay with
Harness's plugin reconciliation, since rulesync only packages plugins: Claude Code
installs the shared `enabledPlugins`, and Codex gets the same list from every
marketplace it knows. A Codex plugin from those marketplaces that the shared list
lacks is reported with its `codex plugin remove` command, never removed.

## Secrets

Secret values live only in each machine's secret store, never in the repo or an
agent's config. `scripts/agent-secrets.py` picks the store from the platform: the
macOS login Keychain (service `agent-secrets`), the Linux desktop keyring through
`secret-tool`, or a `0600` file at `~/.config/agent-secrets/secrets.env`;
`HARNESS_SECRETS_BACKEND` overrides it. On a Linux machine with `secret-tool`
installed but no running keyring (a headless server), set
`HARNESS_SECRETS_BACKEND=file` where both your shell and your agents read it (for
example `~/.config/environment.d/agent-secrets.conf` and `~/.profile`); otherwise
`set` fails and every secret-backed server exits 78.

A Mac's login Keychain refuses writes from an SSH session, even while it is unlocked
at the desktop. When HOST's store refuses one, `copy-to` stages the value in a `0600`
file under `~/.config/agent-secrets/import/` on HOST and prints the `import` command to
run in a terminal on HOST's own desktop session.

| Command | Does |
|---|---|
| `agent-secrets.py set NAME` | store the value read from stdin or a hidden prompt |
| `agent-secrets.py check [NAME ...]` | report present/missing for `secrets.names` in the repo |
| `agent-secrets.py copy-to HOST [NAME ...]` | copy values over fleet SSH into HOST's own store |
| `agent-secrets.py import` | on HOST's own desktop, store what `copy-to` had to stage, then delete it |
| `bin/with-secrets NAME ... -- command` | start a command with those values exported |

An MCP server that needs a key starts through the launcher, so it works no matter
which app launched the agent (GUI apps such as T3 Code do not read shell rc files).
The launcher is plain `sh` and reads the store itself, so it works with any installed
Harness version. Claude Code keeps an unset `${VAR}` literally but warns, so for an
HTTP server with a token header use its `headersHelper` there and `mcp-remote` (which
substitutes `${VAR}` from its own environment) for other tools:

```jsonc
"kie-ai": {
  "command": "sh",
  "args": ["-c", "exec \"$HOME/.agents/bin/with-secrets\" KIE_AI_API_KEY -- npx -y @felores/kie-ai-mcp-server"]
}
```

Values travel on stdin only; nothing prints them or puts them on a command line.

## Provider-resilient routes

The rubric may define an ordered `fallbacks.<route>` list for a semantic route.
Harness switches only when the selected provider or executor has a typed
availability failure; authority, verification, and all other request constraints
stay unchanged. Route health is machine-local: timed failures open cooldowns,
and after a cooldown exactly one post-cooldown half-open probe may run before
the route is considered healthy again. Without an explicit ordered fallback,
Harness does not switch providers or executors.

External Codex routes use the installed App Server protocol. Capability
discovery first checks that its typed
`turn/completed.turn.error.codexErrorInfo` seam is callable; a missing or
incompatible seam is a preflight skip, not a dispatch attempt or timed circuit.
Only its structured terminal metadata may authorize availability fallback—raw
error text is never parsed or returned. External review validates the fixed
commit, checks it out into an ephemeral local clone, and runs the read-only turn
from that pinned snapshot rather than the caller's moving checkout.

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
| `scripts/sync [--dry-run] [decision flags]` | deterministic sync entry point; orchestrates the helpers, refuses unresolved judgment, and prints the structured result |
| `scripts/link-plan.sh [repo]` | read-only drift report; exit 1 if any link needs work |
| `scripts/sync-preflight.sh <repo>` | query and ingest the remote before any reconciliation writer runs |
| `scripts/reconcile_shared_settings.py [--check] <settings.json> [...]` | enable Harness and remove the retired Machine setting atomically |
| `scripts/mcp-manifest.sh [--prune-to-local] <claude-user-state.json> <mcp.manifest.json>` | generate the portable MCP manifest (shape with `${VAR}` references, per-host `machines`), migrate a names-only file, or `--check` one |
| `scripts/mcp-reconcile.sh <repo> <claude-user-state.json> <settings.local.json>` | read-only per-host table and plan lines for `harness:sync`'s match / replace / merge step |
| `scripts/mcp-secrets.sh export [--stdout] <mcp.manifest.json> <claude-user-state.json>` \| `import <claude-user-state.json>` | move `${VAR}` values between machines without the repo seeing them (repos without rulesync; managed repos use `agent-secrets.py`) |
| `scripts/stamp-baseline.sh <target> [body]` | idempotently stamp the Harness project block; defaults to the bundled template |
| `scripts/portability-lint.sh [repo]` | fail on machine-specific absolute paths |
| `scripts/rubric-path.sh [--check]` | resolve the rubric path / report `set`\|`unset` |
| `scripts/resolve-route.py validate\|select\|record-failure\|record-success ...` | validate a rubric, select an authorized route, and record local availability health |
| `scripts/codex-app-server.py check\|run ...` | verify the typed App Server seam and run one bounded external Codex turn |
| `scripts/fetch-model-data.sh` | current model cost + intelligence as TSV (exit 3 = no API key) |
| `scripts/skills-reconcile.sh <repo>` | read-only diff of `skills.manifest` vs. reality (reads `npx skills list -g --json` on stdin) |
| `scripts/skills-manifest.sh <repo>` | regenerate `skills.manifest` and the `.gitignore` block from reality (same stdin) |
| `scripts/fleet-authorize.sh [repo] [authorized_keys]` | rewrite the `# harness:fleet` block in `authorized_keys` from `<repo>/ssh/keys/*.pub`; rejects option-bearing keys |
| `scripts/fleet-hosts.sh [repo]` | print the concrete `Host` aliases in `<repo>/ssh/config`; exit 1 on none or an unsafe alias |
| `scripts/fleet-include.sh [repo] [ssh_config]` | prepend a global `Include` of the fleet inventory unless one already precedes the first `Host`/`Match` |
| `scripts/rulesync-generate.py [--dry-run] <repo>` | install declared skills and generate every agent tool's files from a rulesync-managed repo |
| `scripts/rulesync-bootstrap.py [--write\|--machine] <repo>` | build a repo's rulesync source from this machine's tools, or keep a machine's extras on its first managed sync |
| `scripts/rulesync-rehearse.py <version> [repo]` | diff this machine's generated config between the pinned and a candidate rulesync, in temporary HOMEs |
| `scripts/agent-secrets.py set\|exec\|check\|copy-to\|import ...` | store secrets in this machine's secret store and hand them only to the process that needs them |
| `scripts/telemetry.py record-result\|publish ...` | append delegation results and publish local telemetry into the repo's `telemetry/<host>/` |
| `scripts/usage-report.py [--days N\|--month YYYY-MM]` | deterministic usage counts from transcripts and telemetry |
| `scripts/sync-finalize.sh <repo> <message>` | stage, scan, commit, exact-lease push, and prove a clean actual remote SHA once |

## Tests

```bash
./tests/run-tests.sh
```
