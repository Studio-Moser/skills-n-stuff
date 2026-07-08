# Model orchestration doctrine

Canonical, **model-agnostic** source of truth for how PM skills route sub-agents across models and verify their output. `pm:setup` renders the "project block" below into a project's `CLAUDE.md`/`AGENTS.md`; `pm:sprint-dev`, `pm:dev-task`, and the `code-reviewer` agent read and enforce it. Keeping it here — in the version-controlled plugin — means every machine that installs the plugin behaves the same, instead of each machine's hand-edited global config drifting.

This file names no specific models. The concrete rubric (which models, what scores) is drafted **per user, per ecosystem, at setup time** and written into the project — see `skills/setup/SKILL.md` Phase 4.5.

---

## What lives where

- **Routing philosophy + the rubric** → the project's `CLAUDE.md`/`AGENTS.md` (the "project block" below), written by `pm:setup`. Travels with the repo.
- **Verification behavior** → baked into the skills themselves (`sprint-dev` Phase 2C, `dev-task` step 5, `code-reviewer` agent). Travels with the plugin.
- **Cross-vendor worker capability** (e.g. an OpenAI Codex executor) → optional, capability-gated skills in this plugin (`codex-review`, `codex-implementation`, `codex-computer-use`), inert unless the `codex` CLI is present. Travels with the plugin; activates only where the CLI exists.

The point: nothing orchestration-related needs to live in a machine's global config. Install the plugin + run `pm:setup` per repo, and any machine behaves identically (degrading gracefully where a capability like Codex isn't installed).

---

## Project block (what `pm:setup` writes into the project)

### Where the project block goes

Follow the repo's existing convention; **default to `AGENTS.md` as the single source of truth with `CLAUDE.md` importing it**, so every tool (Claude Code, Codex, Cursor, Copilot) reads the same file:

- **Repo uses `AGENTS.md` as source, or has neither file** → write the block into `AGENTS.md`, and make sure `CLAUDE.md` pulls it in with an **`@AGENTS.md` import line** (Claude Code loads `@`-imports into context at session start — that's what makes it apply on every run, not just PM-skill runs). Create the `CLAUDE.md` pointer if missing; if a `CLAUDE.md` exists but doesn't import `AGENTS.md`, offer to add the import.
- **Repo keeps instructions in `CLAUDE.md` only (no `AGENTS.md`)** → respect it; write into `CLAUDE.md`. Optionally offer to adopt the `AGENTS.md`-source layout.

A bare "see AGENTS.md" link is weaker than an `@AGENTS.md` import — the import guarantees the content loads; the link only works if the agent chooses to open it. Prefer the import.

### The block

`pm:setup` Phase 4.5 renders a section like the following into that source file, filling the rubric table with the **current** models of whatever ecosystem the setup assistant belongs to (looked up live at setup time, not from training-cutoff memory):

```markdown
## Picking the right models for workflows and subagents

Higher = better. Intelligence = hardest problem handled unsupervised. Taste = UI/UX, code quality, API/SDK design, copy.

| model | cost | intelligence | taste |
|-------|------|--------------|-------|
| {cheapest capable coder} | … | … | … |
| {balanced mid-tier}      | … | … | … |
| {most capable}           | … | … | … |

How to apply:
- Defaults, not limits — escalate to a stronger model without asking if output misses the bar; judge the output, not the price.
- Bulk/mechanical, clear-spec work (implementation, migrations, data/log digging) → the cheapest capable model.
- User-facing work (UI, copy, API/SDK design) → needs taste ≥ {threshold}.
- Reviews of plans/implementations → a strong model, optionally a second independent one.
- Keep reasoning effort matched to difficulty; don't default to the top effort tier — the highest tiers tend to over-reason per step, loop, and ship overdone work at much higher cost for no gain on most steps.
- Don't predefine sub-agent archetypes (reviewer, explorer, adversarial). Let the orchestrator invent the roles each task needs.
- If a model hides its reasoning, never ask it to echo or "explain your reasoning" in the response — it can trip a reasoning-extraction guard and silently reroute you off that model. Read its thinking blocks instead.
- Every implementation sub-agent or workflow prompt carries: reuse existing code, stdlib/platform first, shortest working diff, no speculative abstractions, root cause over symptom.
- Optional cross-vendor executor: if a second-vendor CLI is available (e.g. OpenAI Codex via the pm codex-* skills, when the `codex` binary is installed), route the bulk/mechanical tier there; otherwise use this ecosystem's own sub-agents. Behavior is identical where the CLI exists and degrades gracefully where it doesn't.

_Rubric reviewed {date}, sources: {vendor docs / benchmark / offline}. Re-assess when a newer model in this family ships or after ~90 days, whichever comes first: re-check the lineup and rescore, then update this date._
```

---

## Verification (enforced by the skills, not this file)

Summarized here for maintainers; the authority is `sprint-dev` Phase 2C and the `code-reviewer` agent:

- A worker's "done / tests pass" is a **claim, not proof** — the independent check re-executes verification itself.
- Findings loop back with the specific defect until the check passes (bounded rounds), not a single fire-and-forget pass.
- No rank is above verification — orchestrator-authored code goes through the same check.
- Checks run both directions — a worker may dispute a wrong finding and have it overruled, rather than distorting correct work to satisfy it.
