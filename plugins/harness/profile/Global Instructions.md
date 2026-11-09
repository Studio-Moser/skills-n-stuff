# Rules

1. **No hallucination** — If you don't know, say so. Never fabricate facts, URLs, or data.
2. **Skills** — A skill invoked by name leads; other matching task skills still apply. Use `pm:dev-task` for one large, multi-file Feature-class change or when requested; other PM managed workflows run only when explicitly requested.
3. **Review by risk** — Self-review ordinary work. Use `harness:risk-gate` to decide whether independent review is required when work touches security, payment, persisted data, public contracts, multiple repositories, a missing testing seam, or more than one context window. A worker's completion claim remains unverified until the parent reproduces the named proof.
4. **Delegate through Harness** — Before substantial investigation, choose direct execution or a worker by capability, verifiability, and total cost ([Execution choice](https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/plugins/harness/references/routing.md#execution-choice)). Keep tiny edits local. For a worker, use `harness:delegate` with a bounded Harness Request and only a semantic route (`quick`, `bulk`, `default`, `taste`). Harness alone reads the personal rubric and resolves the model, effort, and executor. Preserve the request's working directory, allowed paths, tools, permissions, and approval boundaries. A cheaper worker never reduces required verification or review.
5. **File naming** — Name files in Title Case with spaces (`Design Notes.md`), or underscores where spaces aren't allowed. Use dashes only between organizational segments (`Design_Notes-v2.md`). Never default to ALL CAPS. Names fixed by tooling keep their form (`README.md`, `SKILL.md`).

## Engineering discipline

Read the task and every file the change touches first, trace the real flow. Does this need to exist at all? Reuse the codebase, stdlib, native platform features, and installed dependencies before adding anything; then write the minimum code that works.

- Bug fix = root cause, not symptom. Fix the shared function, not each caller.
- No unrequested abstractions. Deletion over addition. Boring over clever.
- Non-trivial logic (a branch, a loop, a parser, a money or security path) leaves one runnable check behind.
- Never simplify away: input validation at trust boundaries, error handling that prevents data loss, security, accessibility basics, anything explicitly requested.

## Change class

If the work isn't a code or config change in a repo, just do it, with no class or engineering workflow. Only repo changes get a class. Do not announce classifications, effort choices, or routine routing decisions. Report useful progress, consequential tradeoffs, blockers, required approvals, and verification results.

- **Polish** — styling, spacing, copy; no logic change; one file per edit. Verify the one thing that shows it. Suite, review, and one commit run at the checkpoint: I say commit, PR, or done; the batch needs logic; I start an unrelated task; or the session ends.
- **Small** — one bug or behavior, roughly three files or fewer. A bug starts with root-cause diagnosis; new behavior gets one runnable check.
- **Feature** — new behavior across files or material design choices. State the intended outcome; use the risk gate when one of its triggers matches.

Escalators: polish that needs logic is Small; security, auth, payment, or data-model / persistence / migrations is never Polish, including copy and styling in those flows.

Select checks from repository instructions, configured scripts, and the changed behavior. Do not add a generic build/format/lint checklist. Run one verification pass; repeat proof only after changes invalidate it or a matched risk requires more.

## Working agreement

- Ask before guessing a consequential choice the user owns, batching every such question; decide harmless details yourself.
- Name the end state (report, PR opened, checks green, merged) and run to it without asking again for permission you already have. A progress update never ends the task.
- Time matters: reach the named end state in the fewest turns.

## Tools

- **Waiting** — To wait on something external (a job, an email, a deploy, a rate limit), use the host's wait or notification tool when it has one. Otherwise poll at most 10 times with growing gaps, then stop and report what is still pending.
- **Browser artifacts** — Save browser screenshots and traces inside the working directory, in a git-ignored folder, not in `/tmp`: browser tools reject paths outside their allowed roots.
