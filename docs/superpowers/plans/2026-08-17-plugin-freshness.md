# Plugin Freshness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make sure a machine running our plugins actually receives marketplace updates — for machine-plugin users via `machine:sync`, for pm-only users via `pm:setup`, and for a fresh machine via the bootstrap docs — and fix the pm version mismatch (`plugin.json` 0.17.0 vs `marketplace.json` 0.16.1). Correction recorded at final review: Claude Code resolves a plugin's version from `plugin.json` first and the marketplace entry second, so the mismatch was hygiene, not a blocker — the real trap is the inverse: bumping only `marketplace.json` does nothing while `plugin.json` is set.

**Architecture:** Three surfaces, one behavior each. (1) `machine:sync` Phase 2.5's inline reconcile script gains an update pass (`claude plugin marketplace update` + `claude plugin update <name>` for every enabled plugin) and reports marketplaces registered locally but absent from shared settings, with the exact removal command. (2) `pm:setup` gains a short referral phase that checks the studio-moser marketplace is registered and auto-updating, and offers a one-time update. (3) README and `Machine_Setup.md` state the marketplace-add + auto-update step explicitly. Both plugins get a patch bump so the change itself ships; pm's `marketplace.json` version is brought back in line with its `plugin.json`.

**Tech Stack:** Markdown skill files with an embedded python3 reconcile script (existing pattern in `sync/SKILL.md`), JSON manifests, `claude plugin` CLI.

## Global Constraints

- **Repo:** `~/Projects/skills-n-stuff`, work on branch `plugin-freshness` forked from `main` (create it in Task 1 Step 1). All paths below are relative to the repo root.
- **Commit messages** end with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **`claude plugin` CLI facts (verified on claude-code 2.1.229):** `claude plugin marketplace update [name]` refreshes one or all marketplaces; `claude plugin update <plugin>` updates one plugin and prints `✔ Plugin "<name>" updated from X to Y for scope user. Restart to apply changes.` on success; `claude plugin marketplace remove <name>` also uninstalls that marketplace's plugins; `claude plugin marketplace add` has no auto-update flag. Do NOT pass `--yes` to `plugin update` — it auto-accepts a changed command for command-sourced plugins, which is a consent the user should give.
- **Auto-update fact (Claude Code docs, verbatim):** "Third-party and local development marketplaces have auto-update disabled by default." The effective flag lives in `~/.claude/plugins/known_marketplaces.json` as `autoUpdate: true` on the marketplace entry; users toggle it via `/plugin` → **Marketplaces** → the marketplace → **Enable auto-update**. Never edit `known_marketplaces.json` directly — it is Claude Code's internal store; report and instruct instead.
- **Report-and-offer, never silent removal.** Sync may install and update; it must not remove marketplaces or plugins — it prints the removal command for the user.
- **Version bumps (exact):** machine `0.4.0` → `0.4.1` in `plugins/machine/.claude-plugin/plugin.json` AND its `.claude-plugin/marketplace.json` entry. pm: `plugin.json` is `0.17.0`, `marketplace.json` entry is `0.16.1` (mismatch) → set BOTH to `0.17.1`. No other plugin's version may change.
- **Tests:** `plugins/machine/tests/run-tests.sh` must stay green (75 tests today). The Phase 2.5 script is inline in the SKILL and has no bats harness — its runnable check is a live run on this machine (Task 1 Step 5).
- **Report line format** in sync Phase 4: brace-alternative style, `{` at column 15, continuation lines indented 15 spaces (match the neighbouring `Plugins:` line).

---

## File Structure

- `plugins/machine/skills/sync/SKILL.md` — Task 1: extend the Phase 2.5 inline `plugin_reconcile_script` (update pass + orphan-marketplace report), amend the prose beneath it, and widen the Phase 4 `Plugins:` report line.
- `plugins/machine/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` — Task 1: machine 0.4.1.
- `plugins/pm/skills/setup/SKILL.md` — Task 2: new `## Phase 4.6: Plugin freshness (referral)` after Phase 4.5; Phase 8 summary line.
- `plugins/pm/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` — Task 2: pm 0.17.1 in both.
- `README.md` — Task 3: auto-update line after the marketplace-add block.
- `studio-baseline/Machine_Setup.md` — Task 3: concrete plugin commands in "## Afterwards".

---

### Task 1: `machine:sync` updates plugins and reports orphan marketplaces

**Files:**
- Modify: `plugins/machine/skills/sync/SKILL.md` (Phase 2.5 script + prose ~lines 341–437; Phase 4 report line ~917–918)
- Modify: `plugins/machine/.claude-plugin/plugin.json` (`"version": "0.4.0"` → `"0.4.1"`)
- Modify: `.claude-plugin/marketplace.json` (machine entry `0.4.0` → `0.4.1`)

**Interfaces:**
- Produces: `PLUGINS_STATE=` line shapes: `up to date` | `added N marketplace(s), installed M, updated K — restart or /reload-plugins to apply` | `skipped: claude CLI not on PATH` | `failed: <reason>`. Stderr findings: `plugin update failed: <name>: <msg>`, `marketplace update failed: <msg>`, `orphan marketplace: <name> registered here but not in shared settings — remove with: claude plugin marketplace remove <name>  (also uninstalls its plugins)`. Task 2's pm phase does not depend on this; the Phase 4 report line does.

- [ ] **Step 1: Create the branch**

```bash
cd ~/Projects/skills-n-stuff && git checkout main && git pull --rebase && git checkout -b plugin-freshness
```

- [ ] **Step 2: Extend the inline reconcile script**

In `plugins/machine/skills/sync/SKILL.md`, inside the `plugin_reconcile_script='…'` heredoc-style string, replace the tail of the script — from the line `installed_plugins = []` through the final `print(f"PLUGINS_STATE=added …")` line — with exactly:

```python
installed_plugins = []
for name, on in enabled.items():
    if not on or name in have_plugins:
        continue
    r = subprocess.run(["claude", "plugin", "install", name], capture_output=True, text=True)
    if r.returncode == 0:
        installed_plugins.append(name)
        have_plugins.add(name)
    else:
        print(f"plugin install failed: {name}: {(r.stderr or r.stdout).strip()}", file=sys.stderr)

# Update pass: refresh every marketplace, then bring each enabled plugin to the
# latest version the marketplace resolves. Third-party marketplaces have
# auto-update OFF by default, so without this a machine only ever gets the
# version it first installed.
r = subprocess.run(["claude", "plugin", "marketplace", "update"], capture_output=True, text=True)
if r.returncode != 0:
    print(f"marketplace update failed: {(r.stderr or r.stdout).strip()}", file=sys.stderr)

updated_plugins = []
for name, on in enabled.items():
    if not on or name not in have_plugins:
        continue
    r = subprocess.run(["claude", "plugin", "update", name], capture_output=True, text=True)
    out = (r.stdout or "") + (r.stderr or "")
    if r.returncode != 0:
        print(f"plugin update failed: {name}: {out.strip()}", file=sys.stderr)
    elif "updated from" in out:
        updated_plugins.append(name)

# Orphans: registered on this machine but not declared in shared settings.
# Report only — removal uninstalls the marketplace'"'"'s plugins, so the user runs it.
for name in sorted(have_marketplaces - set(marketplaces) - {"claude-plugins-official"}):
    print(f"orphan marketplace: {name} registered here but not in shared settings — remove with: claude plugin marketplace remove {name}  (also uninstalls its plugins)", file=sys.stderr)

if not added_marketplaces and not installed_plugins and not updated_plugins:
    print("PLUGINS_STATE=up to date")
else:
    print(f"PLUGINS_STATE=added {len(added_marketplaces)} marketplace(s), installed {len(installed_plugins)}, updated {len(updated_plugins)} — restart or /reload-plugins to apply")
```

Note the `'"'"'` in the orphan comment — the whole script is a single-quoted bash string, so a literal apostrophe must be written that way; keep it exactly, or drop the apostrophe (write `the marketplace plugins`). Either is acceptable; the bats-free check in Step 5 will catch a quoting mistake.

- [ ] **Step 3: Amend the prose under the script**

Directly after the paragraph that begins `Anything printed to stderr above (a failed marketplace add or plugin install)` and ends `repeat it in the report.`, add this paragraph:

```markdown
The update pass runs every time: `claude plugin marketplace update` refreshes all
registered marketplaces, then `claude plugin update <name>` runs for each enabled
plugin. This exists because third-party marketplaces have auto-update **off** by
default — a machine that only installs would stay on its first-installed version
forever. `updated K` in `PLUGINS_STATE` counts plugins whose version actually
changed; a `plugin update failed:` line is a finding. An `orphan marketplace:`
line means this machine has a marketplace registered that shared settings no
longer declare (a retired plugin's source, typically). Sync never removes it —
removal also uninstalls that marketplace's plugins — so carry the printed
`claude plugin marketplace remove <name>` command into the report for the user
to run.
```

- [ ] **Step 4: Widen the Phase 4 report line**

Change
```
  Plugins:    {up to date | added N marketplace(s), installed M — restart to apply |
               skipped: claude CLI not on PATH | failed: <reason>}
```
to
```
  Plugins:    {up to date | added N marketplace(s), installed M, updated K — restart or
               /reload-plugins to apply | skipped: claude CLI not on PATH | failed: <reason>}
  Orphans:    {none | <name> — remove with: claude plugin marketplace remove <name>}
```

- [ ] **Step 5: Runnable check — run the block once for real on this machine**

Extract and run the script exactly as the SKILL would (this performs real marketplace/plugin updates on this machine — that is the point):
```bash
cd ~/Projects/skills-n-stuff
repo="$HOME/.agents"; claude="$HOME/.claude"
awk "/^plugin_reconcile_script='/{f=1; sub(/^plugin_reconcile_script='/,\"\"); } f{ if (\$0 ~ /^'\$/) {f=0; next} print }" plugins/machine/skills/sync/SKILL.md > /tmp/plugin_reconcile_check.py
python3 -c "import ast,sys; ast.parse(open('/tmp/plugin_reconcile_check.py').read()); print('script parses')"
python3 /tmp/plugin_reconcile_check.py "$repo/claude/settings.json" "$claude/settings.local.json"; echo "exit $?"
```
Expected: `script parses`; then a `PLUGINS_STATE=…` line (either `up to date` or `… updated K …`), exit 0, and no `orphan marketplace:` line (ponytail was already removed on this machine). If `orphan marketplace:` appears for something unexpected, that is a real finding to report, not a script bug.

- [ ] **Step 6: Bump machine to 0.4.1**

```bash
cd ~/Projects/skills-n-stuff
python3 - << 'PY'
p="plugins/machine/.claude-plugin/plugin.json"; s=open(p).read(); assert '"version": "0.4.0"' in s
open(p,"w").write(s.replace('"version": "0.4.0"','"version": "0.4.1"',1))
m=".claude-plugin/marketplace.json"; s=open(m).read()
i=s.index('"name": "machine"'); j=s.index('"version": "0.4.0"', i)
open(m,"w").write(s[:j]+'"version": "0.4.1"'+s[j+len('"version": "0.4.0"'):]); print("machine 0.4.1")
PY
python3 -c "import json;print([x['version'] for x in json.load(open('.claude-plugin/marketplace.json'))['plugins'] if x['name']=='machine'])"
```
Expected: `machine 0.4.1`, `['0.4.1']`.

- [ ] **Step 7: Run the suite and commit**

```bash
cd ~/Projects/skills-n-stuff && plugins/machine/tests/run-tests.sh 2>&1 | grep -c '^ok'   # expect 75
git add plugins/machine/skills/sync/SKILL.md plugins/machine/.claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -F - << 'EOF'
machine 0.4.1: sync updates plugins and reports orphan marketplaces

Phase 2.5 now runs `claude plugin marketplace update` and `claude plugin
update <name>` for every enabled plugin, since third-party marketplaces have
auto-update off by default and an install-only reconcile leaves machines on
their first-installed version. Marketplaces registered locally but absent
from shared settings are reported with the removal command (never removed).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 2: `pm:setup` checks plugin freshness; fix pm's version mismatch

**Files:**
- Modify: `plugins/pm/skills/setup/SKILL.md` — insert `## Phase 4.6` after the `## Phase 4.5: Model-Selection Rubric (referral)` section (before the `---` that precedes `## Phase 5: Create ADR Directory`); add one line to Phase 8's summary.
- Modify: `plugins/pm/.claude-plugin/plugin.json` (`"version": "0.17.0"` → `"0.17.1"`)
- Modify: `.claude-plugin/marketplace.json` (pm entry `0.16.1` → `0.17.1`)

**Interfaces:**
- Consumes: the auto-update fact and CLI facts from Global Constraints. Nothing from Task 1.

- [ ] **Step 1: Insert Phase 4.6**

Directly before the `---` line that precedes `## Phase 5: Create ADR Directory`, insert:

````markdown
## Phase 4.6: Plugin freshness (referral)

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

- `marketplace: missing` → tell the user: `"The studio-moser marketplace isn't registered on this machine, so pm can't update. Add it with /plugin marketplace add Studio-Moser/skills-n-stuff, then enable auto-update (below)."`
- `autoupdate: off` (or `unknown`) → tell the user: `"Auto-update is off for studio-moser (Claude Code's default for third-party marketplaces), so pm won't pick up new versions on its own. Turn it on: /plugin → Marketplaces → studio-moser → Enable auto-update. Want me to pull the latest now? I'd run: claude plugin marketplace update studio-moser && claude plugin update pm@studio-moser"` — and run those two commands only if they say yes. Both need a restart or `/reload-plugins` to apply; say so.
- `marketplace: registered` and `autoupdate: on` → one line: `"studio-moser marketplace is registered and auto-updating."`

If the developer also has the `machine` plugin, `/machine:sync` runs the same update pass on every sync — mention it once, then move on.

---

````

- [ ] **Step 2: Add a summary line in Phase 8**

Find the `## Phase 8: Print Summary` section and, in the summary block it prints, add a line immediately after whatever line reports the model rubric status (search for `rubric` within that section). Add:
```
Plugin updates: {studio-moser auto-updating | auto-update OFF — enable via /plugin → Marketplaces | marketplace missing}
```
If the summary block has no rubric line, add the plugin line as the last item of the block. Match the block's existing indentation and bullet style exactly.

- [ ] **Step 3: Bump pm to 0.17.1 in both manifests**

```bash
cd ~/Projects/skills-n-stuff
python3 - << 'PY'
p="plugins/pm/.claude-plugin/plugin.json"; s=open(p).read(); assert '"version": "0.17.0"' in s
open(p,"w").write(s.replace('"version": "0.17.0"','"version": "0.17.1"',1))
m=".claude-plugin/marketplace.json"; s=open(m).read()
i=s.index('"name": "pm"'); j=s.index('"version": "0.16.1"', i)
open(m,"w").write(s[:j]+'"version": "0.17.1"'+s[j+len('"version": "0.16.1"'):]); print("pm 0.17.1")
PY
python3 -c "import json;print({x['name']:x.get('version') for x in json.load(open('.claude-plugin/marketplace.json'))['plugins'] if x['name'] in ('pm','machine')})"
grep -n '"version"' plugins/pm/.claude-plugin/plugin.json
```
Expected: `pm 0.17.1`; `{'pm': '0.17.1', 'machine': '0.4.1'}`; plugin.json shows `0.17.1`.

- [ ] **Step 4: Verify and commit**

```bash
cd ~/Projects/skills-n-stuff
grep -n '^## Phase 4.6: Plugin freshness (referral)$' plugins/pm/skills/setup/SKILL.md   # one line, between Phase 4.5 and Phase 5
grep -n '^## Phase 4.5\|^## Phase 4.6\|^## Phase 5' plugins/pm/skills/setup/SKILL.md      # ascending order
grep -c 'Plugin updates:' plugins/pm/skills/setup/SKILL.md                                # 1
claude plugin validate plugins/pm 2>&1 | tail -2                                          # no errors
git add plugins/pm/skills/setup/SKILL.md plugins/pm/.claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -F - << 'EOF'
pm 0.17.1: setup checks marketplace registration and auto-update; fix version mismatch

Phase 4.6 checks that the studio-moser marketplace is registered and
auto-updating (third-party marketplaces default to off), tells the user how
to enable it, and offers a one-time marketplace + pm update. Also brings the
marketplace.json pm entry (0.16.1) back in line with plugin.json (0.17.0) at
0.17.1 — (the mismatch was later shown to be hygiene only — `plugin.json` drives update detection).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 3: Docs — README auto-update line, Machine_Setup concrete commands

**Files:**
- Modify: `README.md` (after the marketplace-add fenced block, ~line 16)
- Modify: `studio-baseline/Machine_Setup.md` (`## Afterwards` first paragraph, ~line 473)

- [ ] **Step 1: README**

Directly after the fenced block that ends with `/plugin marketplace add ./skills-n-stuff` and its closing ``` fence, insert:

```markdown
Then turn on auto-update — Claude Code leaves it **off** by default for third-party marketplaces, so without this you stay on whatever version you first installed: `/plugin` → **Marketplaces** → `studio-moser` → **Enable auto-update**. (Or refresh by hand any time: `/plugin marketplace update studio-moser` then `/plugin update <plugin>@studio-moser`.)

```

- [ ] **Step 2: Machine_Setup.md Afterwards**

Replace the paragraph
```
Install the `machine` plugin and use `/machine:sync` for the ongoing work — it does the
link check, pull, and portability lint above on demand, and can push to other
machines. Set up model routing with `/machine:model-rubric`, or follow
[`Rubric_Setup.md`](https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/Rubric_Setup.md)
if you have no plugins.
```
with
```
Install the `machine` plugin and use `/machine:sync` for the ongoing work — it does the
link check, pull, and portability lint above on demand, keeps every plugin on the
latest marketplace version, and can push to other machines:

```bash
claude plugin marketplace add Studio-Moser/skills-n-stuff
claude plugin install machine@studio-moser
```

Then run `/machine:sync` once — it installs the rest of your plugins from the synced
`settings.json` and updates them. Turn on auto-update for `studio-moser` as well
(`/plugin` → **Marketplaces** → `studio-moser` → **Enable auto-update**; Claude Code
defaults it off for third-party marketplaces) so updates also arrive between syncs.
Set up model routing with `/machine:model-rubric`, or follow
[`Rubric_Setup.md`](https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/Rubric_Setup.md)
if you have no plugins.
```

- [ ] **Step 3: Verify and commit**

```bash
cd ~/Projects/skills-n-stuff
grep -c 'Enable auto-update' README.md studio-baseline/Machine_Setup.md    # 1 and 1
grep -c 'claude plugin install machine@studio-moser' studio-baseline/Machine_Setup.md   # 1
git add README.md studio-baseline/Machine_Setup.md
git commit -F - << 'EOF'
docs: state the auto-update toggle and the machine-plugin install commands

Third-party marketplaces default to auto-update off; the README and the
bootstrap doc now say so and show the toggle, and the bootstrap names the
two commands that get the machine plugin onto a fresh machine.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Self-review

**Spec coverage.** D1 (sync updates + orphan report) → Task 1. D2 (pm:setup freshness) → Task 2. D3 (README + Machine_Setup) → Task 3. pm version mismatch → Task 2 Step 3. Ship the change (bumps) → Tasks 1, 2. Runnable check for the only logic change → Task 1 Step 5 (live run) — the SKILL's inline script has no bats harness, matching the existing pattern; not extracting it into a script file (out of scope).

**Placeholder scan.** None. Task 2 Step 2 has a conditional ("if no rubric line…") with a concrete fallback, not a TBD.

**Name consistency.** `PLUGINS_STATE` shapes (Task 1 script vs prose vs Phase 4 line). `Orphans:` report line matches the `orphan marketplace:` stderr prefix. Versions: machine 0.4.1 (Task 1 both files), pm 0.17.1 (Task 2 both files). Phase name `## Phase 4.6: Plugin freshness (referral)` (Task 2 Steps 1 and 4).
