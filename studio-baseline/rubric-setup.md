# Set up your personal model rubric

You are helping a developer create their **personal model-routing rubric** — how their AI agents pick which model does which work (cheap models for bulk/mechanical work, the strongest for ambiguous or taste-sensitive work). This works with **no plugin installed**; you only need shell + web access.

The rubric is **per developer, user-global** — one file on this machine, used across every repo:

```
${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml
```

## Steps

1. **Check if it already exists.** `cat "${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml"`. If present and current, stop — they're set up.

2. **Discover the current model lineup — prefer the Artificial Analysis API (structured, current).** If `ARTIFICIAL_ANALYSIS_API_KEY` is set, run `fetch-model-data.sh` (or curl `https://artificialanalysis.ai/api/v2/language/models/free` with `x-api-key`) to get names, pricing, and coding/agentic index as JSON — map pricing → cost, coding/agentic index → intelligence. That's 2 of 3 axes objectively. If no key: get names+cost from the dev's vendor docs, sanity-check at `artificialanalysis.ai` / `lmarena.ai` / `aider.chat/docs/leaderboards`; if offline, use your knowledge and add a `(verify names)` note. **Taste is never in AA** — always the dev's judgment; on a refresh, carry forward existing taste scores unchanged.

3. **Ask two things:**
   - Which model families/CLIs they can reach (e.g. "Claude only", "Claude + OpenAI Codex"). Record capabilities.
   - Confirm the axes: default **cost, intelligence, taste** (intelligence = hardest problem handled unsupervised; taste = UI/UX, code quality, API/SDK design, copy).

4. **Draft the table** — one row per model in *their* ecosystem, scored 1–10 on each axis. Show it and let them tweak.

   **Stay inside their ecosystem.** Propose only models from the families/CLIs the developer confirmed in step 3. Do not assume another vendor's CLI is available — a Claude-only setup must not include an OpenAI Codex / gpt-5.5 (or other cross-vendor) tier unless the developer confirmed they have that CLI/subscription. Add a cross-vendor tier only on explicit confirmation; record it under `capabilities`.

5. **Write the file** to the path above (create the directory), in this shape:

```yaml
# Personal model-routing rubric. Higher = better.
reviewed: 2026-07-10              # today's date; refresh after 14 days
sources: [artificial-analysis]   # what you checked (AA API for cost+intelligence)
capabilities:
  codex: false                # OpenAI Codex CLI / sub available?
models:
  - { name: <cheapest capable coder>, cost: 9, intelligence: 8, taste: 5 }
  - { name: <balanced mid-tier>,      cost: 5, intelligence: 5, taste: 7 }
  - { name: <most capable>,           cost: 2, intelligence: 9, taste: 9 }
routing:
  bulk: <cheapest capable model>      # clear-spec / mechanical work
  taste_min: 7                        # user-facing work needs taste >= this
  review: <strong model>              # plan/implementation reviews
```

6. **How to apply it** (tell the developer, and follow it yourself when dispatching sub-agents):
   - Defaults, not limits — escalate to a stronger model without asking if output misses the bar.
   - Bulk/mechanical/clear-spec → `routing.bulk`.
   - User-facing (UI, copy, API) → a model with `taste >= routing.taste_min`.
   - Reviews → `routing.review`.
   - Keep reasoning effort matched to difficulty; don't default to the top tier.
   - Re-check when a newer model ships or after **14 days**, then update `reviewed`. On refresh, re-pull Artificial Analysis for cost + intelligence and **keep your taste scores and capabilities** — only the AA-sourced axes change.

That's it — the rubric now lives in your user-global config and any repo's baseline reminder can point your agent at it.
