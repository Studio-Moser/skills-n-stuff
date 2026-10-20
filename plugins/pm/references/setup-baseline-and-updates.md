# Harness Baseline and Plugin Updates for /pm:setup

Loaded by `skills/setup/SKILL.md` after Phase 4, for every backend. `$pm` is the
installed PM root resolved in Phase 3.

## Phase 4.4: Stamp the Harness baseline block

Every repo—regardless of who works on it—gets the same managed baseline block in its
`AGENTS.md`. PM only stamps the shared block; Harness owns its execution guidance and
setup surface.

1. Follow the repository's existing instruction-file convention: use `AGENTS.md` if
   it exists, or if neither `AGENTS.md` nor `CLAUDE.md` exists; use `CLAUDE.md`
   directly only when it is the sole file present.

```bash
if [ -f "$primary_repo_root/AGENTS.md" ]; then
  TARGET="$primary_repo_root/AGENTS.md"
elif [ -f "$primary_repo_root/CLAUDE.md" ]; then
  TARGET="$primary_repo_root/CLAUDE.md"
else
  TARGET="$primary_repo_root/AGENTS.md"
fi
```

   If `$TARGET` is `AGENTS.md`, make sure `CLAUDE.md` imports it: if `CLAUDE.md` exists but has no `@AGENTS.md` line, add one; if `CLAUDE.md` doesn't exist, create a minimal one containing just `@AGENTS.md`.

2. Read the canonical Harness template. Harness is already a proven prerequisite
   from Step 1d, so PM does not keep or reconstruct a second copy. The public source
   path is `plugins/harness/templates/AGENTS_Baseline.md`; use the installed Harness
   copy so setup also works offline:

```bash
harness="${HARNESS_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
pm="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/pm/*/ 2>/dev/null | sort -V | tail -1)}"; pm="${pm%/}"
[ -d "$harness" ] || harness="$pm/../harness"
BODY="$harness/templates/AGENTS_Baseline.md"
```

3. Stamp it with Harness's idempotent writer. An empty or missing template must
   leave any existing block unchanged, so skip the stamp and report the missing
   Harness installation rather than falling back to a duplicate:

```bash
if [ ! -s "$BODY" ]; then
  echo "Could not obtain the Harness baseline template. Run /harness:setup, then rerun /pm:setup."
else
  "$harness/scripts/stamp-baseline.sh" "$TARGET"
fi
```

4. If the stamp ran, tell the user the block was stamped/refreshed and that it's committed with the rest of setup, so every teammate inherits it on clone.

---

## Phase 4.5: Plugin freshness (referral)

pm ships through the `studio-moser` marketplace. **Third-party marketplaces have
auto-update off by default**, so a developer who added it once may be running a
months-old pm without knowing. Check, report, offer — do not change their
Claude Code configuration for them.

```bash
if command -v claude >/dev/null 2>&1; then
  claude plugin marketplace list 2>/dev/null | grep -q 'studio-moser' && echo "marketplace: registered" || echo "marketplace: missing"
  python3 - << 'PY' 2>/dev/null || echo "autoupdate: unknown"
import json, os
d = json.load(open(os.path.expanduser("~/.claude/plugins/known_marketplaces.json")))
print("autoupdate:", "on" if d.get("studio-moser", {}).get("autoUpdate") else "off")
PY
else
  echo "claude CLI not on PATH — skip"
fi
```

- `marketplace: missing` → tell the user: `"The studio-moser marketplace isn't registered on this machine, so pm can't update. Add it with /plugin marketplace add Studio-Moser/skills-n-stuff, then enable auto-update (below)."` — and stop there; do not also give the `autoupdate: off` message or offer the update commands, since they cannot succeed without the marketplace.
- `autoupdate: off` (or `unknown`) → tell the user: `"Auto-update is off for studio-moser (Claude Code's default for third-party marketplaces), so pm won't pick up new versions on its own. Turn it on: /plugin → Marketplaces → studio-moser → Enable auto-update. Want me to pull the latest now? I'd run: claude plugin marketplace update studio-moser && claude plugin update pm@studio-moser"` — and run those two commands only if they say yes. Both need a restart or `/reload-plugins` to apply; say so.
- `marketplace: registered` and `autoupdate: on` → one line: `"studio-moser marketplace is registered and auto-updating."`
