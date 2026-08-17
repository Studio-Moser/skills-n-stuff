# Set up your personal model rubric

You are helping a developer create their **personal model-routing rubric** — how their AI agents pick which model does which work (cheap models for bulk/mechanical work, the strongest for ambiguous or taste-sensitive work). This works with **no plugin installed**; you only need shell + web access.

The rubric is **per developer, user-global** — one file on this machine, used across every repo:

```
${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml
```

**If that path (or its parent folder) is a symlink, preserve it.** On machines managed
by the `machine` plugin, `~/.config/studio-moser/` links into the developer's private
agents repo so the rubric syncs across their machines. Write *through* the link
(open/edit the file at the path above); never delete and recreate the folder or do an
atomic replace-the-directory — that severs the sync silently.

## Steps

1. **Check if it already exists.** `cat "${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml"`. If present and current, stop — they're set up. If present but stale (>14 days or a listed model is superseded), this is a **refresh**: skip the interview (step 5), re-pull data (steps 2–4), keep their taste scores and `capabilities` unchanged, and update `reviewed:`.

2. **Get them an Artificial Analysis API key (one-time, free).** Check `[ -n "$ARTIFICIAL_ANALYSIS_API_KEY" ]`. If unset, walk them through it before anything else:
   - Sign up at https://artificialanalysis.ai/data-api and generate a free API key — the free tier covers the models endpoint used here.
   - Have them add it to their shell environment so non-interactive shells (agent tooling) inherit it too — e.g. for zsh: `echo 'export ARTIFICIAL_ANALYSIS_API_KEY="<their key>"' >> ~/.zshenv`, then `source ~/.zshenv`. They paste the key themselves; never ask them to paste it into chat, and never commit it anywhere.
   - They can decline — the rubric still works. Fall back to vendor docs / judgment, note it under `sources:`, and offer the key again on the next refresh.

3. **Pull pricing + latency from Artificial Analysis.** If the key is set, run `fetch-model-data.sh` (or curl `https://artificialanalysis.ai/api/v2/language/models/free` with `x-api-key`) for names and pricing. AA's dollar figures inform `cost` for metered developers, and its latency figures inform latency notes — but see step 6 for why dollars alone mislead.

4. **Pull agentic quality from DeepSWE — per effort level.** Fetch https://deepswe.datacurve.ai (a web leaderboard; there is **no API or bulk export** — read the rendered page/chart). Record each candidate model's score **at each effort level** as `swe:`. Two things DeepSWE shows that AA's indices hide:
   - **Effort moves quality more than tier does.** The same model can span worthless-to-frontier across its effort curve. A rubric row is a *(model, effort)* pair, never a bare model.
   - **DeepSWE disagrees sharply with AA on small models** — for agentic SWE work, trust `swe:` over AA's coding index.
   If DeepSWE is unreachable, note that under `sources:` and lean on AA + judgment; re-pull on the next refresh.

5. **Interview the developer — one focused question at a time.** First-time setup is a short Q&A; do NOT open with a pre-scored table (the table comes at the end, as confirmation). Ask in order, adapting wording and skipping anything already known:

   1. **Providers** — which providers/CLIs do they have: Claude Code, OpenAI Codex, Gemini CLI, others? Ask about subscriptions too. Verify each claimed CLI actually resolves (`command -v codex`, `command -v gemini`, …) and record the full set under `capabilities`. Every later question stays inside this set.
   2. **Cost reality** — metered API or flat subscription, per provider? This picks the cost *semantics*, not just the scores: **metered → score dollars per task; flat sub → dollars are irrelevant, score token burn (quota) and wall-clock latency instead.** Record which semantics apply in a comment at the top of the file.
   3. **Trust for hard problems** — which model would they hand the hardest, most ambiguous problem and not supervise? Any model they'd never use?
   4. **Taste** — which model's UI, copy, and API design would they ship with the least editing?
   5. **Working style** — do they wait on agents interactively (latency matters) or fan out unattended batches (throughput matters)? This decides whether a slow-but-free row (e.g. a max-effort batch model) earns a `batch:` route or gets dropped.

6. **Draft the table** — one row per *(model, effort)* pair worth routing to, scored 1–10 on cost / intelligence / taste, with `swe:` carrying the DeepSWE number. Where a **seed rubric** is available (the `machine` plugin ships one at `plugins/machine/skills/model-rubric/Default_Rubric.yml`), start from it: keep its taste scores and anti-pattern notes, **drop rows whose provider isn't in this developer's `capabilities`**, and fill in `cost` from this developer's semantics. Working plugin-free, build the table from steps 3–4 directly. Mark rows reached through a cross-vendor CLI with `via: <cli>`. Show the table and let them tweak — their edits override the seed.

7. **Derive `routing` from the table — never copy it.** Routing names concrete *(model, effort)* pairs as `<model>@<effort>` strings, so it is only valid for the capabilities it was derived from:
   - `default:` the everyday driver — best swe-per-cost among reachable rows. **When a `via: codex` tier is reachable, that's the default** — those rows are codex handoffs (the `pm:codex-*` skills), not Agent calls. A mid-tier Claude model (e.g. Sonnet) is a fallback for machines without the codex CLI, not the bulk driver.
   - `bulk:` clear-spec / mechanical multi-step work — usually the same as `default`.
   - `quick:` short single-step turns where latency beats depth — a low-effort row (a `via: codex` low-effort row where codex is present).
   - `batch:` unattended fan-out ONLY, and only if a near-free high-swe row exists (omit otherwise; never route interactive work here).
   - `taste_min:` the floor for user-facing work (house default: 9).
   - `review:` plan/implementation reviews — the highest-swe row that isn't wasteful.
   - `independent:` adversarial read of one's own plan/diff — a *different vendor* than the daily driver, so it shares no context or family bias. Only if 2+ providers are in `capabilities`; omit otherwise.

8. **Write the file** to the path above (create the directory if absent — but see the symlink caution at the top), in this shape:

```yaml
# Personal model-routing rubric. Higher = better.
# cost semantics: <flat-sub: token burn + latency | metered: $/task> — set per step 5.2
reviewed: 2026-08-13              # today's date; refresh after 14 days
sources: [artificial-analysis, deepswe-v1.1]   # or [judgment], [seed-...], as applicable
capabilities:
  claude: true
  codex: false                    # each entry verified with command -v
models:
  # (name, effort) pairs; swe: = DeepSWE score at that effort; via: <cli> = cross-vendor
  - { name: <model>, effort: <low|medium|high|xhigh|max>, cost: <1-10>, intelligence: <1-10>, taste: <1-10>, swe: <n> }
routing:
  default: <model>@<effort>
  bulk: <model>@<effort>
  quick: <model>@<effort>
  # batch: <model>@<effort>       # only if an unattended near-free row exists
  taste_min: 9
  review: <model>@<effort>
  # independent: <model>@<effort> # only with 2+ providers; ask before spawning
```

9. **How to apply it** (tell the developer, and follow it yourself when dispatching sub-agents):
   - **Routing values are `<model>@<effort>` — split them on `@`.** If the named row carries `via: <cli>`, dispatch through that CLI's integration (with the pm plugin: its `codex-*` skills) — an Agent-tool call cannot run a cross-vendor model. Otherwise map the model to the Agent tool's tier (`claude-fable-*`→`fable`, `claude-opus-*`→`opus`, `claude-sonnet-*`→`sonnet`, `claude-haiku-*`→`haiku`) and pass the effort through the Agent `effort` parameter.
   - **Pass model AND effort explicitly on every dispatch** — every Agent-tool call and every `agent()` call inside a workflow script. Omitting either silently inherits the session default, and the routing does nothing. This is the one rule that makes the rest of the rubric real.
   - Defaults, not limits — escalate to a stronger row without asking if output misses the bar.
   - Bulk/mechanical/clear-spec → `routing.bulk`. Short latency-sensitive turns → `routing.quick`. User-facing (UI, copy, API) → a row with `taste >= routing.taste_min`. Reviews → `routing.review`. Unattended fan-out → `routing.batch` if set, and never for work someone is waiting on.
   - **Independence is its own axis.** `routing.independent` is for an adversarial read of *your own* plan or diff by a model that hasn't seen your context. Propose it and wait for a yes rather than spawning one unprompted; run it standalone after a workflow finishes, never as a workflow stage.
   - Raise effort before raising tier — on current data, one effort step buys more agentic quality than one model step.
   - Re-check when a newer model ships or after **14 days**, then update `reviewed:`. On refresh, re-pull AA and DeepSWE; **keep taste scores and `capabilities`** — only data-sourced axes change. No re-interview.

That's it — the rubric now lives in your user-global config (and, on machine-plugin-managed setups, syncs across your machines through your agents repo).
