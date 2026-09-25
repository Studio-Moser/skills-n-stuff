---
name: sync
description: Run the guarded Harness script that reconciles and publishes this machine's portable personal agent configuration.
disable-model-invocation: true
effort: low
allowed-tools: "Bash Read"
---

# Harness — Sync

Synchronize the developer's user-global agent configuration through the deterministic
entry point. This skill is slash-only because a full run can replace live paths,
install or remove machine-local tools, commit, and push.

## Run

Resolve the installed Harness root, then run:

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/sync" --dry-run
```

Use the dry run first when the requested choices are not already explicit. It is
read-only: it does not fetch, render, install, unlink, commit, or push. For a full
run, invoke the same script without `--dry-run` and pass every already-decided
choice as a flag. Use `scripts/sync --help` for the complete flag list.

The script resolves the same configuration roots as the helpers:

- repository: `${AGENTS_REPO:-$HOME/.agents}`
- Claude: `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`
- Codex: `${CODEX_HOME:-$HOME/.codex}`
- shared config: `${XDG_CONFIG_HOME:-$HOME/.config}`

## Decisions that stay with the agent or user

Do not infer a choice from timestamps, path names, or which side is newer. Inspect
the script's plan or shown diff, ask when the answer is not already known, then
rerun with explicit flags:

- first run: `--source existing --repo-url URL`, or
  `--source loose --remote-url URL --confirm-private-remote`; replacing an occupied
  repository path additionally needs `--replace-repo-path`;
- live-path conflicts: `--keep-live NAME`, `--discard-live NAME`, `--relink NAME`,
  or `--relink-all`;
- MCP set: `--mcp-mode match|replace|merge`; replace also needs
  `--confirm-mcp-replace`. Resolve named extras, unavailable commands, and secrets
  with the corresponding `--remove-mcp`, `--keep-local-mcp`, `--skip-mcp`,
  `--keep-unresolved-mcp`, or `--mcp-secrets-file` flag; a server whose definition
  differs from the manifest needs `--mcp-take-manifest NAME` or `--mcp-keep-live NAME`;
- third-party skills: choose each named `--install-skill`, `--skip-skill`,
  `--add-skill`, `--remove-skill`, or `--keep-local-skill` action;
- optional fleet push: `--push-machines` reaches every other host in the fleet's
  `ssh/config`, updates Harness there, and runs that machine's own sync (a machine
  without the sync script only pulls). Inspect the fleet hosts before passing it.

Never put a secret value in a command-line flag. `--mcp-secrets-file` accepts a
local `NAME=value` file and the script passes its contents only to
`mcp-secrets.sh import`; neither helper prints values.

## Typed stops

- exit `20`, `SYNC_DECISION_REQUIRED=...`: obtain or supply a missing judgment;
- exit `21`, `SYNC_CONFLICT=...`: inspect and resolve conflicting state;
- exit `22`, `SYNC_REFUSED=...`: a destructive or incompletely verified action was
  refused;
- exit `1`, `*_STATE=failed...`: fix the operational failure and rerun;
- exit `2`: invalid invocation.

Do not bypass a typed stop by manually running later phases. The script preserves
the ordering contract: remote ingestion before writers, backups before first-run
replacement, all reconciliation before the single finalizer transaction, and no
repository writer after finalization.

## Report

Return the script's structured summary and every unresolved line. State whether
the run was a dry run or full run, whether the repository push completed, and any
decision still required. A missing or rejected push is not a completed sync.

On a successful first run, repeat the script's reminders once: restart active
agent sessions after verifying links, and offer to schedule `/harness:sync` with
the user's existing scheduler. Do not choose or install a scheduler unasked.
