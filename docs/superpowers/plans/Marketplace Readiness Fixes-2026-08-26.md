# Marketplace Readiness Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the PM and Harness updates validate and sync against their real runtime contracts without exposing private prompt packets or Claude global state.

**Architecture:** Keep PM prompt packets as private references consumed by existing workflows. Reuse Harness's names-only MCP manifest script, but feed it Claude Code's actual user-scope state path resolved from `CLAUDE_CONFIG_DIR` or `HOME`.

**Tech Stack:** Markdown skills/references, Bash, Bats, Python contract checks, Claude plugin validator, Git.

**Spec:** `docs/superpowers/specs/Marketplace Readiness Fixes Design-2026-08-26.md`

## Global constraints

- Work only in `bugfix/marketplace-readiness`; never edit the shared `main` checkout.
- Add each regression test before its implementation and observe the expected failure.
- Never read fixture-independent secrets into output or repository artifacts.
- Keep `.claude.json` machine-local; only its sorted top-level MCP server names may cross the script boundary.
- Keep unrelated baseline fixture behavior out of scope. Run the Harness suite with `init.defaultBranch=main` supplied process-locally because the current tests initialize bare remotes before pushing `main`.
- Use explicit-path staging, conventional commits, full validation, and one fixed-target review before the PR.

---

### Task 1: Correct PM prompt packet classification

**Files:**

- Modify: `plugins/pm/tests/skill-contracts.bats`
- Move: `plugins/pm/agents/ingestion-analyst.md` to `plugins/pm/references/ingestion-analyst.md`
- Move: `plugins/pm/agents/scorecard-evaluator.md` to `plugins/pm/references/scorecard-evaluator.md`
- Modify: `plugins/pm/skills/ingest/SKILL.md`
- Modify: `plugins/pm/references/triage-scorecard.md`

1. Add a contract test that fails when any `agents/*.md` file lacks YAML frontmatter and proves the two packet consumers resolve reference paths.
2. Run the targeted Bats file and confirm it fails on the two existing files.
3. Move the packets, update both consumers and existing fixture references, then rerun the targeted test.
4. Run the PM suite and `claude plugin validate plugins/pm`; require no frontmatter warning.

### Task 2: Read Claude's actual user MCP registry

**Files:**

- Modify: `plugins/harness/tests/sync-procedure.bats`
- Modify as needed: `plugins/harness/tests/mcp-manifest.bats`
- Modify: `plugins/harness/skills/sync/SKILL.md`
- Modify: `plugins/harness/scripts/mcp-manifest.sh`
- Modify: `plugins/harness/README.md`

1. Add controlled-fixture tests for the default and custom global state paths, a nested-project-only server, and a missing state file. Assert only names are emitted and no configuration payload appears.
2. Run the targeted tests and confirm they fail because sync still uses `claude/mcp.json`.
3. Resolve `${CLAUDE_CONFIG_DIR}/.claude.json` or `${HOME}/.claude.json` in every sync phase that checks or generates the portable manifest.
4. Rewrite adoption and dry-run guidance so `.claude.json` is never copied, linked, printed, or tracked; retain only explicit legacy cleanup for `claude/mcp.json`.
5. Update script and README terminology, then rerun the targeted tests and Harness suite.

### Task 3: Release metadata and complete proof

**Files:**

- Modify: `plugins/pm/.claude-plugin/plugin.json`
- Modify: `plugins/harness/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`

1. Add or rely on the existing version-consistency test, then apply the approved PM, Harness, and marketplace patch versions.
2. Run both full plugin suites, both plugin validators, and marketplace validation.
3. Inspect the complete diff for scope, secret leakage, broken links, and stale paths.
4. Commit logical changes, pin the fixed target, obtain one read-only review, reproduce decisive checks, push the branch, and open a PR with What, Why, and Testing sections.
