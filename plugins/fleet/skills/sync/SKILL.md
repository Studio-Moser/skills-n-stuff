---
name: sync
description: >-
  Make this machine match your personal agent repo — the private repo holding your
  skills, global CLAUDE.md, and shared Claude Code settings. Clones on first run;
  after that commits this machine's changes, pulls, and pushes so the repo actually
  stays current. Re-links anything that drifted back into ~/.claude, lints for paths
  that would be wrong on another machine, and optionally triggers a pull on your
  other machines. Trigger: "sync my config", "sync my machines", "update my skills from
  my repo", "is this machine up to date", or /fleet:sync.
  Do NOT use for setting up a machine that has no plugins yet (follow
  studio-baseline/Machine_Setup.md), for creating the model rubric (that's
  /fleet:model-rubric), or for anything in a project repo — sync only touches this
  developer's user-global agent config.
effort: low
allowed-tools: "Bash Read Edit"
---

# Fleet — Sync

Makes this machine match your personal agent repo.

**Default repo:** `$HOME/.agents`. If `$FLEET_REPO` is set, use that instead.

---

## Dry run

If the user asks what would change, or passes `--dry-run`, run **only the
read-only pieces** — `link-plan.sh` (Phase 1's command), Phase 2.5's MCP
verification block, Phase 2.6's read/compare/report step, and
`portability-lint.sh` (Phase 3's command) — then print the report from
Phase 4 and stop. Phase 2.5's MCP block only reads `mcp.json` and checks
whether each server's command resolves; it belongs in a dry run because
that's exactly the kind of thing someone previewing a sync wants to see.
Phase 2.6's `skills-reconcile.sh` call is the same shape: it only reads the
manifest, `.fleet-local.json`, and `npx skills list -g --json` output, and
prints findings — nothing on disk changes.

Skip everything else, explicitly:

- **Phase 2** (commit, pull, push) — writes to the repo and the remote.
- **Phase 2.5's plugin half** (marketplace add / plugin install) — installs
  software. Run only its MCP verification block, not this one.
- **Phase 2.6's installs, removals, manifest write, and `.gitignore`
  write** — everything after the `skills-reconcile.sh` call. Running
  `skills-manifest.sh` in a dry run would write real files; skip it.
- Phase 1's action column (create/re-link/remove) and Phase 3's fix
  suggestions — both are writes, not part of the dry run.

Nothing is created, installed, moved, or removed. The three pieces that do
run are read-only, so this is safe to offer unprompted when the user seems
unsure.

---

## Phase 0: Locate the repo

```bash
repo="${FLEET_REPO:-$HOME/.agents}"
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
[ -d "$repo/.git" ] && echo "found" || echo "absent"
```

`link-plan.sh` resolves `$claude` the same way internally — use this `$claude`
variable everywhere below instead of hardcoding `~/.claude` or `$HOME/.claude`,
so the skill and the script always agree on which directory is being managed.

**Each phase below may run as a separate command, in a separate shell.**
Nothing set in one command block — `repo=`, `claude=`, and later
`diff_status=`, `$diff_err`'s path — persists into the next. Re-resolve
`repo=`/`claude=` at the top of any later block that references them, rather
than assuming Phase 0's values are still set. Same rule for the diff
sequence in Phase 1: run the `diff`, the `$diff_err` check, the resulting
removal, and the `rm -f "$diff_err"` cleanup as one command block, not as
separately-issued commands — splitting them loses the temp file's path and
the `diff_status` value in between.

**absent** — first run on this machine. Ask the user for their private repo URL;
do not guess one. Then:

```bash
git clone <url> "$repo"
```

If the clone fails on authentication, say so plainly and stop — do not fall back
to another protocol without asking. A common cause is an SSH remote with no key
loaded (`ssh-add -l` reports no identities); `gh auth status` will show whether
HTTPS is the configured protocol instead.

**found** — continue.

---

## Phase 1: Link check

**Run this before pulling.** `CLAUDE.md` and `settings.json` are both rewritten by
tooling — a memory tool's bootstrap block edits one, Claude Code writes the other
on plugin toggle. A writer that does atomic-replace (temp file + rename) rather
than write-in-place silently converts a symlink back into a real file, and sync
stops working with no signal. This phase is how that gets noticed.

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/link-plan.sh" "$repo"
```

Each line ends in a state:

| state | meaning | action |
|---|---|---|
| `ok` | correct symlink | nothing |
| `ABSENT` | no such path in `$claude` | create the link |
| `REAL-FILE` | a real file (or directory — `skills` is one of the five tracked entries) sits where the link should be | **diff first** (below) |
| `RELINK(->X)` | symlink points somewhere else | show `X`, confirm, re-link |
| `MISSING-IN-REPO` | the repo has no such file | report; do not create anything |

**`mcp.json` is tracked like the rest, but the portability lint in Phase 3 doesn't
fully cover it.** That lint only flags literal `/Users/<name>` or `/home/<name>` paths;
`mcp.json` typically holds paths like `/Applications/Some.app/Contents/Helpers/Server`,
which pass the lint but are still machine-specific. Tracking it is right — the
inventory should migrate — but each server's command needs to be verified as
actually present on this machine, not assumed to be. That happens in Phase 2.5,
not here.

**`MISSING-IN-REPO` is checked first and masks the other states.** If the
repo lacks the file, `link-plan.sh` reports `MISSING-IN-REPO` for that entry
no matter what `$claude` currently has there (a real file, a drifted
symlink, or nothing) — the five states are not independent signals about
both sides at once. Don't infer "no real file exists on this machine" from a
`MISSING-IN-REPO` line.

**`RELINK(->X)` can be a false positive on a working link.** The script
compares the symlink target to the expected path as a raw string, not a
resolved path, so a symlink using a *relative* target that still resolves to
the right file also reports `RELINK`. Before re-linking, resolve `X` (e.g.
`readlink -f "$claude/<name>"`) and compare it to `$repo/<rel>`; if they
match, leave the link alone — re-linking would just churn a working link.

**On `REAL-FILE`, never overwrite silently.** That file may hold edits made on
this machine since the link broke. `skills` is a *directory*, so the diff must
be recursive:

```bash
diff_err="$(mktemp)"
diff -ru "$repo/<rel>" "$claude/<name>" 2>"$diff_err"
diff_status=$?
```

`diff_status`, not `status` — `status` is a read-only special variable in
zsh (an alias for `$?`), and assigning to it aborts the command with
`read-only variable: status` instead of setting anything. Since this skill
runs its Bash blocks through whatever shell the agent's tool uses, which may
be zsh, name it something the shell won't reject.

**First, before looking at `diff_status` at all: if `$diff_err` is
non-empty, stop and report.** Do not remove or re-link anything, and do not
fall through to the status bullets below — a stderr line means part of the
comparison didn't happen, so no status value is trustworthy:

```bash
if [ -s "$diff_err" ]; then cat "$diff_err"; rm -f "$diff_err"; exit 1; fi
```

This matters because BSD `diff -r` (macOS's default `diff`) can leave a
non-empty `diff_err` — a `diff: …: Permission denied` line from a
subdirectory it can't read — under two distinct exit codes. If that
unreadable subtree is the *only* difference, `diff -r` exits **0**
("identical") even though part of the tree was never compared, which would
otherwise walk straight into the keep/discard prompt below and `rm -r` a
tree that was never actually fully compared. If a *different*, readable part
of the same tree also genuinely differs, `diff -r` instead exits **1**
(`diff_status=1`) for that real difference, while the unreadable subtree is
still unchecked. Either exit code is untrustworthy once `diff_err` is
non-empty, which is why it's checked first and unconditionally, before
`diff_status` is read at all — removing the need to repeat the check on
every status branch.

Once `$diff_err` is confirmed empty, branch on `diff_status`:

- **`diff_status` = 0 (identical)** → remove the stray file (or `rm -r` the
  stray directory) and re-link.
- **`diff_status` = 1 (differs)** → show the diff and ask: keep the machine's
  version, or discard it. Never pick for the user. **Either way, remove the
  stray path before re-linking** — re-linking does not itself replace a real
  file or directory (see the `ln -sfn` note below), so skipping the removal
  step lands the new link inside the surviving path instead of replacing it,
  and the run reports success while the drift persists:
  - *keep, file*: `cp "$claude/<name>" "$repo/<rel>"` (commit it in the repo
    if the user wants it tracked), **then `rm "$claude/<name>"`**, then
    `ln -sfn`.
  - *keep, directory (e.g. `skills`)*: copy **contents**, not the directory
    itself — `cp -R "$claude/<name>/." "$repo/<rel>/"`. A plain
    `cp -R "$claude/<name>" "$repo/<rel>"` nests one level too deep
    (`$repo/<rel>/<name>/…`) because both sides already exist as
    directories, so the file ends up somewhere the repo's own `<rel>` path
    doesn't cover — "keep the machine's version" would silently not happen
    even though the command succeeds. **Then `rm -r "$claude/<name>"`**, then
    `ln -sfn`.
  - *discard*: **`rm -r "$claude/<name>"`**, then `ln -sfn` to the repo's
    version.
- `diff_status` >= 2 without a `diff_err` message is not expected from
  `diff`, but treat it the same as the stderr case above: stop and report,
  take no action.

**Whichever branch fires, clean up the temp file once done:**
`rm -f "$diff_err"`. All three branches above create and leave `$diff_err`
behind — this isn't specific to the `>= 2` case.

A plain `diff -u` here is a data-loss trap: non-recursive `diff` against
two directories prints only `Common subdirectories: …` and exits 0 even
when their contents differ, so the "no differences" branch would fire and
delete a `skills` tree that might hold this machine's only copy of local
edits. `-r` is required, not optional.

To create or re-link, use:

```bash
ln -sfn "$repo/<rel>" "$claude/<name>"
```

The target must be the **absolute** path `"$repo/<rel>"` — `link-plan.sh`
compares symlink targets as raw strings (see the `RELINK` false-positive note
above), so a relative target would report `RELINK` on every future run even
though it resolves correctly.

`-sfn` only repoints an **existing symlink** (that's what its `-n` guards —
it treats the destination as the link itself, not as a directory to drop the
link into). It does **not** replace a real file or a real directory: run
against a real path — including a `REAL-FILE` directory like `skills`, or a
`skills` directory left over after only *part* of a `diff_status` = 1 cleanup ran —
`ln -sfn` creates `"$claude/<name>/<basename of $repo/<rel>>"` inside the
surviving path and exits 0, reporting success while nothing was actually
replaced. The real file or directory **must be removed (or moved aside)
first**, on every branch that re-links over an existing path, not only the
symlink-to-directory case.

---

## Phase 2: Commit, pull, push

A sync that only pulls leaves this machine's changes stranded, and the repo goes
stale the moment anything here changes — which is the whole failure this skill
exists to prevent. The full cycle is **commit → pull → push**, in that order.

**Order matters.** `git pull --ff-only` refuses when incoming changes touch a
locally-modified file — precisely when you most need it to work. Committing first
removes that failure mode entirely.

### 2.1 Commit local changes

```bash
git -C "$repo" status --short
```

Clean → skip to 2.2.

Otherwise **show the developer what changed before committing** — the counts and
the paths, deletions especially:

```bash
git -C "$repo" diff --stat
git -C "$repo" status --short | grep '^.D\|^D' || true
```

Then stage everything and commit, deletions included:

```bash
git -C "$repo" add -A
git -C "$repo" commit -m "fleet: sync from {hostname} — {N} added, {M} modified, {K} deleted"
```

`add -A` is correct **here and only here**: this repo contains exactly one
developer's config and no other session is working in it. That is the opposite of
a shared project checkout, where `add -A` stages someone else's in-flight work.

Write a message that says what actually changed — `{N} skills updated`,
`settings.json`, `impeccable 3.9.1 → 4.0.4` — not a bare timestamp. This is the
only record of why the config moved.

**Deletions are committed too.** A skill manager consolidating or removing skills
produces deletions, and holding them back is what leaves the repo stale. Everything
here is recoverable from git history, so a wrong auto-commit costs a revert, not
data. If a human is present and the deletions look wrong, they can say so — but do
not block an unattended run waiting for an answer nobody will give.

### 2.2 Pull

```bash
git -C "$repo" pull --ff-only
```

**If this fails, another machine has pushed work that diverges from this one's.
Stop. Do not rebase, merge, or force anything.** Report the divergence and skip
Phase 2.3 — resolving conflicting config across machines needs a human, and an
unattended rebase can leave the repo mid-rebase with no one to finish it.

Local work is already committed at this point, so nothing is at risk; it is simply
unpushed until someone resolves it. Say that plainly in the report so it does not
read as data loss.

### 2.3 Push

```bash
git -C "$repo" push
```

Skip if 2.2 failed. If the push is rejected, report it and stop — do not retry
with force.

**Skip this whole phase if the repo has no remote.** Say so once in the report:
without a remote, this machine is versioned but nothing syncs anywhere.

---

## Phase 2.5: Reconcile installed plugins and MCP servers

The repo is current now (Phase 2 committed, pulled, and pushed it), so this
phase reads the tracked config as the source of truth for what *should* be on
this machine and reconciles reality against it — installing what's missing for
plugins, only reporting for MCP servers.

### Plugins — install what's missing, automatically

The inventory is already in the tracked `settings.json` — read the **repo's**
copy (`$repo/claude/settings.json`), the same file the MCP check below reads
`mcp.json` from, not the possibly-drifted live file at `$claude/settings.json`
(Phase 1 runs first and would have already flagged or fixed any such drift,
but reading the repo copy here keeps both halves of this phase consistent on
principle rather than by coincidence). `extraKnownMarketplaces` names the
marketplaces this developer's config expects; `enabledPlugins` names the
plugins. **Merge `settings.local.json` over it** — `settings.local.json` is
never tracked (it's machine-local by design, per the "keep machine-local
things local" table), so it's always read from `$claude`, live. A local
`false` for a plugin the shared file marks `true` is a deliberate per-machine
override (how a local fork wins over a marketplace plugin of the same name),
and installing it anyway would overwrite that choice. Local wins.

```bash
repo="${FLEET_REPO:-$HOME/.agents}"
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

plugin_reconcile_script='import json, re, shutil, subprocess, sys

def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}

if shutil.which("claude") is None:
    print("PLUGINS_STATE=skipped: claude CLI not on PATH")
    raise SystemExit(0)

settings = load(sys.argv[1])
local = load(sys.argv[2])

marketplaces = settings.get("extraKnownMarketplaces", {})
enabled = dict(settings.get("enabledPlugins", {}))
enabled.update(local.get("enabledPlugins", {}))  # local wins over shared

def names(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        cmd_str = " ".join(cmd)
        print(f"PLUGINS_STATE=failed: running {cmd_str} exited {r.returncode}: {(r.stderr or r.stdout).strip()}")
        raise SystemExit(0)
    return {m.group(1) for m in re.finditer(r"❯\s+(\S+)", r.stdout)}

have_marketplaces = names(["claude", "plugin", "marketplace", "list"])
have_plugins = names(["claude", "plugin", "list"])

added_marketplaces = []
for name, cfg in marketplaces.items():
    if name in have_marketplaces:
        continue
    repo = cfg.get("source", {}).get("repo")
    if not repo:
        continue
    r = subprocess.run(["claude", "plugin", "marketplace", "add", repo], capture_output=True, text=True)
    if r.returncode == 0:
        added_marketplaces.append(name)
        have_marketplaces.add(name)
    else:
        print(f"marketplace add failed: {name} ({repo}): {(r.stderr or r.stdout).strip()}", file=sys.stderr)

installed_plugins = []
for name, on in enabled.items():
    if not on or name in have_plugins:
        continue
    r = subprocess.run(["claude", "plugin", "install", name], capture_output=True, text=True)
    if r.returncode == 0:
        installed_plugins.append(name)
    else:
        print(f"plugin install failed: {name}: {(r.stderr or r.stdout).strip()}", file=sys.stderr)

if not added_marketplaces and not installed_plugins:
    print("PLUGINS_STATE=up to date")
else:
    print(f"PLUGINS_STATE=added {len(added_marketplaces)} marketplace(s), installed {len(installed_plugins)} — restart to apply")
'

printf '%s\n' "$plugin_reconcile_script" | python3 - "$repo/claude/settings.json" "$claude/settings.local.json"
```

`names()` fails closed: a non-zero exit from `claude plugin list` or
`claude plugin marketplace list` reports `PLUGINS_STATE=failed: ...` and
stops rather than treating empty/error output as "nothing installed," which
would otherwise try to install everything. The `claude` CLI itself missing
from `$PATH` is checked up front the same way, before any subprocess call.

Anything printed to stderr above (a failed marketplace add or plugin install)
is a finding — carry it into the Phase 4 report the same way an unfixed lint
finding is carried, never silently. **Plugin installs need a restart to take
effect** — the `PLUGINS_STATE` line already says so whenever it installed
anything; repeat it in the report.

### MCP servers — verify, report, never auto-install

Read the tracked `claude/mcp.json` (skip cleanly if absent — not every
developer runs MCP servers). For each entry under `mcpServers`, confirm its
`command` actually resolves on this machine: an absolute path must be
executable, a bare name must resolve on `$PATH`. **Do not attempt to install
anything here** — an MCP entry points at an arbitrary binary (an app bundle, a
local CLI, a script); there is no generic install, and guessing a package
manager would be worse than a clear message naming what to install by hand.
Also honour `disabledMcpjsonServers` in `settings.local.json` — a server
disabled on this machine is not a finding.

```bash
repo="${FLEET_REPO:-$HOME/.agents}"
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

mcp_reconcile_script='import json, os, shutil, sys

def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}

mcp_path, local_path = sys.argv[1], sys.argv[2]
if not os.path.exists(mcp_path):
    print("MCP_STATE=not tracked")
    raise SystemExit(0)

servers = load(mcp_path).get("mcpServers", {})
disabled = set(load(local_path).get("disabledMcpjsonServers", []))

active = {n: c for n, c in servers.items() if n not in disabled}
unresolved = []
remote = 0
for name, cfg in active.items():
    cmd = cfg.get("command", "")
    if not cmd:
        # URL/SSE-style server: no local command to verify, so it is neither
        # checked nor "ok" — count it separately rather than folding it into
        # a verified count it never earned.
        remote += 1
        continue
    ok = os.access(cmd, os.X_OK) if cmd.startswith("/") else shutil.which(cmd) is not None
    if not ok:
        unresolved.append((name, cmd))

ok_count = len(active) - remote - len(unresolved)
parts = [f"{ok_count} ok"]
if remote:
    parts.append(f"{remote} remote (no local command)")
if unresolved:
    parts.append(f"{len(unresolved)} unresolved")
print("MCP_STATE=" + ", ".join(parts))
for name, cmd in unresolved:
    print(f"MCP_FINDING={name} → {cmd} (not present on this machine)")
'

printf '%s\n' "$mcp_reconcile_script" | python3 - "$repo/claude/mcp.json" "$claude/settings.local.json"
```

Report any unresolved server, naming the server and the missing command, e.g.
`shelby-memory → /Applications/Shelby.app/Contents/Helpers/ShelbyMCP (not
present on this machine)`.

---

## Phase 2.6: Reconcile third-party skills

**The store.** `$repo/skills/<name>` holds the real code for a skill; `$claude/skills`
is a symlink to it, so this developer's other agent config already reads it
directly — Phase 1 covers that link like any other tracked entry. Some of
those skills are authored right here in the repo; others are installed from
elsewhere with `npx skills` (vercel-labs) and should be *declared*, not
vendored. `npx skills list -g --json` reports every skill on this machine
across every agent, each with a `source` field — `null` for locally-authored
skills, `"owner/repo"` for an installed third-party one. That field is the
only thing that tells the two apart; a skill's own files don't say where it
came from.

`$repo/skills.manifest` is the developer's **declared** set of third-party
skills — one `name<TAB>source` line each, sorted, generated, never
hand-edited. It's regenerated from reality at the end of this phase, so a
skill removed by any means (this machine, another machine, or by hand)
simply disappears from the next regeneration. Other agents (Cursor, Pi,
Codex) symlink into the same store and manage themselves — never touch
`~/.cursor`, `~/.pi`, or `~/.codex`, and the manifest only ever covers
entries whose `path` falls under `$repo/skills/`.

**Guard first — this phase needs `npx` and `node`:**

```bash
command -v npx >/dev/null 2>&1 && command -v node >/dev/null 2>&1 \
  || echo "SKILLS_STATE=skipped: npx/node not on PATH"
```

If that printed, skip the rest of this phase, carry `SKILLS_STATE=skipped:
...` into the Phase 4 report, and move on to Phase 3. Never let a missing
`npx` traceback into the middle of a sync.

**Order matters, which is why this phase is five numbered steps run in this
exact sequence, not whatever order is convenient:**

1. Read the committed manifest.
2. Install anything it declares that isn't on this machine yet.
3. Detect **extras** — installed here, not declared.
4. Detect **removals** — the same signal as step 3, read the other way (below).
5. Only now, regenerate the manifest and `.gitignore` block from reality.

Regeneration has to come **last**. It captures whatever `npx skills list`
reports *at the moment it runs* — if that moment is before steps 2–4 have
changed this machine to match the manifest (the common case: a fresh
machine with an empty `skills/` directory), regenerating would capture that
empty state, overwrite the committed manifest with nothing, and the
developer's declaration is gone. Steps 2–4 have to change reality first;
step 5 only ever records reality as it now stands.

### 1–2. Read the manifest, install what's missing

```bash
repo="${FLEET_REPO:-$HOME/.agents}"
listing="$(npx skills list -g --json 2>/dev/null)" \
  || { echo "SKILLS_STATE=failed: npx skills list -g --json"; }
plan="$(printf '%s' "$listing" | "$CLAUDE_PLUGIN_ROOT/scripts/skills-reconcile.sh" "$repo")"
printf '%s\n' "$plan"
```

`skills-reconcile.sh` reads the committed `skills.manifest` (absent file →
treated as empty — a first run, not an error) and `.fleet-local.json`
(absent → no overrides), diffs both against the `listing` JSON, and prints
one line per finding: `INSTALL`, `SKIP-INSTALL`, `EXTRA`, or `KEEP-LOCAL`
(tab-separated: kind, name, and source where relevant). It writes nothing —
the same read-only-report role `link-plan.sh` plays for Phase 1.

Act on every `INSTALL` line:

```bash
repo="${FLEET_REPO:-$HOME/.agents}"
printf '%s\n' "$plan" | while IFS=$'\t' read -r kind name source; do
  [ "$kind" = "INSTALL" ] || continue
  npx skills add "$source" -s "$name" -g -y \
    && echo "installed: $name ($source)" \
    || echo "install failed: $name ($source) — offer to add to skipInstall (see overrides)"
done
```

Report every `SKIP-INSTALL` line too — the developer (or a previous run)
already declined this one; do not attempt it and do not re-ask.

### 3–4. Extras and removals — one detection, one offer

An `EXTRA` line names a skill that's on this machine, has a real `source`,
and isn't in the manifest. That single fact has two equally plausible
stories behind it — it was just installed here and never declared, or it
*was* declared and the developer removed it from the manifest on another
machine, and this machine hasn't caught up yet ("the manifest lost an
entry" while the skill itself is still sitting in `$repo/skills/`). Nothing
in the data distinguishes those two stories, so this phase doesn't try to —
it asks once, with both outcomes on the table:

- **Add to the manifest** (the normal case) — no action needed now; the
  skill is already in `listing`, so step 5's regeneration picks it up.
- **Remove it** — `npx skills remove <name> -g -y`.
- **Neither, for now** — legitimate; record the decline so sync stops
  asking every run (see overrides, below).

### Overrides

`$repo/.fleet-local.json` records deliberate per-machine deviations so a
decline doesn't get re-asked forever:

```json
{"skipInstall": ["name", "…"], "keepLocal": ["name", "…"]}
```

- `skipInstall` — declared in the manifest, deliberately not wanted on this
  machine. Usually hand-edited directly (a developer knows in advance a
  heavy skill only belongs on one machine); also offer to add a name here
  when its `INSTALL` attempt above fails, so a broken or unwanted source
  isn't retried every run.
- `keepLocal` — present on this machine, deliberately left undeclared. Add a
  name here when the extras offer above is declined outright.

To add a name, load the file (treat absent as `{"skipInstall": [],
"keepLocal": []}`), append if not already present, keep each array sorted,
and write it back:

```bash
repo="${FLEET_REPO:-$HOME/.agents}"

override_script='import json, sys

path, kind, name = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
data.setdefault("skipInstall", [])
data.setdefault("keepLocal", [])
if name not in data[kind]:
    data[kind].append(name)
    data[kind].sort()
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
'

printf '%s\n' "$override_script" | python3 - "$repo/.fleet-local.json" keepLocal "<name>"
```

Use `kind=skipInstall` for a declined/failed install instead. `.fleet-local.json`
is machine-local by design — it must never be committed; `skills-manifest.sh`
(step 5) keeps it gitignored in the static part of `.gitignore`, outside the
generated block.

**Report deviations once per run**, even when nothing changed this time —
otherwise a standing decline becomes invisible permanent state:

```
Skills local deviations: skipInstall <name>, … | keepLocal <name>, … | none
```

### 5. Regenerate — only after 2–4 have run

```bash
repo="${FLEET_REPO:-$HOME/.agents}"
npx skills list -g --json 2>/dev/null | "$CLAUDE_PLUGIN_ROOT/scripts/skills-manifest.sh" "$repo"
```

Deliberately a **fresh** `npx skills list -g --json` call, not the `$listing`
captured in steps 1–2 — installs and removals in steps 2–4 changed reality
since then, and regenerating from a stale `$listing` would write back
exactly the drift this phase exists to fix. `skills-manifest.sh` filters to
entries with a non-null `source` under `$repo/skills/`, writes the sorted
`name<TAB>source` manifest, and rewrites the `# fleet:skills start` … `# fleet:skills
end` block in `.gitignore` to match — one `skills/<name>/` line per entry —
without touching anything else in that file.

---

## Phase 3: Portability lint

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/portability-lint.sh" "$repo"
```

Non-zero exit means something tracked in the repo carries a machine-specific
absolute path. This matters more than it looks: a hardcoded `/Users/<name>` makes
a synced config silently **wrong** on another machine rather than merely absent,
which is much harder to notice than a missing file.

Two findings and their fixes:

- `literal home path` in a file → replace with `$HOME`, or
  `${XDG_CONFIG_HOME:-$HOME/.config}` for config paths.
- `absolute symlink target` → re-point the link relatively, or drop it if it
  reaches outside the repo.

Offer to fix each one, showing the edit. If the user declines, carry the finding
into the report — never fail silently.

**Also check hook guards.** For any hook in `claude/settings.json` invoking a binary
that may not exist on every machine, confirm it is guarded:

```sh
[ -x "$HOME/.tool/bin/hook" ] && "$HOME/.tool/bin/hook" args || true
```

Unguarded, it errors on every event on machines without that tool.

---

## Phase 4: Report

```
Fleet sync — {repo}

  Links:      {N} ok, {M} relinked, {K} need attention
  Committed:  {nothing local | <short message>: N added, M modified, K deleted}
  Pull:       {up to date | N commits: <oneline list> | DIVERGED — not pushed}
  Push:       {pushed <sha> | skipped: <reason> | no remote configured}
  Plugins:    {up to date | added N marketplace(s), installed M — restart to apply |
               skipped: claude CLI not on PATH | failed: <reason>}
  MCP:        {N ok | N ok, M remote (no local command) | N ok, M unresolved: <names>}
  Skills:     {N declared, M installed, K extra | up to date |
               skipped: npx/node not on PATH | failed: <reason>}
  Lint:       {clean | N finding(s), M fixed}

{Skills local deviations line, only when skipInstall or keepLocal is non-empty}
{any unresolved finding, one per line}
```

If anything is unresolved, say so in the summary line — do not report success with
open findings buried above. That includes a failed marketplace add or plugin
install from Phase 2.5, `claude` missing from `$PATH`, or `claude plugin list` /
`claude plugin marketplace list` itself failing (report any of these the same as
an unfixed lint finding), any MCP server whose command didn't resolve (list
each as `<name> → <command> (not present on this machine)` alongside the other
unresolved findings), and any Phase 2.6 `install failed` or `npx skills remove`
failure. A server with no `command` (a URL/SSE-style server) is not a finding —
it's counted separately as "remote," never folded into "ok."

**Never report a sync as complete when the push did not happen.** A diverged pull,
a rejected push, or a missing remote all mean this machine's changes have not
reached anywhere else, and the next machine to sync will get the old state. That is
the exact failure this skill exists to prevent, so it belongs in the first line of
the report, not buried in a field.

**On a first run only** (Phase 0 reported `absent` and you cloned), add one line
after the report: nothing runs this skill automatically, so drift goes unnoticed
until someone runs it again. Offer to set up a recurring `/fleet:sync` with
whichever scheduler they already use — their agent tool's scheduled tasks, `cron`,
`launchd`. Daily is plenty. Ask which they prefer; do not pick one, and do not
install anything unasked. Say it once and drop it — repeating this on every sync
is noise.

---

## Phase 5: Push (optional)

Only if `$repo/fleet.yml` exists. Skip this phase entirely otherwise; never
create `fleet.yml` unprompted.

```yaml
# fleet.yml
machines:
  - host: studio-mini      # ssh target: a Host from ~/.ssh/config, or user@addr
  - host: laptop
```

```bash
command -v yq >/dev/null 2>&1 || { echo "yq not found — install it to use Phase 5 (push)."; exit 1; }
yq -r '.machines[].host' "$repo/fleet.yml"
```

Confirm the host list with the user, then for each:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 "$host" 'cd "${FLEET_REPO:-$HOME/.agents}" && git pull --ff-only' 2>&1
```

The remote path expression matches Phase 0's local resolution (`$FLEET_REPO`
if the remote machine has it set, else `$HOME/.agents`) rather than a
hardcoded `~/.agents`, so pushing is consistent with how this machine finds
its own repo.

- Unreachable → report and continue to the next host. One offline machine is not
  a failure of the run.
- Non-zero exit → report that host's output verbatim.

**Be honest about what this proves.** A remote `git pull` says the remote repo
advanced. It does **not** confirm the remote machine re-linked correctly — that
needs `fleet:sync` run there. Report what was attempted, not what succeeded:

```
Pushed to {N}/{M} machines. {list}
Unreachable: {list}
A pull is not a relink — run /fleet:sync on a machine if its links may have drifted.
```
