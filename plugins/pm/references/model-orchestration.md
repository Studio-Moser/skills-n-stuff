# Model orchestration doctrine

Canonical, **model-agnostic** source of truth for how PM skills route sub-agents across models and verify their output. `pm:setup` Phase 4.4 stamps the baseline reminder block below into a project's `AGENTS.md` (with `CLAUDE.md` importing it), and Phase 4.5 helps each developer create their own user-global rubric; `pm:sprint-dev`, `pm:dev-task`, and the `code-reviewer` agent read and enforce it. Keeping the baseline block here — in the version-controlled plugin — means every machine that installs the plugin behaves the same, instead of each machine's hand-edited global config drifting.

This file names no specific models. The concrete rubric (which models, what scores) is drafted **per user, per ecosystem, at setup time** and stored in the developer's user-global rubric file — see `skills/setup/SKILL.md` Phase 4.5 and `studio-baseline/Rubric_Setup.md` for its shape.

---

## What lives where

- **Routing philosophy** → the shared `studio-baseline` (house-rules + the `AGENTS.md` reminder block), reaching every dev plugin-free. **The rubric itself** → each developer's user-global store `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`, NOT the repo. The repo's `AGENTS.md` only reminds the agent to load it; `pm:setup`/`Rubric_Setup.md` create it.
- **Verification behavior** → baked into the skills themselves (`sprint-dev` Phase 2C, `dev-task` step 5, `code-reviewer` agent). Travels with the plugin.
- **Cross-vendor worker capability** (e.g. an OpenAI Codex executor) → optional, capability-gated skills in this plugin (`codex-review`, `codex-implementation`, `codex-computer-use`), inert unless the `codex` CLI is present. Travels with the plugin; activates only where the CLI exists.

The point: nothing orchestration-related needs to live in a machine's global config. Install the plugin + run `pm:setup` per repo, and any machine behaves identically (degrading gracefully where a capability like Codex isn't installed).

---

## Project block

`pm:setup` stamps a *reminder* block into the repo's `AGENTS.md` (see `studio-baseline/AGENTS_Baseline.md`); the scored rubric table lives in the developer's user-global store (`studio-baseline/Rubric_Setup.md` defines its shape).

### Where the baseline block goes

Follow the repo's existing convention; **default to `AGENTS.md` as the single source of truth with `CLAUDE.md` importing it**, so every tool (Claude Code, Codex, Cursor, Copilot) reads the same file. This applies to the baseline reminder block (`studio-baseline/AGENTS_Baseline.md`) that `pm:setup` Phase 4.4 stamps in — never to the scored rubric, which stays out of the repo entirely:

- **Repo uses `AGENTS.md` as source, or has neither file** → write the baseline block into `AGENTS.md`, and make sure `CLAUDE.md` pulls it in with an **`@AGENTS.md` import line** (Claude Code loads `@`-imports into context at session start — that's what makes it apply on every run, not just PM-skill runs). Create the `CLAUDE.md` pointer if missing; if a `CLAUDE.md` exists but doesn't import `AGENTS.md`, offer to add the import.
- **Repo keeps instructions in `CLAUDE.md` only (no `AGENTS.md`)** → respect it; write the baseline block into `CLAUDE.md`. Optionally offer to adopt the `AGENTS.md`-source layout.

A bare "see AGENTS.md" link is weaker than an `@AGENTS.md` import — the import guarantees the content loads; the link only works if the agent chooses to open it. Prefer the import. `stamp-baseline.sh` applies the block idempotently, delimited by `<!-- studio-baseline:start/end -->` markers, so re-running `pm:setup` updates it in place instead of duplicating it.

### The rubric

The scored rubric below — the table plus the "how to apply" bullets — is **not** part of the baseline block and is never written into the repo. It's the content that lives in each developer's user-global store (`${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`, shape defined by `studio-baseline/Rubric_Setup.md`), created by `pm:setup` Phase 4.5 or by any agent following `studio-baseline/Rubric_Setup.md` directly (plugin-free). It's reproduced here to illustrate what the rubric contains and how to apply it, filled with the **current** models of whatever ecosystem the setup assistant belongs to (looked up live at setup time, not from training-cutoff memory):

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

_Rubric reviewed {date}, sources: {vendor docs / benchmark / offline}. Re-assess when a newer model in this family ships or after 14 days, whichever comes first: re-check the lineup and rescore, then update this date._
```

---

## Verification (enforced by the skills, not this file)

Summarized here for maintainers; the authority is `sprint-dev` Phase 2C and the `code-reviewer` agent:

- A worker's "done / tests pass" is a **claim, not proof** — the independent check re-executes verification itself.
- Findings loop back with the specific defect until the check passes (bounded rounds), not a single fire-and-forget pass.
- No rank is above verification — orchestrator-authored code goes through the same check.
- Checks run both directions — a worker may dispute a wrong finding and have it overruled, rather than distorting correct work to satisfy it.

---

## Agent structure: minimal and dynamic

Don't build a standing cast of predefined project agents. A capable frontier orchestrator invents the role each task needs on the fly; a fixed zoo of process archetypes (reviewer, explorer, adversarial, planner…) just narrows what the orchestrator would otherwise do better per task.

- **No per-project `.claude/agents/` zoo.** `pm:setup` deliberately does not scaffold one. Roles are spawned dynamically by `sprint-dev`/`dev-task` per task.
- **Domain context lives in `AGENTS.md`** (+ the `CONTEXT.md` glossary), not baked into per-domain agent files. That's the single source every tool — and every dynamically-spawned worker — reads.
- **Verification is the one durable role.** The plugin's built-in `code-reviewer` agent (re-executes, ignores self-report) is the independent checker; `sprint-dev` Phase 2C loops it. You don't need a project-specific reviewer agent.
- **Tool-permission scoping is the only reason to add a named project agent** — and only when a hard permission boundary (constrain a worker to one package/toolset) genuinely can't be expressed in the task prompt. Prefer the prompt; add the file as a last resort.
- **Migrating an existing repo with a fixed agent team** (e.g. a Cove-style 8-agent setup): retire the process-archetype agents (reviewer/explorer/adversarial/planner) — dynamic orchestration + the built-in `code-reviewer` cover them. Keep at most a domain agent where a real tool-permission boundary exists. Fewer, sharper files beat a standing cast.
