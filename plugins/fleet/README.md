# fleet

Keeps your personal agent configuration identical across machines.

Your config lives in **your own private repo** — this plugin never contains it.
The plugin is public and generic; the data is yours.

## Skills

- **`/fleet:sync`** — make this machine match your personal agent repo. Clones on
  first run, pulls after. Re-links anything that drifted, lints for paths that
  would be wrong on another machine, and optionally pushes to other machines.
- **`/fleet:model-rubric`** — create or refresh your user-global model-routing
  rubric at `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`.

## Third-party skills are declared, not vendored

`/fleet:sync` (Phase 2.6) reconciles third-party skills — the ones installed
with `npx skills` (vercel-labs) rather than authored in your repo — against
a generated `skills.manifest`. Vendoring one instead (committing its code
into your repo) bloats the repo and drifts from upstream. To move an
already-vendored skill to manifest management:

1. `git -C "$repo" rm -r --cached skills/<name>` — untrack it; the file
   stays on disk.
2. Run `/fleet:sync`. Phase 2.6 sees it installed with a real `source`,
   offers to add it to `skills.manifest`, and `skills-manifest.sh` adds a
   `skills/<name>/` line to the generated `.gitignore` block — the untracked
   files are now deliberately ignored, not lost.
3. Verify: `npx skills list -g --json` should still report the skill, with
   a non-null `source`.

## Schedule it, or it won't happen

**Nothing runs `/fleet:sync` for you.** This plugin detects drift; it does not
watch for it. Your config diverges the moment a tool upgrades a skill, a plugin
toggle rewrites `settings.json`, or you edit a skill on one machine — and an
unsynced repo silently hands the *old* state to the next machine that clones it.

Set up a recurring `/fleet:sync` with whatever scheduler you already use — your
agent tool's scheduled tasks, `cron`, `launchd`, CI. Daily is plenty. There is
deliberately no scheduler in this plugin: you already have one, and a background
job that reorganizes your config is something you should own rather than inherit.

Two rules whichever you pick:

- **Report, don't act silently.** `/fleet:sync` asks before removing, re-linking,
  or discarding. An unattended run must not answer those prompts for you.
- **It commits and pushes.** Sync commits this machine's changes, pulls, then
  pushes — otherwise the repo goes stale and the next machine to clone gets the old
  state. Everything is recoverable from git history. It stops without pushing if
  another machine has diverged; it never rebases or forces.

## Bootstrapping a bare machine

This plugin can't set up a machine that has no plugins installed. For that, follow
[`studio-baseline/Machine_Setup.md`](https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/Machine_Setup.md),
which needs only a shell and web access. Install this plugin afterwards for the
ongoing work.

## Scripts

| | |
|---|---|
| `scripts/link-plan.sh [repo]` | read-only drift report; exit 1 if any link needs work |
| `scripts/portability-lint.sh [repo]` | fail on machine-specific absolute paths |
| `scripts/rubric-path.sh [--check]` | resolve the rubric path / report `set`\|`unset` |
| `scripts/fetch-model-data.sh` | current model cost + intelligence as TSV (exit 3 = no API key) |
| `scripts/skills-reconcile.sh <repo>` | read-only diff of `skills.manifest` vs. reality (reads `npx skills list -g --json` on stdin) |
| `scripts/skills-manifest.sh <repo>` | regenerate `skills.manifest` and the `.gitignore` block from reality (same stdin) |

## Tests

```bash
./tests/run-tests.sh
```
