---
name: model-rubric
description: >-
  Create or refresh this developer's user-global model-routing rubric — the file
  that decides which model does which work (cheap models for bulk/mechanical work,
  the strongest for ambiguous or taste-sensitive work). Lives at
  ${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml, one per
  developer, shared across every repo. Trigger: "set up my model rubric",
  "refresh my rubric", "which model should agents use", "my rubric is stale",
  or /fleet:model-rubric.
  Do NOT use to route a specific task right now (just read the rubric), or to
  configure a project's issue tracker (that's /pm:setup).
effort: medium
allowed-tools: "Bash Read Write Edit WebFetch"
---

# Fleet — Model Rubric

Owns creating and refreshing the per-developer model-routing rubric.

## 1. Check current state

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/rubric-path.sh" --check
```

- `set` → read the file's `reviewed:` stamp. Current (≤14 days, no superseded
  models listed) → say so and stop. Otherwise offer a refresh.
- `unset` → first-time setup.

## 2. Follow the canonical walkthrough

The full procedure lives in `studio-baseline/Rubric_Setup.md` and is deliberately
**not duplicated here** — it must work for developers with no plugin installed, so
that file is the single source of truth. Read it:

```bash
cat "$CLAUDE_PLUGIN_ROOT/../../studio-baseline/Rubric_Setup.md" 2>/dev/null \
  || echo "fetch https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/Rubric_Setup.md"
```

Follow it exactly. Two notes specific to running it from here:

- Where it calls for live model data, use
  `"$CLAUDE_PLUGIN_ROOT/scripts/fetch-model-data.sh"`. Exit code 3 means no
  `ARTIFICIAL_ANALYSIS_API_KEY` — fall back to vendor docs and judgment, and record
  `sources: [judgment]`.
- Where it calls for the target path, use
  `$("$CLAUDE_PLUGIN_ROOT/scripts/rubric-path.sh")`.

**On a refresh, keep the developer's taste scores and `capabilities` unchanged** —
only the Artificial-Analysis-sourced axes (cost, intelligence) change. Do not
re-interview.

## 3. Confirm

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/rubric-path.sh" --check
```

Expected: `set`. Report the path and the `reviewed:` date.
