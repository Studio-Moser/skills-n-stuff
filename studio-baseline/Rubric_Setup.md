# Set up your personal model rubric

You are helping a developer create their **personal model-routing rubric** — how their AI agents pick which model does which work (cheap models for bulk/mechanical work, the strongest for ambiguous or taste-sensitive work). This works with **no plugin installed**; you only need shell + web access.

The rubric is **per developer, user-global** — one file on this machine, used across every repo:

```
${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml
```

## Steps

1. **Check if it already exists.** `cat "${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml"`. If present and current, stop — they're set up. If present but stale (>14 days or a listed model is superseded), this is a **refresh**: skip the interview (step 4), re-pull data (steps 2–3), keep their taste scores and capabilities unchanged, and update `reviewed:`.

2. **Get them an Artificial Analysis API key (one-time, free).** Check `[ -n "$ARTIFICIAL_ANALYSIS_API_KEY" ]`. If unset, walk them through it before anything else:
   - Sign up at https://artificialanalysis.ai/data-api and generate a free API key — the free tier covers the models endpoint used here.
   - Have them add it to their shell environment so non-interactive shells (agent tooling) inherit it too — e.g. for zsh: `echo 'export ARTIFICIAL_ANALYSIS_API_KEY="<their key>"' >> ~/.zshenv`, then `source ~/.zshenv`. They paste the key themselves; never ask them to paste it into chat, and never commit it anywhere.
   - Verify: the curl in step 3 returns JSON.
   - They can decline — the rubric still works. Fall back to vendor docs / judgment for cost + intelligence, note `sources: [judgment]` in the file, and offer the key again on the next refresh.

3. **Discover the current model lineup — prefer the Artificial Analysis API (structured, current).** If `ARTIFICIAL_ANALYSIS_API_KEY` is set, run `fetch-model-data.sh` (or curl `https://artificialanalysis.ai/api/v2/language/models/free` with `x-api-key`) to get names, pricing, and coding/agentic index as JSON — map pricing → cost, coding/agentic index → intelligence. That's 2 of 3 axes objectively. If no key: get names+cost from the dev's vendor docs, sanity-check at `artificialanalysis.ai` / `lmarena.ai` / `aider.chat/docs/leaderboards`; if offline, use your knowledge and add a `(verify names)` note. **Taste is never in AA** — always the dev's judgment; on a refresh, carry forward existing taste scores unchanged.

4. **Interview the developer — one focused question at a time.** First-time setup is a short Q&A; do NOT open with a pre-scored table (the table comes at the end, as confirmation). Ask in order, adapting wording and skipping anything already known:

   1. **Providers** — which providers/CLIs do they have: Claude Code, OpenAI Codex, Gemini CLI, others? Ask about subscriptions too (a flat sub changes the cost math). Verify each claimed CLI actually resolves (`command -v codex`, `command -v gemini`, …) and record the full set under `capabilities`. Every later question stays inside this set. Multiple providers is the *good* case — the rubric then routes each task to whichever vendor's model is best-and-cheapest for it (e.g. bulk work to a generously-subscribed second vendor, taste work to the native one), bouncing between them automatically.
   2. **Axes** — confirm the default three: **cost, intelligence, taste** (intelligence = hardest problem handled unsupervised; taste = UI/UX, code quality, API/SDK design, copy). Let them rename or add an axis if they want.
   3. **Cost reality** — for each model, do they pay metered API rates or a flat subscription with generous limits? Score cost by **what they actually pay**, not list price (a model that's "free" on their sub scores high even if its API price is steep).
   4. **Trust for hard problems** — which model would they hand the hardest, most ambiguous problem and not supervise? Any model they'd never use?
   5. **Taste** — which model's UI, copy, and API design would they ship with the least editing?
   6. **Routing defaults** — which model is the bulk/mechanical workhorse, and which reviews plans/implementations?

5. **Draft the table from their answers + the data** — one row per model in *their* ecosystem, scored 1–10 on each axis. AA data anchors cost and intelligence; their answers set taste and adjust cost for subscription realities. With multiple providers, score all of them in **one** table and mark rows not reachable natively with `via: <cli>` so routing knows how each model is invoked. Show it and let them tweak.

   **Stay inside their ecosystem.** Propose only models from the providers/CLIs the developer confirmed in step 4. Do not assume another vendor's CLI is available — a Claude-only setup must not include an OpenAI Codex (or other cross-vendor) tier unless the developer confirmed they have that CLI/subscription. Add a cross-vendor tier only on explicit confirmation; record it under `capabilities`.

6. **Write the file** to the path above (create the directory), in this shape:

```yaml
# Personal model-routing rubric. Higher = better.
reviewed: 2026-07-10              # today's date; refresh after 14 days
sources: [artificial-analysis]   # what you checked (AA API for cost+intelligence)
capabilities:                # one entry per provider/CLI the dev confirmed (verified with command -v)
  claude: true
  codex: false               # OpenAI Codex CLI / sub available?
models:
  # via: <cli> marks a model reached through a cross-vendor CLI (omit = native)
  - { name: <cheapest capable coder>, cost: 9, intelligence: 8, taste: 5, via: codex }
  - { name: <balanced mid-tier>,      cost: 5, intelligence: 5, taste: 7 }
  - { name: <most capable>,           cost: 2, intelligence: 9, taste: 9 }
routing:
  bulk: <cheapest capable model>      # clear-spec / mechanical work — cheapest capable ACROSS providers
  taste_min: 7                        # user-facing work needs taste >= this
  review: <strong model>              # plan/implementation reviews
  independent: <model>                # optional — adversarial read of YOUR OWN plan/diff, by a model
                                      # that hasn't seen your context. Ask before spawning; expensive.
```

7. **How to apply it** (tell the developer, and follow it yourself when dispatching sub-agents):
   - **Pass the model explicitly on every dispatch** — every Agent-tool call and every `agent()` call inside a workflow script. Omitting it silently inherits the session model, and the routing below does nothing. This is the one rule that makes the rest of the rubric real.
   - Defaults, not limits — escalate to a stronger model without asking if output misses the bar.
   - Bulk/mechanical/clear-spec → `routing.bulk` — the cheapest capable model regardless of vendor.
   - User-facing (UI, copy, API) → a model with `taste >= routing.taste_min`.
   - Reviews → `routing.review`. Unsure between two tiers → take the cheaper and escalate on failure.
   - **Independence is its own axis, not just strength.** An adversarial read of *your own* plan or diff needs a model that hasn't seen your context — `routing.independent`, if set. It's the expensive option: propose it and wait for a yes rather than spawning one unprompted, and run it as a standalone call *after* a workflow finishes, never as a workflow stage.
   - **Dynamic workflows** (the Workflow tool) are fair game — reach for one when a task has 3+ independent parallelizable subtasks or wants a pipeline/judge panel. Unless the session has already opted in to multi-agent orchestration, propose it in a sentence or two with the rough shape and cost and wait for a yes. Inside the script, every `agent()` carries its own `model` per the routing above.
   - Models marked `via: <cli>` are invoked through that CLI (e.g. `codex exec`) rather than natively — where the pm plugin is installed, its `codex-*` skills handle this.
   - Keep reasoning effort matched to difficulty; don't default to the top tier.
   - Re-check when a newer model ships or after **14 days**, then update `reviewed`. On refresh, re-pull Artificial Analysis for cost + intelligence and **keep your taste scores and capabilities** — only the AA-sourced axes change. No re-interview needed.

That's it — the rubric now lives in your user-global config and any repo's baseline reminder can point your agent at it.
