# Model evidence

Read this from `harness:model-rubric` when refreshing benchmark or pricing
evidence for rubric rows.

Treat official provider list prices as source inputs, not as the software-work
comparison. Read the current DeepSWE leaderboard and compare its observed
`pass_at_1`, `mean_task_cost_usd`, output tokens, steps, and duration at each
effort level. Compute cost per successful task as
`mean_task_cost_usd / pass_at_1` and retain both observed inputs so the division
can be checked. Preserve the benchmark source version and observation date. If
DeepSWE is unavailable, record that and use provider evidence plus judgment.

Use Slopalytics at https://slopalytics.com to compare and pick candidate
`(model, effort)` rows. It plots Artificial Analysis figures per model and effort
variant: intelligence index, cost per task, time per task, tokens per task, and
output speed. Follow its Pareto line, which keeps only non-dominated variants: no
other visible variant is both better and cheaper on "Cost vs intelligence", or
both better and faster on "Time per task vs intelligence". Prefer rows on the
cost line for delegated work and on the time line for latency-sensitive routes.
Read each line once per reachable provider and once across all reachable
providers. The same-provider lines choose the routes of a single-provider rubric
and the fallback rows; the cross-provider line chooses primaries when Claude and
Codex are both reachable.

A row off both lines is dominated; keep it only for a recorded reason such as
trust, taste, a flat subscription, or reachability. Its intelligence index is
general rather than software-specific, so DeepSWE remains the software-work
comparison, and its usage charts do not measure model quality. The page renders
client-side, so a plain fetch returns only its title: read it through an
available browser tool or ask the developer for the variants on each line. When
it is used, record `slopalytics` and the observation date under `sources`; when
it cannot be read, record that and continue.
