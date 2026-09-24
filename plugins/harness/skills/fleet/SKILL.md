---
name: fleet
description: >-
  Use when an agent needs a shell on another of the developer's machines — run a
  command, read a log, check a build, or restart a service over SSH instead of VNC —
  or when a machine must be enrolled in, or removed from, the Harness fleet. The host
  inventory and public keys live in the developer's private agents repo; this skill
  never stores private keys or passwords. Skip GUI verification (use computer-use) and
  config sync (use sync).
disable-model-invocation: true
---

# Harness — Fleet

Every machine the developer owns is reachable as `ssh <alias>` once it is enrolled.
Plain OpenSSH does the work: the private agents repo tracks an `ssh/config` fragment
and one public key per machine, and each machine includes the fragment and
authorizes those keys.

```
$repo/ssh/config          Host blocks: alias, HostName, User, IdentityFile. No secrets.
$repo/ssh/keys/<alias>.pub one public key per enrolled machine
~/.ssh/id_ed25519_fleet   this machine's private key — never leaves the machine
~/.ssh/config             starts with `Include <repo>/ssh/config`
~/.ssh/authorized_keys    a `# harness:fleet` block rewritten from ssh/keys
```

**Trust boundary.** Anyone who can push to the agents repo can add a key that every
machine authorizes on its next authorize run. That is the same trust the repo
already holds through tracked `settings.json` hooks; keep the repo private.

## Run a command on a machine

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/fleet-hosts.sh"
```

Pick the alias from that list, then:

```bash
ssh -o BatchMode=yes <alias> 'zsh -l -s' <<'EOF'
uptime
EOF
```

- **Always `BatchMode=yes`.** A password or host-key prompt then fails fast instead
  of hanging the agent.
- **Use `zsh -l -s` with a quoted heredoc** for anything beyond one word. A non-login
  shell on macOS lacks Homebrew's `PATH`, and the heredoc avoids nested quoting.
- **Unreachable host:** check `tailscale status` for that name. Report "offline"
  and stop. Do not retry in a loop.
- **Permission denied:** that machine has not authorized this machine's key yet.
  Run the propagate step below from a machine that can already reach it, or
  enroll the target machine.

### Authority

Remote commands run with the session's permission mode, and this skill does not
widen it. Read-only commands (status, logs, `ls`, `git status`, builds that write
only to their own output) may run as the task needs. **Ask the user before**
anything that changes remote state outside the task's scope: installing or
removing software, deleting files, `kill`/`launchctl`, reboots, `git push`, or
editing another machine's config. `sudo` needs a password that BatchMode cannot
supply. Hand that command to the user. Never configure passwordless `sudo`.

SSH gives a shell, not the screen. To prove behavior visually on another machine,
use `harness:computer-use` or ask the user.

## Enroll this machine

Run once per machine, on that machine. It needs macOS Remote Login (System Settings
› General › Sharing) or `sshd` enabled for other machines to reach it, and a
network path to the others (for example, Tailscale MagicDNS names).

1. **Inventory.** If `$repo/ssh/config` has no block for this machine, add one and
   show it to the user:

   ```
   Host studio
     HostName studio.example-tailnet.ts.net
     User alice
     IdentityFile ~/.ssh/id_ed25519_fleet
     IdentitiesOnly yes
     ConnectTimeout 8
   ```

   Use `~` rather than an absolute home path; `harness:sync`'s portability lint
   rejects `/Users/<name>`.

2. **Key.** If `~/.ssh/id_ed25519_fleet` is absent, generate it. Agents need a
   key they can use without anyone present, so tell the user it has no
   passphrase and is protected by file mode and disk encryption. If they prefer
   a passphrase, they create the key themselves and load it with
   `ssh-add --apple-use-keychain`.

   ```bash
   repo="${AGENTS_REPO:-$HOME/.agents}"; alias=<this machine's Host alias>
   [ -f ~/.ssh/id_ed25519_fleet ] || ssh-keygen -q -t ed25519 -N '' -C "$USER@$alias fleet" -f ~/.ssh/id_ed25519_fleet
   mkdir -p "$repo/ssh/keys" && cp ~/.ssh/id_ed25519_fleet.pub "$repo/ssh/keys/$alias.pub"
   ```

3. **Include** the inventory from `~/.ssh/config`:

   ```bash
   harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
   "$harness/scripts/fleet-include.sh"
   ```

   OpenSSH applies an `Include` placed after a `Host` or `Match` line only to that
   block, so the script prepends the line unless it already precedes the first one.
   It refuses a symlinked config, because the rename would replace the link. In
   that case, tell the user to add the line to the top of the link's target.

4. **Authorize** every key in the repo, including the one just added:

   ```bash
   harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
   "$harness/scripts/fleet-authorize.sh"
   ```

   The script rewrites only the marked block. It rejects any key file that is
   not exactly one plain public-key line, including lines with `command=` and
   other options, and then leaves `authorized_keys` unchanged.

5. **Commit** with `/harness:sync`, which commits and pushes the repo.

6. **Propagate** (next section) from any machine that can already reach the others.
   Until then, the other machines do not accept the new key.

The first two machines need one bootstrap visit: enroll each one at its own keyboard
or over VNC. Every later machine is enrolled locally and then propagated from any
enrolled machine.

## Propagate keys to reachable machines

After a key is added or removed, pull the repo on every reachable machine and
re-run authorize there. The script is streamed over stdin, so the target does not
need this plugin installed.

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
hosts="$("$harness/scripts/fleet-hosts.sh")" || exit 1
failed=0
for h in $hosts; do
  out="$(ssh -o BatchMode=yes "$h" 'git -C "${AGENTS_REPO:-$HOME/.agents}" pull -q --ff-only && bash -s' \
    < "$harness/scripts/fleet-authorize.sh" 2>&1)" && rc=0 || rc=$?
  case "$rc" in 0) r=ok ;; 255) r="unreachable or refused" ;; *) r=FAILED ;; esac
  [ "$rc" -eq 0 ] || failed=1
  printf '== %s: %s (exit %s) %s\n' "$h" "$r" "$rc" "$(printf '%s\n' "$out" | tail -1)"
done
exit "$failed"
```

Report each host's line verbatim. The run exits 1 unless every host succeeded,
because any host not updated may still hold a revoked key. `unreachable or
refused` (ssh exit 255) means the connection failed; that host picks up the change
the next time propagate reaches it. `FAILED` means the pull or authorize failed on
a reachable host and needs attention there.

## Remove a machine

Delete its `Host` block and `ssh/keys/<alias>.pub`, commit with `/harness:sync`, then
propagate. Its key leaves every reachable machine's `authorized_keys`. Tell the user
that machines propagate cannot reach still accept the key until they are reached.
