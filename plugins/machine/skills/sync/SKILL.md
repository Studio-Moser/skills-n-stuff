---
name: sync
description: >-
  Make this machine match your personal agent repo — the private repo holding your
  skills, global CLAUDE.md, and shared Claude Code settings. Clones on first run;
  after that commits this machine's changes, pulls, and pushes so the repo actually
  stays current. Re-links anything that drifted back into ~/.claude, lints for paths
  that would be wrong on another machine, and optionally triggers a pull on your
  other machines. Trigger: "sync my config", "sync my machines", "update my skills from
  my repo", "is this machine up to date", or /machine:sync.
  Do NOT use for setting up a machine that has no plugins yet (follow
  studio-baseline/Machine_Setup.md), for creating the model rubric (that's
  /machine:model-rubric), or for anything in a project repo — sync only touches this
  developer's user-global agent config.
effort: low
allowed-tools: "Bash Read Edit"
---

# Machine — Sync

Makes this machine match your personal agent repo.

**Default repo:** `$HOME/.agents`. If `$AGENTS_REPO` is set, use that instead.

---

## Dry run

If the user asks what would change, or passes `--dry-run`, run **only the
read-only pieces** — `link-plan.sh` (Phase 1's command), Phase 2.5's MCP
verification block, Phase 2.6's step 0 *detection* block (the `git
ls-files --error-unmatch` tracked-check and the `.gitignore` presence
check — not the fix block right after it) and step 1 (the
`skills-reconcile.sh` call, nothing that follows it),
`portability-lint.sh` (Phase 3's command), and `rubric-audit.sh` (Phase 3.5's
command — it only reads transcripts) — then print the report from
Phase 4 and stop. Phase 2.5's MCP block only reads `mcp.json` and checks
whether each server's command resolves; it belongs in a dry run because
that's exactly the kind of thing someone previewing a sync wants to see.
Phase 2.6's step 0 detection and step 1 are the same shape: `git ls-files
--error-unmatch` and `grep` only read, and `skills-reconcile.sh` only
reads the manifest, `.fleet-local.json`, and `npx skills list -g --json`
output — all of them print findings without touching disk.

Skip everything else, explicitly:

- **Phase 2** (commit, pull, push) — writes to the repo and the remote.
- **Phase 2.5's plugin half** (marketplace add / plugin install) — installs
  software. Run only its MCP verification block, not this one.
- **Phase 2.6's step 0 fix block** (the `.gitignore` write, `git rm
  --cached`, commit, push) — a write, and a one-time repo migration, not
  something a preview should perform. Only step 0's detection block above
  it belongs in a dry run.
- **Phase 2.6's step 2 (installs, removals, override writes) and step 3
  (the `skills-manifest.sh` regeneration)** — running either would write
  real files or install real software; skip both. Only step 1's read/
  compare/report belongs in a dry run.
- Phase 1's action column (create/re-link/remove) and Phase 3's fix
  suggestions — both are writes, not part of the dry run.

Nothing is created, installed, moved, or removed. The three pieces that do
run are read-only, so this is safe to offer unprompted when the user seems
unsure.

---

## Phase 0: Locate the repo

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
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
machine="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/machine/*/ 2>/dev/null | sort -V | tail -1)}"; machine="${machine%/}"
"$machine/scripts/link-plan.sh" "$repo"
```

Each line ends in a state:

| state | meaning | action |
|---|---|---|
| `ok` | correct symlink | nothing |
| `ABSENT` | no such path in `$claude` | create the link |
| `REAL-FILE` | a real file (or directory — `skills`, `output-styles`, and `studio-moser` are directories among the seven tracked entries) sits where the link should be | **diff first** (below) |
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

**The `studio-moser` entry lives under `${XDG_CONFIG_HOME:-$HOME/.config}`, not `$claude`.**
For it, the link is `"${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser"` and the target is
`"$repo/config/studio-moser"`. Create the parent first — `mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}"` —
a fresh machine may not have it. The REAL-FILE diff/keep/merge procedure applies to it exactly
as it does to `skills` (both are directories). When keeping the machine's copy, also ensure
`$repo/.gitignore` covers `config/studio-moser/*.bak*` so local backup files never sync.

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
git -C "$repo" commit -m "machine: sync from {hostname} — {N} added, {M} modified, {K} deleted"
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
repo="${AGENTS_REPO:-$HOME/.agents}"
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
repo="${AGENTS_REPO:-$HOME/.agents}"
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

**The store.** `npx skills` (vercel-labs) hardcodes its install directory to
`$HOME/.agents/skills` — it never looks at `$AGENTS_REPO`. When this
developer's repo *is* `$HOME/.agents` (the default), `$repo/skills/<name>`
holds the real code for a skill and `$claude/skills` is a symlink to it, so
other agent config already reads it directly (Phase 1 covers that link like
any other tracked entry). Some skills are authored right here in the repo;
others are installed from elsewhere with `npx skills` and should be
*declared*, not vendored. `npx skills list -g --json` reports every skill on
this machine across every agent, each with a `source` field — `null` for
locally-authored skills, `"owner/repo"` for an installed third-party one.
That field is the only thing that tells the two apart; a skill's own files
don't say where it came from.

`$repo/skills.manifest` is the developer's **declared** set of third-party
skills — one `name<TAB>source` line each, sorted, generated, never
hand-edited. It's regenerated from reality at the end of this phase, so a
skill removed by any means (this machine, another machine, or by hand)
simply disappears from the next regeneration. Other agents (Cursor, Pi,
Codex) symlink into the same store and manage themselves — never touch
`~/.cursor`, `~/.pi`, or `~/.codex`, and the manifest only ever covers
entries whose `path` falls under `$HOME/.agents/skills/`.

### 0. One-time migration: untrack `.skill-lock.json`

`npx skills` writes its own lockfile, `.skill-lock.json`, and reads a
skill's `source` back *from that lockfile* — not by inspecting the skill
itself. If this repo tracks it, the failure mode is silent and exactly the
kind this phase exists to prevent: machine A removes a skill, its lock
entry goes with it and that removal gets committed; machine B pulls, but
`skills/<name>` is gitignored so the pull can't delete the now-untracked
directory that's still sitting there from before; `npx skills list` on B
now reports that skill's `source` as `null` (nothing in *its* lockfile
mentions it); this phase's filter correctly drops null-source entries,
so regeneration silently removes it from `.gitignore` — and the next
`git add -A` vendors the third-party code right back into the repo.
Untracked, each machine's lockfile reflects only its own reality, so a
removal shows up as exactly what it is: a manifest entry that's gone while
the skill is still on disk here, i.e. an `EXTRA` — offered for removal like
any other, in step 2 below.

**Detect first — read-only, dry-run safe:**

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
gitignore="$repo/.gitignore"

git -C "$repo" ls-files --error-unmatch .skill-lock.json >/dev/null 2>&1 \
  && echo "TRACKED" || echo "not tracked"

for line in ".fleet-local.json" ".skill-lock.json"; do
  grep -qxF "$line" "$gitignore" 2>/dev/null && echo "gitignored: $line" || echo "missing from .gitignore: $line"
done
```

If it printed `not tracked` and both lines `gitignored: ...`, this repo has
already migrated (or never vendored it) — move on, nothing to fix.

Otherwise, explain the above and fix everything this step is responsible
for in one write:

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
gitignore="$repo/.gitignore"
for line in ".fleet-local.json" ".skill-lock.json"; do
  grep -qxF "$line" "$gitignore" 2>/dev/null || printf '%s\n' "$line" >> "$gitignore"
done

git -C "$repo" add .gitignore
git -C "$repo" rm --cached .skill-lock.json --ignore-unmatch -q
if git -C "$repo" diff --cached --quiet; then
  echo "nothing to commit"
else
  git -C "$repo" commit -q -m "machine: untrack .skill-lock.json and gitignore it (breaks third-party skill removal propagation)"
  git -C "$repo" push || echo "push failed — will retry on a future sync; do not force"
fi
```

**The gitignore lines are written here, unconditionally — not only by step
3.** Step 3 (and the gitignore lines it maintains) is skipped whenever
`npx`/`node` is missing or `$repo` isn't `$HOME/.agents`. On such a
machine, untracking `.skill-lock.json` without also gitignoring it here
would leave it an untracked file sitting in the worktree — the next sync's
Phase 2 commit (`git add -A`, correct in that phase, see its own note)
stages and commits it right back, every single run. Step 0 runs
unconditionally, so its fix has to be self-contained rather than depend on
a step that might not run this time. `--ignore-unmatch` keeps the fix block
safe to run even when only the `.gitignore` lines were missing and
`.skill-lock.json` was never tracked. `skills-manifest.sh` (step 3 below)
also ensures both lines are present as a second, idempotent pass whenever
it does run — harmless overlap, not a second source of truth.

### Guard — the rest of this phase needs `npx`, `node`, and `$repo` at exactly `$HOME/.agents`

```bash
command -v npx >/dev/null 2>&1 && command -v node >/dev/null 2>&1 \
  || echo "SKILLS_STATE=skipped: npx/node not on PATH"
```

If that printed, skip everything below, carry `SKILLS_STATE=skipped: ...`
into the Phase 4 report, and move on to Phase 3. Never let a missing `npx`
traceback into the middle of a sync.

`skills-manifest.sh` and `skills-reconcile.sh` each carry a second guard
internally: if `$repo` isn't exactly `$HOME/.agents` (an overridden
`$AGENTS_REPO`), every real install's `path` fails to match the hardcoded
store from the section above, which would otherwise make everything look
uninstalled and regenerate an empty manifest. Both scripts print their own
`SKILLS_STATE=skipped: ...` and exit 0 without touching any file in that
case — surface that line the same way.

**Order matters, which is why this phase is numbered steps run in this
exact sequence, not whatever order is convenient:**

1. Read the committed manifest and compare it to reality.
2. Offer to install what it declares that isn't here, and offer to resolve
   what's here that it doesn't declare.
3. Only now, regenerate the manifest and `.gitignore` block from reality.

Regeneration has to come **last**. It captures whatever `npx skills list`
reports *at the moment it runs* — if that moment is before step 2 has
changed this machine to match the developer's choices (the common case: a
fresh machine with an empty `skills/` directory), regenerating would
capture that empty state, overwrite the committed manifest with nothing,
and the developer's declaration is gone. Step 2 has to change reality
first; step 3 only ever records reality as it now stands.

### 1. Read the manifest, compare to reality

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
machine="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/machine/*/ 2>/dev/null | sort -V | tail -1)}"; machine="${machine%/}"
listing="$(npx skills list -g --json 2>/dev/null)"
if [ -z "$listing" ] || ! printf '%s' "$listing" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1; then
  echo "SKILLS_STATE=failed: npx skills list -g --json produced no parseable output"
else
  printf '%s' "$listing" | "$machine/scripts/skills-reconcile.sh" "$repo"
fi
```

Checking `$listing` is valid JSON *before* piping it anywhere matters: `npx`
being on `$PATH` doesn't mean the command succeeds — offline, a registry
error, or a truncated pipe all leave `$listing` empty or garbage, and
piping that straight into a script that calls `json.load` would traceback
instead of failing cleanly. If `SKILLS_STATE=failed` printed, stop — do not
proceed to step 2 or step 3 this run.

Otherwise, `skills-reconcile.sh` reads the committed `skills.manifest`
(absent file → treated as empty — a first run, not an error) and
`.fleet-local.json` (absent → no overrides), diffs both against `listing`,
and prints one line per finding, tab-separated:

| kind | means |
|---|---|
| `INSTALL <name> <source>` | manifest declares it, not on this machine — offer to install |
| `SKIP-INSTALL <name>` | same, but a previous decline (or a hand-edit) says leave it |
| `EXTRA <name> <source>` | on this machine, not in the manifest — offer add/remove |
| `KEEP-LOCAL <name>` | same, but a previous decline says leave it undeclared |

It writes nothing — the same read-only-report role `link-plan.sh` plays for
Phase 1. **This is the entire plan.** Read it here; don't try to carry it
in a shell variable into a later command block — nothing set in one block
persists into the next (see Phase 0), and a block that references a `$plan`
set two blocks ago runs against an empty variable with no error. Every
action below either runs in this same block or uses the literal `name`/
`source` values already visible in this output.

### 2. Offer, don't assume — installs and extras are symmetric

Both `INSTALL` and `EXTRA` lines are **offers**, not automatic actions —
the same shape either way: this machine's third-party skills disagree with
the manifest, and only the developer knows which side is right this time.

**For each `INSTALL <name> <source>` line**, ask whether to install it. If
yes:

```bash
npx skills add "<source>" -s "<name>" -a claude-code -g -y
```

`-a claude-code` matters, and the value is exact — verified against the
installed CLI: without an explicit agent, `npx skills add` registers the
skill with every agent it detects, writing into `~/.cursor`, `~/.pi`, and
`~/.codex` — the exact directories this plugin must never touch, since
those agents manage their own registrations. `-a claude` (no `-code`) is
**not** a valid agent name for this CLI — it prints `Invalid agents: claude`,
exits 1, and installs nothing, which silently empties the store and makes
step 3 regenerate a 0-byte manifest. Use `-a claude-code`, exactly.

If the install command fails (network, registry, bad source, or any other
non-zero exit) that's a **failure**, not a decline — report `install
failed: <name> (<source>)` as an unresolved finding, same as an unfixed
lint finding. **Remember this name** — literally, in this conversation, the
same way step 1's plan is read rather than carried in a shell variable —
and pass it to step 3 below so a transient failure doesn't silently
un-declare the skill; don't write anything to overrides for it, since a
decline and a failure must stay distinguishable (see Overrides, below, and
step 3's manifest-preservation rule).

If the developer instead **declines** the install — a deliberate "not on
this machine" — that's not a failure, record it so sync stops asking:
`skipInstall` (see Overrides, below).

**For each `EXTRA <name> <source>` line**, ask whether to add it to the
manifest, remove it, or leave it undeclared. That single fact — installed
here, real source, not declared — has two equally plausible stories behind
it: it was just installed here and never declared, or it *was* declared and
the developer removed it from the manifest on another machine, and this
machine hasn't caught up yet. Nothing in the data distinguishes those two
stories, so this phase doesn't try to — it asks once, with all three
outcomes on the table:

- **Add to the manifest** (the normal case) — no action needed now; the
  skill is already in `listing`, so step 3's regeneration picks it up.
- **Remove it** — `npx skills remove "<name>" -a claude-code -g -y`. If
  this fails, report `remove failed: <name>` as an unresolved finding — a
  different state from a decline, and it should read differently.
- **Leave it undeclared, for now** — a deliberate decline; record it:
  `keepLocal` (see Overrides, below).

**Report every `SKIP-INSTALL` and `KEEP-LOCAL` line too** — a previous
decline, already recorded; do not act on it and do not re-ask.

### Overrides

`$repo/.fleet-local.json` records deliberate per-machine deviations so a
decline doesn't get re-asked forever:

```json
{"skipInstall": ["name", "…"], "keepLocal": ["name", "…"]}
```

- `skipInstall` — declared in the manifest, deliberately not wanted on this
  machine. Reached by declining an install offer above; also fine to
  hand-edit directly when a developer already knows in advance that a
  heavy skill only belongs on one machine.
- `keepLocal` — present on this machine, deliberately left undeclared.
  Reached by declining an extras offer above.

An **install failure** or a **remove failure** is never written to either
array — those are unresolved findings that should keep surfacing until
fixed, not silenced. Only an explicit decline goes into overrides.

To add a name, load the file (treat absent as `{"skipInstall": [],
"keepLocal": []}`), append if not already present, keep each array sorted,
and write it back:

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"

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

Use `kind=skipInstall` for a declined install instead. `.fleet-local.json`
is machine-local by design — it must never be committed; `skills-manifest.sh`
(step 3) keeps both it and `.skill-lock.json` gitignored in the static part
of `.gitignore`, outside the generated block.

**Report deviations once per run, always** — with a `none` fallback when
both arrays are empty, not only when something's there. Otherwise a
standing decline becomes invisible permanent state the moment it stops
being new:

```
Skills local deviations: skipInstall <name>, … | keepLocal <name>, … | none
```

### 3. Regenerate — only after step 2 has run

**The manifest is the shared declaration; `skipInstall` and a this-run
install failure are this machine's local reasons a declared entry isn't
here.** A local reason must never edit the shared declaration. So this
step's output is the *union* of: third-party skills actually present in
the store right now, **plus** entries already in the committed manifest
that are absent here *for a recorded reason* — `skipInstall`, or named as a
failed install in step 2 above. An entry absent with no recorded reason at
all is a genuine removal and correctly drops out — that's the only case
this step is allowed to un-declare something.

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
machine="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/machine/*/ 2>/dev/null | sort -V | tail -1)}"; machine="${machine%/}"
listing="$(npx skills list -g --json 2>/dev/null)"
if [ -z "$listing" ] || ! printf '%s' "$listing" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1; then
  echo "SKILLS_STATE=failed: npx skills list -g --json produced no parseable output — manifest not regenerated"
else
  printf '%s' "$listing" | "$machine/scripts/skills-manifest.sh" "$repo" <failed-name> <failed-name> ...
fi
```

Pass every name step 2 reported as `install failed:` this run as a trailing
argument, literally — the same names already visible in this
conversation's step 2 output, not a shell variable carried over from an
earlier block (nothing persists between blocks; see Phase 0). No failures
this run → no trailing arguments.

Deliberately a **fresh** `npx skills list -g --json` call, not anything
captured in step 1 — installs and removals in step 2 changed reality since
then, and regenerating from stale output would write back exactly the
drift this phase exists to fix. Same JSON-validity guard as step 1, for the
same reason: a bad `npx` call here must not traceback, and must not
overwrite a good manifest with an empty one — `skills-manifest.sh` never
opens the manifest file for writing until its own JSON parse has already
succeeded, so a failed fetch leaves the existing manifest untouched either
way, but the shell-level check keeps the failure visible instead of a
silent no-op.

`skills-manifest.sh` filters `listing` to entries with a non-null `source`
under `$HOME/.agents/skills/`, reads the *old* manifest and `.fleet-local.json`
before touching either, computes the union described above, writes the
sorted `name<TAB>source` result, and rewrites the `# fleet:skills start` …
`# fleet:skills end` block in `.gitignore` to match — one `skills/<name>/`
line per entry — without touching anything else in that file.

**Backstop.** If the old manifest had at least one entry and the computed
result has none, the script refuses to write and exits non-zero instead —
this exact shape (a good manifest silently replaced by an empty one) has
already caused a silent wipe twice this review, by two different routes.
Report the refusal as an unresolved finding. If every declared skill is
genuinely gone from this machine and that's really intended, rerun with
`SKILLS_ALLOW_EMPTY_MANIFEST=1` to confirm it explicitly — never set that
automatically on the developer's behalf.

**This step depends on Phase 1 having already re-linked `skills`.** `npx
skills` resolves the Claude Code skills directory through `~/.claude/skills`
(or `$CLAUDE_CONFIG_DIR/skills`) to decide where to write; when that path is
the symlink Phase 1 maintains, the install lands in the canonical
`$HOME/.agents/skills` store and this filter keeps it. If that path is ever
a real directory instead — Phase 1 skipped, run out of order, or this phase
invoked standalone — installs land there instead, `npx skills list` reports
that path, `$HOME/.agents/skills/` never matches it, and every install
this phase just offered gets silently dropped and re-offered next run.
Phase 2.6 must always run after Phase 1 in the same sync, never on its own.

---

## Phase 3: Portability lint

```bash
machine="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/machine/*/ 2>/dev/null | sort -V | tail -1)}"; machine="${machine%/}"
"$machine/scripts/portability-lint.sh" "$repo"
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

## Phase 3.5: Rubric audit

```bash
machine="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/machine/*/ 2>/dev/null | sort -V | tail -1)}"; machine="${machine%/}"
"$machine/scripts/rubric-audit.sh" --days 7 || true
```

Read-only. Reports how sub-agents were actually routed over the last week: dispatches
by `model` param, `UNSET` count, haiku count, and codex handoffs. Exit `1` means a
finding — an omitted `model` (routing by inheritance) or a haiku dispatch — carry it
into the report. Exit `3` means python3 is missing; report `skipped: python3 not on
PATH`. Do not try to fix past dispatches; the point is to see drift, and to notice
when bulk work is landing on native sub-agents instead of the codex handoff.

---

## Phase 4: Report

```
Machine sync — {repo}

  Links:      {N} ok, {M} relinked, {K} need attention
  Committed:  {nothing local | <short message>: N added, M modified, K deleted}
  Pull:       {up to date | N commits: <oneline list> | DIVERGED — not pushed}
  Push:       {pushed <sha> | skipped: <reason> | no remote configured}
  Plugins:    {up to date | added N marketplace(s), installed M — restart to apply |
               skipped: claude CLI not on PATH | failed: <reason>}
  MCP:        {N ok | N ok, M remote (no local command) | N ok, M unresolved: <names>}
  Skills:     {N declared, M installed, K extra | up to date |
               skipped: npx/node not on PATH | skipped: repo is not $HOME/.agents |
               failed: <reason>}
  Skills local deviations: skipInstall <name>, … | keepLocal <name>, … | none
  Lint:       {clean | N finding(s), M fixed}
  Rubric:     {N dispatches, all explicit, 0 haiku, K codex handoffs |
               N dispatches: U unset, H haiku — see below | skipped: python3 not on PATH}

{any unresolved finding, one per line}
```

The `Skills local deviations` line always prints, with the `none` fallback
when both override arrays are empty — never omit it just because there's
nothing to show; a standing decline is exactly the kind of state that goes
invisible if it's only reported the first time.

If anything is unresolved, say so in the summary line — do not report success with
open findings buried above. That includes a failed marketplace add or plugin
install from Phase 2.5, `claude` missing from `$PATH`, or `claude plugin list` /
`claude plugin marketplace list` itself failing (report any of these the same as
an unfixed lint finding), any MCP server whose command didn't resolve (list
each as `<name> → <command> (not present on this machine)` alongside the other
unresolved findings), and any Phase 2.6 `install failed` or `remove failed`
line — both are distinct from a recorded decline (`skipInstall`/`keepLocal`,
reported in the deviations line above, not here) and must stay visible until
fixed. A server with no `command` (a URL/SSE-style server) is not a finding —
it's counted separately as "remote," never folded into "ok." A rubric-audit finding (any UNSET or haiku dispatch) is unresolved in the same sense — list it, do not fold it into a clean summary.

**Never report a sync as complete when the push did not happen.** A diverged pull,
a rejected push, or a missing remote all mean this machine's changes have not
reached anywhere else, and the next machine to sync will get the old state. That is
the exact failure this skill exists to prevent, so it belongs in the first line of
the report, not buried in a field.

**On a first run only** (Phase 0 reported `absent` and you cloned), add one line
after the report: nothing runs this skill automatically, so drift goes unnoticed
until someone runs it again. Offer to set up a recurring `/machine:sync` with
whichever scheduler they already use — their agent tool's scheduled tasks, `cron`,
`launchd`. Daily is plenty. Ask which they prefer; do not pick one, and do not
install anything unasked. Say it once and drop it — repeating this on every sync
is noise.

---

## Phase 5: Push (optional)

Only if `$repo/machine.yml` exists. Skip this phase entirely otherwise; never
create `machine.yml` unprompted.

**Legacy name.** If `$repo/machine.yml` is absent but `$repo/fleet.yml` exists
(a repo from before this plugin's rename), don't skip silently — tell the
user their push config is still under the old name and offer to rename it:
`mv "$repo/fleet.yml" "$repo/machine.yml"`.

```yaml
# machine.yml
machines:
  - host: studio-mini      # ssh target: a Host from ~/.ssh/config, or user@addr
  - host: laptop
```

```bash
command -v yq >/dev/null 2>&1 || { echo "yq not found — install it to use Phase 5 (push)."; exit 1; }
yq -r '.machines[].host' "$repo/machine.yml"
```

Confirm the host list with the user, then for each:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=8 "$host" 'cd "${AGENTS_REPO:-$HOME/.agents}" && git pull --ff-only' 2>&1
```

The remote path expression matches Phase 0's local resolution (`$AGENTS_REPO`
if the remote machine has it set, else `$HOME/.agents`) rather than a
hardcoded `~/.agents`, so pushing is consistent with how this machine finds
its own repo.

- Unreachable → report and continue to the next host. One offline machine is not
  a failure of the run.
- Non-zero exit → report that host's output verbatim.

**Be honest about what this proves.** A remote `git pull` says the remote repo
advanced. It does **not** confirm the remote machine re-linked correctly — that
needs `machine:sync` run there. Report what was attempted, not what succeeded:

```
Pushed to {N}/{M} machines. {list}
Unreachable: {list}
A pull is not a relink — run /machine:sync on a machine if its links may have drifted.
```
