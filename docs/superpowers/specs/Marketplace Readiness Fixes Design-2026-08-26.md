# Marketplace Readiness Fixes Design

## Delivery slice

- **Outcome:** The marketplace validates without treating private PM prompt packets as agents, and Harness sync compares the portable MCP manifest with Claude Code's actual user-scope MCP registry.
- **Blockers:** None. Both causes are established from validator output, caller tracing, Claude CLI behavior, and controlled `CLAUDE_CONFIG_DIR` probes.
- **Testing seam:** PM plugin validation plus the PM contract suite; Harness sync procedure tests against controlled default, custom, nested-project-only, and missing Claude config fixtures; then both full plugin suites and marketplace validation.
- **Proof:** Unproven until the fixed branch passes those checks.

## PM prompt packet classification

`ingestion-analyst.md` and `scorecard-evaluator.md` are text packets embedded in Harness requests. They are not independently invokable Claude agents and therefore should not live under `plugins/pm/agents/`, where plugin validation correctly expects agent frontmatter.

Move both packets to `plugins/pm/references/`, update their two runtime consumers and contract fixtures, and leave the real `code-reviewer.md` agent unchanged. A contract test will require every remaining file under `agents/` to have frontmatter and will prove both prompt packets remain reachable from their consumers.

## Claude user MCP registry

Claude Code stores user-scope MCP servers in the top-level `mcpServers` object of its global state file:

- `${CLAUDE_CONFIG_DIR}/.claude.json` when `CLAUDE_CONFIG_DIR` is set.
- `${HOME}/.claude.json` otherwise.

Harness sync currently reads `~/.claude/mcp.json`, so a connected user-scope server can be falsely reported missing. Sync will resolve the real global state path, pass it to the existing names-only `mcp-manifest.sh` boundary, and compare only top-level user-scope server names. Nested project-local registries must not satisfy the portable user manifest.

The global state file remains machine-local and secret-bearing: sync must never copy, link, print, stage, or commit it. The legacy `claude/mcp.json` path remains cleanup-only so old tracked files can be untracked safely.

## Release

Bump PM from `0.19.0` to `0.19.1`, Harness from `0.8.0` to `0.8.1`, and marketplace metadata from `0.19.1` to `0.19.2`. No other plugin behavior or version changes are in scope.
