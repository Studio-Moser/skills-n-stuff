# Portable MCP Sync Design

Date: 2026-09-02
Plugin: harness
Status: approved design, awaiting implementation plan

## Problem

`mcp.manifest` tracks MCP server names only. A machine that syncs sees names it cannot act on: on 2026-09-02 the Mac Studio reported nine servers "not configured" with nothing to install from. The full registry (`~/.claude.json`) stays machine-local for a sound reason: it mixes portable shape, secrets, and machine-bound state.

## Goal

Move the secret-free shape of each user-scope MCP server into the agents repo, keep secret values machine-local, show the user which machines have which servers, and let them choose once per sync how to reconcile the repo and this machine.

## Approach

Extend the existing script-per-concern pattern in `plugins/harness/scripts`: one generator, one read-only planner, one secrets helper, each with a bats test. Alternatives rejected: a single Python module with subcommands (breaks the one-script, one-test layout the sync skill's dry-run rules depend on) and one JSON file per server (two sources of truth with the machines list).

## 1. Manifest format

`mcp.manifest.json` replaces `mcp.manifest`. One tracked file, servers sorted by name.

```json
{
  "version": 1,
  "servers": {
    "kie-ai": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@felores/kie-ai-mcp-server"],
      "env": {"KIE_AI_API_KEY": "${KIE_AI_API_KEY}"},
      "machines": ["Mac-Studio", "macbookpro"]
    },
    "railway": {
      "type": "http",
      "url": "https://mcp.railway.com",
      "machines": ["macbookpro"]
    }
  }
}
```

Generator rules (`mcp-manifest.sh <live-registry> <manifest>`):

- Portable keys only: `type`, `command`, `args`, `url`, `env`, `headers`. Every other key in a live entry is dropped. OAuth state is never read.
- Every `env` and `headers` value is redacted to `${KEY}`. Env uses the env name. Headers use `${<SERVER>_<HEADER>}` uppercased with non-alphanumerics replaced by `_`. No value is inspected or written.
- Args are scanned, not redacted. An arg matching a token pattern, or `--flag=value` with a value of 16 or more characters, fails the generator with the server name only. Secrets in args have no reference form; the fix is manual.
- An absolute home path in `command` or `args` fails the same way. Portability lint remains the backstop.
- `machines` is the only field the generator edits per run: `hostname -s` is added when the server is in the live registry and removed when it is not. Other hosts' entries are untouched.
- `--prune-to-local`: additionally drop every server not in the live registry. Used only after the user chooses "replace the repo with this machine" (section 2).
- A live server absent from the manifest and listed in `.fleet-local.json` `keepLocalMcp` is not added.
- Migration: if `mcp.manifest` exists and `mcp.manifest.json` does not, seed the JSON from the names with `machines: []` and no shape, then `git rm --cached` the old file and delete it. A shapeless entry shows as `NO-CONFIG` until a machine that has it syncs.
- Backstop: if the old manifest had entries and the computed result has none, refuse to write and exit non-zero unless `MCP_ALLOW_EMPTY_MANIFEST=1`.
- Unparseable registry: leave the manifest untouched, print `MCP_MANIFEST_STATE=failed: ...`, exit non-zero.

`--check <manifest>` validates: `version` is 1, server names match `^[A-Za-z0-9][A-Za-z0-9._-]*$` and are sorted, only portable keys plus `machines`, every `env` and `headers` value matches `^\$\{[A-Z][A-Z0-9_]*\}$`, no key-like arg, `machines` is a sorted list of unique strings.

## 2. Reconcile table and the three choices

`mcp-reconcile.sh <repo> <live-registry> <settings.local.json>` is read-only. It prints a table, then plan lines.

Table: one row per server in the union of manifest and registry, one column per hostname found in any `machines` list plus `here`.

```
server         Mac-Studio  macbookpro  here   note
blender        -           x           -      no config in manifest
kie-ai         x           x           x
railway        -           x           x      needs authentication
sm-hub         -           x           -      command not on PATH
```

Plan lines, tab-separated:

| line | meaning |
|---|---|
| `INSTALL <name>` | in manifest with a shape, not here |
| `NO-CONFIG <name>` | in manifest without a shape; cannot install |
| `SKIP <name>` | in manifest, not here, listed in `.fleet-local.json` `skipMcp` |
| `EXTRA <name>` | here, not in manifest |
| `KEEP-LOCAL <name>` | here, not in manifest, listed in `keepLocalMcp` |
| `NEEDS-SECRET <name> <VAR>` | installable, but VAR has no local value yet |
| `UNRESOLVED <name>` | installed here, command not on PATH |

Servers listed in `settings.local.json` `disabledMcpjsonServers` are not findings.

If there are no `INSTALL`, `NO-CONFIG`, or `EXTRA` lines, sync prints the table and continues. Otherwise it asks one question with three options:

- **Match this machine to the repo.** Install every `INSTALL` server. Then list `EXTRA` servers and ask a second confirm before removing them from this machine. Declined removals are written to `keepLocalMcp`.
- **Replace the repo with this machine.** The manifest's server set becomes this machine's set. Servers only other machines had are listed by name in a confirm, because the next sync on those machines will offer to remove them. Applied in Phase 3.75 via `--prune-to-local`.
- **Merge.** Install every `INSTALL` server here and keep every `EXTRA` in the manifest. No removals anywhere.

After installs, servers whose command does not resolve on this machine are listed once with one follow-up: skip these on this machine? Yes writes them to `skipMcp` and removes the live entry, so a machine without Blender does not keep a blender server.

`NO-CONFIG` and `SKIP` lines are reported, never acted on. An install or remove that fails is reported as `install failed: <name>` or `remove failed: <name>` and never written to overrides, so it stays visible until fixed.

Installs use `claude mcp add-json -s user <name> <json>` with the `${VAR}` references left in place; removals use `claude mcp remove -s user <name>`.

## 3. Secrets

`mcp-secrets.sh export|import` moves values between machines without the repo seeing them.

- `export <manifest> <live-registry>`, run on the source machine. Prints one `NAME=value` line for every `${NAME}` the manifest references, `NAME=` when this registry has no value. Stdout only. When stdout is not a TTY it requires an explicit `--stdout` flag, so an agent cannot capture it silently. Sync prints the exact command to run on the other machine.
- `import <live-registry>` reads `NAME=value` lines on stdin and writes each value into every live server entry whose `env` or `headers` references `${NAME}`. Empty values are skipped. Nothing is echoed.
- Prompt path: for each `NEEDS-SECRET` line after install, sync asks for the value with a hidden read and feeds it to `import`. Pasting a whole export block at the first prompt imports all of it and skips the remaining prompts.

Values live only in this machine's registry. The manifest keeps the reference. Nothing is written to the shell profile or keychain. Sync states once, before the first prompt, that pasted values pass through the session transcript.

## 4. Placement in the sync skill

- Phase 2.3 becomes "generate the portable MCP manifest": run `mcp-manifest.sh` against the live registry, which performs the migration. Legacy `claude/mcp.json` cleanup is unchanged.
- Phase 2.5's MCP half becomes the interactive reconcile: run `mcp-reconcile.sh`, print the table, ask the three-way question when there are differences, apply installs and removals, run the secrets flow, then the unresolved-command follow-up.
- Phase 3.75 already regenerates the manifest before staging, so the `machines` column reflects the final registry; it uses `--prune-to-local` only after a "replace" choice and does not add an undeclared live server listed in `.fleet-local.json` `keepLocalMcp`.
- Dry run runs `mcp-manifest.sh --check` and `mcp-reconcile.sh` only. Table and plan lines print; no question is asked.
- `.fleet-local.json` gains `skipMcp` and `keepLocalMcp` arrays. The existing override snippet handles them as new kinds.
- Phase 4 MCP line: `{N ok | N ok, M remote | N ok, M skipped here, K need config: <names>}` plus one line per unresolved command. `NO-CONFIG` names stay visible every run.
- Setup inherits the change through its existing call into sync. The sync skill text, harness README, and house-rules reference are updated for the new filename.

## 5. Testing and error handling

Bats, one file per script, fixtures under `tests/fixtures`:

- `mcp-manifest.bats`: env and header redaction; key-like arg fails naming the server only; absolute path fails; `machines` add and remove; migration from names-only file; `--check` rejects unsorted, unredacted, and extra keys; `--prune-to-local`; empty-result backstop.
- `mcp-reconcile.bats`: every plan line kind from fixture registry and manifest; overrides and `disabledMcpjsonServers` suppress the right lines; table renders one column per hostname.
- `mcp-secrets.bats`: export lists referenced names with and without values; refuses without `--stdout` off a TTY; import writes only into referencing entries and skips empty values.
- `sync-procedure.bats`, `sync-workflow.bats`: updated for the renamed file and new phase text.
- `sync-finalize.bats`: a manifest with `${VAR}` values passes the staged secret scan; one with a literal value fails.

## Out of scope

Project-scope `.mcp.json` files, plugin-provided servers, OAuth login automation, Codex or other agents' MCP registries.
