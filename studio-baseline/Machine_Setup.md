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

## Steps

1. **Ask which case this is.** Two paths, and they differ in what can destroy work:
   - *This developer already has the repo* → clone it (step 2).
   - *This machine has loose config and there is no repo yet* → build the repo from
     it (step 3). Read that step fully before running anything.

2. **Clone and link.** Ask for the repo URL — never guess one.

   ```bash
   git clone <url> "$HOME/.agents"
   ```

   Before replacing anything, check what each of the four table entries currently
   is on this machine:

   ```bash
   for name in skills CLAUDE.md settings.json statusline-command.sh; do
     link="$HOME/.claude/$name"
     if [ -L "$link" ]; then
       echo "$name: existing symlink -> $(readlink "$link")"
     elif [ -e "$link" ]; then
       echo "$name: REAL file/directory — diff before touching it"
     else
       echo "$name: absent"
     fi
   done
   ```

   For anything reported as a **real file or directory**, it holds this machine's
   current config. Diff it against the repo's copy and ask the developer which
   side wins before removing anything. `skills` is a *directory* — that diff must
   be recursive, or it will lie:

   ```bash
   diff -ru "$HOME/.agents/skills" "$HOME/.claude/skills"                     # directory
   diff -u  "$HOME/.agents/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"        # a file
   ```

   A non-recursive `diff -u` against two directories prints only
   `Common subdirectories: …` and **exits 0 even when their contents differ** — it
   will tell you nothing changed when something did. Always use `-r` for `skills`.

   If the machine's version wins, copy it into the repo first (and commit it there
   if the developer wants it tracked) before it's removed:

   ```bash
   cp -R "$HOME/.claude/skills/." "$HOME/.agents/skills/"   # contents, not the directory —
                                                             # cp -R src dst nests one level
                                                             # deeper when both sides already exist
   cp "$HOME/.claude/CLAUDE.md" "$HOME/.agents/claude/CLAUDE.md"   # plain cp for a file
   ```

   Now link every entry. **A real file or directory must be removed first** —
   `ln -sfn` only repoints an *existing symlink*; pointed at a real path it does
   not error and does not replace it, it silently creates the link *inside* that
   path instead:

   ```bash
   # only the entries that are a real file/directory per the check above —
   # never rm a symlink you intend to keep pointed elsewhere without re-linking it
   rm -rf "$HOME/.claude/skills" "$HOME/.claude/CLAUDE.md" \
          "$HOME/.claude/settings.json" "$HOME/.claude/statusline-command.sh"

   ln -sfn "$HOME/.agents/skills"                        "$HOME/.claude/skills"
   ln -sfn "$HOME/.agents/claude/CLAUDE.md"              "$HOME/.claude/CLAUDE.md"
   ln -sfn "$HOME/.agents/claude/settings.json"          "$HOME/.claude/settings.json"
   ln -sfn "$HOME/.agents/claude/statusline-command.sh"  "$HOME/.claude/statusline-command.sh"
   ```

   Skip to step 5.

3. **Build the repo from loose config.** Order matters — step 3b is destructive if
   run before 3a.

   a. **Back up first.**

      ```bash
      tar czhf "$HOME/agent-config-backup.tgz" -C "$HOME" \
        .claude/skills .claude/CLAUDE.md .claude/settings.json \
        .claude/statusline-command.sh
      ```

   b. **If skills exist in more than one place, repair before consolidating.**
      Diff every duplicated pair — recursively, `diff -ru`, for the reason in
      step 2 — and establish which side is clean **before** deleting either. **A
      newer mtime is not evidence of a newer version** — in one observed case the
      newer timestamp was when a blind find-and-replace corrupted that copy. Read
      the diffs.

   c. **Initialise and commit a restore point** before anything moves. Copy, don't
      move, the skills tree in — the originals stay in place as a fallback until
      they're verified and explicitly removed in step 3e:

      ```bash
      mkdir -p "$HOME/.agents/claude" "$HOME/.agents/skills"
      cd "$HOME/.agents" && git init -b main
      cp -R "$HOME/.claude/skills/." skills/   # contents, not the directory (see step 2)
      git add skills && git commit -m "Initial commit: skills tree"
      ```

   d. **Copy the config files in** (again, copy — not move), then apply the two
      rules in step 4:

      ```bash
      cp "$HOME/.claude/CLAUDE.md" claude/CLAUDE.md
      cp "$HOME/.claude/settings.json" claude/settings.json
      cp "$HOME/.claude/statusline-command.sh" claude/statusline-command.sh 2>/dev/null || true
      git add claude && git commit -m "Add claude config files"
      ```

   e. **Replace the originals with symlinks** (commands in step 2 — resolve every
      entry as a real file/directory there, since the originals are all still in
      place). Before removing the backup tarball from 3a, verify the new links
      actually work:

      ```bash
      python3 -m json.tool "$HOME/.claude/settings.json" >/dev/null && echo "settings.json parses"
      ls "$HOME/.claude/skills" | wc -l   # sanity-check against the pre-migration count
      ```

4. **Apply two rules to everything tracked.** Both prevent silent breakage on the
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

5. **Keep machine-local things local.** Do not track these:

   | | why |
   |---|---|
   | `~/.claude/settings.local.json` | machine-local by design; holds `skillOverrides` |
   | `~/.claude/mcp.json` | hardcodes app paths that differ per machine |
   | `~/.claude/projects/` | session state and per-project memory |
   | any tool's own store (e.g. `~/.shelby/`) | credentials and per-machine databases |

   Syncing a memory tool's *configuration* does not sync its *memories*.

6. **Push, then verify.**

   ```bash
   cd "$HOME/.agents" && git remote add origin <url> && git push -u origin main
   ```

   **Confirm the remote is private before pushing** — this repo holds personal
   configuration. If the remote fails to authenticate, check `ssh-add -l` for a
   loaded key and `gh auth status` for the configured protocol; do not silently
   switch protocols.

7. **Restart running agent sessions.** They hold the old settings in memory, and one
   of them writing settings can replace a fresh symlink with a real file.

## Afterwards

Install the `fleet` plugin and use `/fleet:sync` for the ongoing work — it does the
link check, pull, and portability lint above on demand, and can push to other
machines. Set up model routing with `/fleet:model-rubric`, or follow
[`Rubric_Setup.md`](https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/Rubric_Setup.md)
if you have no plugins.
