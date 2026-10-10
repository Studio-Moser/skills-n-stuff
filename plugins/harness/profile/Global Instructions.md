# Rules

1. **No hallucination** — If you don't know, say so. Never fabricate facts, URLs, or data.
2. **Skill ownership** — A skill invoked by name leads. Choose direct execution or a rubric worker by capability, verifiability, and total cost. Use `pm:dev-task` for one large, multi-file Feature-class change or when requested; other PM managed workflows run only when explicitly requested. Other matching task skills still apply.
3. **Risk-based review** — Self-review ordinary work. Use `harness:risk-gate` to decide whether independent review is required; review paths are not additive. For a selected review, Harness owns routing and evidence while PM supplies development-specific review axes. A worker’s completion claim remains unverified until the parent reproduces the named proof.
4. **Delegate through Harness** — For delegated execution, review, or computer use, construct a bounded Harness Request and select only a semantic route. Harness alone reads the personal rubric, interprets `via:`, resolves the model, effort, provider, and executor, and passes the resolved model and effort explicitly. Preserve the request's working directory, allowed paths, tools, permissions, and approval boundaries. Keep tiny edits local when handoff costs more than finishing them.
5. **File naming** — Name files in Title Case with spaces (`Design Notes.md`). When spaces aren't allowed for the context, replace them with underscores (`Design_Notes.md`). Use dashes only to separate organizational segments like version or topic (`Design_Notes-v2.md`, `API_Reference-Authentication.md`). Do NOT default to ALL CAPS. Exception: files whose names are fixed by tooling/ecosystem convention keep their mandated form (`README.md`, `CLAUDE.md`, `SKILL.md`, `LICENSE`, `Makefile`, etc.)

## Engineering discipline

Applies to every agent that loads this file, sub-agents included. It shapes how small the solution is; the **change class** below decides which gates run and when — a class never skips a gate it requires. Read the task and every file the change touches first, trace the real flow, then stop at the first rung that holds:

1. Does this need to exist at all? Speculative need = skip it, say so in one line.
2. Already in this codebase? Reuse the helper, type, or pattern that already lives here.
3. Stdlib does it? Use it.
4. Native platform feature covers it? Use it (`<input type="date">` over a picker lib, CSS over JS, DB constraint over app code).
5. Already-installed dependency solves it? Use it. Never add a new one for what a few lines can do.
6. Can it be one line? One line.
7. Only then: the minimum code that works.

- Bug fix = root cause, not symptom. Grep every caller of the function you're about to touch; one guard in the shared function beats a guard in every caller.
- No unrequested abstractions: no interface with one implementation, no factory for one product, no config for a value that never changes. Deletion over addition. Boring over clever.
- The smallest diff in the wrong place is a second bug. Understand fully, then be lazy.
- Non-trivial logic (a branch, a loop, a parser, a money or security path) leaves one runnable check behind: an `assert`-based self-check or one small test. Trivial one-liners need none.
- Mark deliberate shortcuts with a `ponytail:` comment naming the ceiling and the upgrade path (`# ponytail: global lock, per-account locks if throughput matters`).
- Never simplify away: input validation at trust boundaries, error handling that prevents data loss, security, accessibility basics, anything explicitly requested. Hardware keeps its calibration knob.

### Change class

**Gate first: is this a code or config change in a repo?** If not — research, writing, analysis, a question, planning, ops, a throwaway script — no class, no engineering workflow, no skill ceremony. Just do it in House Style. Only repo changes get a class.

Classify internally and apply the required gates. Do not announce classifications,
effort choices, or routine routing decisions. Report useful progress, consequential
tradeoffs, blockers, required approvals, and verification results.

- **Polish** — styling, spacing, copy; no logic change; one file per edit. No brainstorm or separate plan. Keep tiny edits local; route a bounded batch only when the execution-choice rule below justifies it. Edit, verify the one thing that shows it, keep going. Suite, review, and one commit run at the **checkpoint**: I say commit / PR / done; the batch needs logic (commit it first, then proceed as Small); I start an unrelated task; the session ends.
- **Small** — one bug or one behavior with a clear spec, roughly three files or fewer. No brainstorm or separate plan. A bug starts with root-cause diagnosis; new behavior gets one runnable check. Choose direct execution or a rubric worker and use one verification pass at the highest stable existing testing seam.
- **Feature** — new behavior across files or material design choices. State the intended outcome and use the risk gate. Choose the implementer using the execution-choice rule below; risk determines verification and review. Add a written plan, recovery point, or independent review only when the matched risk requires it.

Escalators: polish that needs logic is Small; security, auth, payment, or data-model / persistence / migrations is never Polish — copy and styling inside those flows included. Full text: https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/plugins/harness/references/house-rules.md § Change class.


### Lite execution and verification

Before substantial investigation, choose direct execution or a bounded Harness
worker. Keep tiny edits and individual tool calls local. Prefer a rubric worker for
clear work with a reliable acceptance check when expected savings justify dispatch,
context transfer, parent verification, retries, and repairs. Account for subscription
quota and latency as well as metered dollars; do not infer savings from model names.
Any main model may route to a cheaper or stronger worker. Keep ambiguous diagnosis
and subjective judgment with a suitably capable agent. Task difficulty selects the
route; risk selects verification and review. This execution-choice rule applies to
all change classes and supersedes older direct-only or substantial-track-only
wording in installed Harness/PM skills; required risk gates still apply.

Use `harness:delegate` with `operation: execute` and a semantic route (`quick`, `bulk`, `default`, or `taste`)
when a worker is justified. Harness resolves the configured model and effort and
passes both explicitly; never inherit the session model or rewrite the rubric.
Preserve authority, delegation limits, approvals, and the existing escalation rules.
Give the worker the outcome, necessary context, and acceptance check before solving
the task yourself. Reproduce its named proof without repeating the whole investigation.
A cheaper worker never reduces required verification or review. Keep classification
and routine routing internal. Use `harness:risk-gate` for security, payment, persisted
data, public contracts, multiple repositories, missing testing seams, or work that
exceeds one context window. Use `pm:dev-task` for one large, multi-file Feature-class
change or when requested; other PM managed workflows remain explicit-only.

**Select checks from repository instructions, configured scripts, and the changed behavior.** Do not add a generic build/format/lint checklist. Confirm availability before scheduling an additional tool justified by the change; report an unavailable required check as an unmet gate, and run the remaining independent checks. Do not install optional tooling solely to complete a checklist.

Self-review the fixed diff and run one task-appropriate verification pass; repeat proof only after changes invalidate it or a matched risk requires more. Require independent review only when the risk gate says so or the user explicitly asks.
