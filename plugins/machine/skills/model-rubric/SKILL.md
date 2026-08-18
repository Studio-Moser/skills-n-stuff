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
  or /machine:model-rubric.
  Do NOT use to route a specific task right now (just read the rubric), or to
  configure a project's issue tracker (that's /pm:setup).
effort: medium
allowed-tools: "Bash Read Write Edit WebFetch"
---

# Machine — Model Rubric

Owns creating and refreshing the per-developer model-routing rubric.

## 1. Check current state

```bash
machine="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/machine/*/ 2>/dev/null | sort -V | tail -1)}"; machine="${machine%/}"
"$machine/scripts/rubric-path.sh" --check
```

- `set` → read the file's `reviewed:` stamp. Current (≤14 days, no superseded
  models listed) → say so and stop. Otherwise offer a refresh.
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
  `/machine:sync` verifies this link on every run (it is one of the eight tracked entries).
- **`plain`** → no repo on this machine; write to `$config/studio-moser/` as a real
  directory (`mkdir -p`). Everything else proceeds identically.

**Never replace the symlink with a real file/folder when writing or refreshing** — edit
the file through the link. An atomic-replace of the directory severs sync silently.

## 2. Follow the canonical walkthrough

The full procedure lives in `studio-baseline/Rubric_Setup.md` and is deliberately
**not duplicated here** — it must work for developers with no plugin installed, so
that file is the single source of truth. Read it:

```bash
cat "$machine/../../studio-baseline/Rubric_Setup.md" 2>/dev/null \
  || echo "fetch https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/Rubric_Setup.md"
```

Follow it exactly. Two notes specific to running it from here:

- Where it calls for live model data, use
  `"$machine/scripts/fetch-model-data.sh"`. Exit code 3 means no
  `ARTIFICIAL_ANALYSIS_API_KEY` — fall back to vendor docs and judgment, and record
  `sources: [judgment]`. Exit code 4 (request failed, e.g. network) or 5 (response
  parsed but no row yielded a figure — the API shape likely changed) are **not**
  the same as "no key": a key was present and the call was attempted but didn't
  come back clean. Don't silently fall back to judgment as if the developer
  declined — report the failure, retry once, and only fall back to vendor
  docs/judgment if it persists, noting the reason (not just `judgment`) under
  `sources`.
- Where it calls for the target path, use
  `$("$machine/scripts/rubric-path.sh")`.
- Where the walkthrough offers a **seed rubric**, use this plugin's copy:
  `"$machine/skills/model-rubric/Default_Rubric.yml"`. Copy it to the target path
  as the starting table, then follow the walkthrough's rules: drop rows whose
  provider isn't in this developer's `capabilities`, fill `cost` from their cost
  semantics, derive `routing` fresh, remove the `seed:` key, and set `reviewed:`
  to today. A file still containing `seed: true`, `cost: null`, or `routing: {}`
  is NOT set up — `--check` may pass on it, so verify these keys are gone.

**On a refresh, keep the developer's taste scores and `capabilities` unchanged** —
re-pull AA and DeepSWE and update only the data-sourced axes (cost,
intelligence, swe). Do not re-interview.

## 3. Confirm

```bash
machine="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/machine/*/ 2>/dev/null | sort -V | tail -1)}"; machine="${machine%/}"
"$machine/scripts/rubric-path.sh" --check
```

Expected: `set`. Report the path and the `reviewed:` date.
