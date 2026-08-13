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

## Tests

```bash
./tests/run-tests.sh
```
