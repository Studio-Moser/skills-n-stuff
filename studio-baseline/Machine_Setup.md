# Set up a machine's agent configuration

You are helping a developer bring a machine in line with their personal agent
configuration. This works with **no plugin installed** — you need only a shell and
git. Once done, the `fleet` plugin automates the repeated work.

The personal layer is **one private git repo per developer**, conventionally at
`~/.agents`, linked into `~/.claude`:

```
~/.agents/
├── skills/                    every skill; flat, every machine gets all of them
└── claude/
    ├── CLAUDE.md
    ├── settings.json          permissions, hooks, statusLine, enabledPlugins
    └── statusline-command.sh  referenced by settings.json — they travel together
```

| link | target |
|------|--------|
| `~/.claude/skills` | `~/.agents/skills` |
| `~/.claude/CLAUDE.md` | `~/.agents/claude/CLAUDE.md` |
| `~/.claude/settings.json` | `~/.agents/claude/settings.json` |
| `~/.claude/statusline-command.sh` | `~/.agents/claude/statusline-command.sh` |

**The four rows above are "the entries."** Every step below that touches more than
one of them is written as a loop over the same list, redeclared verbatim at the top
of that step's command block (blocks may run in separate shells, so nothing set in
one persists into the next). Copy it exactly — don't hand-unroll it into separate
per-entry lines. That's what makes adding a fifth entry later a one-line edit
repeated in a few places instead of a hunt through prose for every place "the four"
were listed out by hand:

```bash
entries="skills|skills|dir
CLAUDE.md|claude/CLAUDE.md|file
settings.json|claude/settings.json|file
statusline-command.sh|claude/statusline-command.sh|file"
```

(`name|rel|kind` — `name` under `~/.claude`, `rel` under `~/.agents`, `kind` is
`dir` or `file` so loops can branch: `skills` needs `-R`/`-r` forms, the rest don't.)

## Steps

1. **Back up whatever is on this machine for these four entries, before anything
   else.** Both paths below can remove real files — the clone path (step 3) has an
   unconditional removal a few lines into it, and it's the only net either path
   gets:

   ```bash
   entries="skills|skills|dir
   CLAUDE.md|claude/CLAUDE.md|file
   settings.json|claude/settings.json|file
   statusline-command.sh|claude/statusline-command.sh|file"

   rm -f "$HOME/agent-config-backup.tar" "$HOME/agent-config-backup.tar.gz"
   found=0
   while IFS='|' read -r name rel kind; do
     [ -n "$name" ] || continue
     if [ -e "$HOME/.claude/$name" ]; then
       tar rhf "$HOME/agent-config-backup.tar" -C "$HOME" ".claude/$name"
       found=1
     fi
   done <<EOF
   $entries
   EOF

   if [ "$found" = 1 ]; then
     gzip -f "$HOME/agent-config-backup.tar"
     echo "backed up to $HOME/agent-config-backup.tar.gz"
   else
     echo "nothing at ~/.claude yet — no backup needed"
   fi
   ```

   Archive each existing entry with its own `tar rhf` (append) call rather than
   collecting paths into one variable and passing it to a single `tar` — `tar`
   given a path that isn't there exits non-zero (`Cannot stat` /
   `Error exit delayed`) even though the rest of the archive would be fine, and
   most machines don't have `statusline-command.sh`; a backup step that appears
   to fail is worse than no backup step. Per-entry calls also sidestep an unquoted
   multi-path variable, which silently stops word-splitting into separate
   arguments under zsh (unlike bash) and archives one bad combined path instead
   — this skill's Bash tool may run either.

2. **Ask which case this is.** Two paths, and they differ in what can destroy work:
   - *This developer already has the repo* → clone it (step 3).
   - *This machine has loose config and there is no repo yet* → build the repo from
     it (step 4). Read that step fully before running anything.

3. **Clone and link.** Ask for the repo URL — never guess one.

   ```bash
   git clone <url> "$HOME/.agents"
   ```

   Check state and diff in one pass — for each entry, report what's on this
   machine, and if it's a real file or directory, diff it against the repo's copy
   right there (branching on `kind`, since `skills` is a directory and a
   non-recursive diff against a directory prints only `Common subdirectories: …`
   and **exits 0 even when contents differ** — it will tell you nothing changed
   when something did):

   ```bash
   entries="skills|skills|dir
   CLAUDE.md|claude/CLAUDE.md|file
   settings.json|claude/settings.json|file
   statusline-command.sh|claude/statusline-command.sh|file"

   while IFS='|' read -r name rel kind; do
     [ -n "$name" ] || continue
     link="$HOME/.claude/$name"
     want="$HOME/.agents/$rel"
     if [ -L "$link" ]; then
       echo "== $name: existing symlink -> $(readlink "$link")"
     elif [ -e "$link" ]; then
       echo "== $name: REAL $kind on this machine"
       if [ "$kind" = dir ]; then diff -ru "$want" "$link"; else diff -u "$want" "$link"; fi
     else
       echo "== $name: absent on this machine"
     fi
   done <<EOF
   $entries
   EOF
   ```

   For every entry reported **REAL**, ask the developer which side wins — one
   entry at a time. If the machine's version wins, copy it into the repo
   **immediately**, before deciding the next entry (and commit it there if the
   developer wants it tracked):

   ```bash
   # directory (skills) — contents, not the directory itself:
   cp -R "$HOME/.claude/skills/." "$HOME/.agents/skills/"
   # a file — same form for CLAUDE.md, settings.json, or statusline-command.sh:
   cp "$HOME/.claude/settings.json" "$HOME/.agents/claude/settings.json"
   ```

   Do this for **every** entry the machine wins, not only the ones that come to
   mind first — `settings.json` and `statusline-command.sh` are exactly as
   unrecoverable as `skills` and `CLAUDE.md` once the next step removes them, and
   nothing later in this doc copies them back for you.

   Once every REAL entry is resolved (the repo now holds the winning content for
   each), remove what's on the machine and link — but only for entries the repo
   actually has. Linking to a path the repo lacks would create a dangling symlink
   instead of correctly leaving that entry absent (this is also the loop step 4
   reuses to replace originals with symlinks, and the one `/fleet:sync`'s own
   `link-plan.sh` mirrors):

   ```bash
   entries="skills|skills|dir
   CLAUDE.md|claude/CLAUDE.md|file
   settings.json|claude/settings.json|file
   statusline-command.sh|claude/statusline-command.sh|file"

   while IFS='|' read -r name rel kind; do
     [ -n "$name" ] || continue
     link="$HOME/.claude/$name"
     want="$HOME/.agents/$rel"
     if [ ! -e "$want" ]; then
       echo "== $name: repo has no $rel — leaving $link as-is, not linking"
       continue
     fi
     rm -rf "$link"
     ln -sfn "$want" "$link"
     echo "== $name: linked -> $want"
   done <<EOF
   $entries
   EOF
   ```

   `rm -rf` here is safe unconditionally: by this point every REAL entry's content
   worth keeping is already in the repo (or the developer chose to discard it),
   and removing a plain symlink or a nonexistent path is a no-op. `ln -sfn` alone
   is not enough — it only repoints an *existing symlink*; pointed at a real file
   or directory it does not error and does not replace it, it silently creates the
   link *inside* that path instead, which is why the removal has to happen first
   on every branch, not only the symlink-to-directory case.

   Skip to step 5.

4. **Build the repo from loose config.** Order matters — step 4b is destructive if
   run before 4a.

   a. **If skills exist in more than one place, repair before consolidating.**
      Diff every duplicated pair — recursively, `diff -ru`, for the reason in
      step 3 — and establish which side is clean **before** deleting either. **A
      newer mtime is not evidence of a newer version** — in one observed case the
      newer timestamp was when a blind find-and-replace corrupted that copy. Read
      the diffs.

   b. **Initialise the repo and copy every entry in** — copy, don't move; the
      originals stay in place as a fallback until they're verified and explicitly
      removed in step 4d. Skip any entry not present on this machine rather than
      failing on it (`statusline-command.sh` is commonly absent):

      ```bash
      mkdir -p "$HOME/.agents/claude" "$HOME/.agents/skills"
      cd "$HOME/.agents" && git init -b main

      entries="skills|skills|dir
      CLAUDE.md|claude/CLAUDE.md|file
      settings.json|claude/settings.json|file
      statusline-command.sh|claude/statusline-command.sh|file"

      while IFS='|' read -r name rel kind; do
        [ -n "$name" ] || continue
        src="$HOME/.claude/$name"
        if [ ! -e "$src" ]; then echo "== $name: not on this machine, skipping"; continue; fi
        if [ "$kind" = dir ]; then cp -R "$src/." "$HOME/.agents/$rel/"; else cp "$src" "$HOME/.agents/$rel"; fi
      done <<EOF
      $entries
      EOF

      git add skills claude && git commit -m "Initial commit: skills tree and claude config"
      ```

   c. **Apply the two rules in step 5** to what you just committed.

   d. **Replace the originals with symlinks** — reuse the removal+link loop from
      step 3 verbatim (it already skips any entry the repo doesn't have, so it's
      safe even when `statusline-command.sh` was never present). Before removing
      the backup tarball from step 1, verify what's now linked actually resolves
      and parses:

      ```bash
      entries="skills|skills|dir
      CLAUDE.md|claude/CLAUDE.md|file
      settings.json|claude/settings.json|file
      statusline-command.sh|claude/statusline-command.sh|file"

      while IFS='|' read -r name rel kind; do
        [ -n "$name" ] || continue
        link="$HOME/.claude/$name"
        if [ ! -e "$link" ] && [ ! -L "$link" ]; then echo "== $name: not linked (repo had none)"; continue; fi
        target="$(readlink -f "$link" 2>/dev/null)"
        if [ -z "$target" ] || [ ! -e "$target" ]; then echo "== $name: DANGLING -> $(readlink "$link")"; continue; fi
        if [ "$kind" = dir ]; then
          [ -n "$(ls -A "$link" 2>/dev/null)" ] && echo "== $name: ok, populated" || echo "== $name: EMPTY"
        elif [ "$name" = settings.json ]; then
          python3 -m json.tool "$link" >/dev/null 2>&1 && echo "== $name: ok, parses" || echo "== $name: FAILED to parse"
        else
          echo "== $name: ok"
        fi
      done <<EOF
      $entries
      EOF
      ```

      Only delete the backup tarball once every line reads `ok` (or the expected
      `not linked` for an entry that was never present).

5. **Apply two rules to everything tracked.** Both prevent silent breakage on the
   *next* machine, which is far harder to diagnose than breakage here.

   - **No literal `/Users/<name>` or `/home/<name>` paths.** Use `$HOME`. A
     hardcoded home directory makes a synced config *wrong* elsewhere rather than
     merely absent. Check contents **and symlink targets** — `grep` follows a
     symlink and reads its target, so an absolute link target passes a naive check:

     ```bash
     cd "$HOME/.agents"
     git ls-files -s | grep '^120000 ' | cut -f2- | while read -r l; do
       case "$(readlink "$l")" in /*) echo "absolute symlink: $l";; esac
     done
     git ls-files | while read -r f; do
       [ -L "$f" ] || grep -nHE '/(Users|home)/[A-Za-z0-9._-]+' "$f"
     done
     ```

   - **Guard hooks calling an optional binary**, so a machine without that tool
     degrades quietly instead of erroring every turn:

     ```sh
     [ -x "$HOME/.tool/bin/hook" ] && "$HOME/.tool/bin/hook" args || true
     ```

6. **Keep machine-local things local.** Do not track these:

   | | why |
   |---|---|
   | `~/.claude/settings.local.json` | machine-local by design; holds `skillOverrides` |
   | `~/.claude/mcp.json` | hardcodes app paths that differ per machine |
   | `~/.claude/projects/` | session state and per-project memory |
   | any tool's own store (e.g. `~/.shelby/`) | credentials and per-machine databases |

   Syncing a memory tool's *configuration* does not sync its *memories*.

7. **Push, then verify.**

   ```bash
   cd "$HOME/.agents" && git remote add origin <url> && git push -u origin main
   ```

   **Confirm the remote is private before pushing** — this repo holds personal
   configuration. If the remote fails to authenticate, check `ssh-add -l` for a
   loaded key and `gh auth status` for the configured protocol; do not silently
   switch protocols.

8. **Restart running agent sessions.** They hold the old settings in memory, and one
   of them writing settings can replace a fresh symlink with a real file.

## Afterwards

Install the `fleet` plugin and use `/fleet:sync` for the ongoing work — it does the
link check, pull, and portability lint above on demand, and can push to other
machines. Set up model routing with `/fleet:model-rubric`, or follow
[`Rubric_Setup.md`](https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/Rubric_Setup.md)
if you have no plugins.
