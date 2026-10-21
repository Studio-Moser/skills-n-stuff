---
name: audit
description: >-
  Answers questions about how the Harness is actually used and where it falls short, from local transcripts, the delegation ledger, shim firings, and the component catalog across every synced machine. Use when asked which skills or rules are used or unused, which shims still fire or could retire, what tool calls fail, how delegations turn out, or where the harness has gaps to fix or grow into.
allowed-tools: "Bash Read Grep Glob"
---

# Harness — Audit

Answer the question asked from evidence. The data already exists; this playbook says
where it is and which questions to ask of it. Do not build a report feature: when an
answer needs a view, make it for this conversation.

## Sources

- **Counts** — the deterministic report. Its numbers compare across models and
  machines, so quote them rather than recounting:

  ```bash
  harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
  "$harness/scripts/usage-report.py" --days 30
  ```

  `--month YYYY-MM` selects a calendar month; `--local-only` drops other machines.
- **Catalog** — `Component_Catalog.toml` in the Harness plugin root: every rule and
  shim with its kind, source anchor, why it exists, detector, and retirement test.
- **Ledger and shim events** — `Results-*.jsonl` and `Shim_Events-*.jsonl`, unpublished
  under `${XDG_STATE_HOME:-~/.local/state}/studio-moser/harness/telemetry/` and
  published per host under `${AGENTS_REPO:-~/.agents}/telemetry/<host>/`.
- **Other machines** — `telemetry/<host>/Usage-YYYY-MM.json` summaries written by Sync.
- **Transcripts** — this machine only: `${CLAUDE_CONFIG_DIR:-~/.claude}/projects/**/*.jsonl`
  and `${CODEX_HOME:-~/.codex}/sessions/**/*.jsonl`. Read them for the why behind a
  count; quote at most short excerpts and never copy them into a repository.

## Questions to cover

Answer the user's question first. For a general audit, cover:

1. **Usage** — which skills run, how they are invoked, and which installed skills
   never ran in the window.
2. **Shims** — for each `model-shim` and `environment-shim`, the firings or detector
   hits, and whether its `retire_test` now looks satisfiable. Zero hits alone never
   proves a shim can go: the rule may be working, or nothing exercised it. Name the
   Harness Testing ablation that would decide it.
3. **Delegation** — ledger outcomes by route, fallbacks, unproven or blocked results,
   and delegate invocations with no recorded result.
4. **Gaps** — sample sessions with failed tool calls, compactions, unproven or blocked
   results, interruptions, or user corrections. For each, ask: what went wrong, what
   data or tool was missing that would have prevented it, and what the user had to
   repeat across sessions. Note the first failure in each session, group them, and
   count the groups.

## Output

Lead with the answer. Separate counts from interpretation. End with proposed changes:
catalog entries to add or retire, skills or shims to create for repeated work, and
regression tasks for Harness Testing. Propose only; change the catalog, profile, or
skills when the user asks.
