---
name: house-rules
description: Use when a code change needs Studio Moser conventions for change classes, branches, file naming, commits, pull requests, testing, or pre-commit security checks.
---

# House Rules

Studio Moser conventions for code changes. **Canonical source:** [`studio-baseline/House_Rules.md`](https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/House_Rules.md) — the same rules every repo's `AGENTS.md` baseline block points at, so plugin and non-plugin devs follow one set. Read the canonical doc for the full text; the essentials:

- **Branches:** never commit to `main`/`master`; branch `{type}/{short-desc}` (feature/bugfix/hotfix/release/chore). Sprint batches use `pulse/{cluster}-{date}`.
- **Commits:** Conventional Commits, present tense, one logical change each.
- **PRs:** imperative title < 72 chars; body always `## What` / `## Why` / `## Testing`; one PR per task.
- **File naming:** Title Case with spaces; underscores when spaces can't be used; dashes only for version/topic segments; never default to ALL CAPS; tooling-fixed names (`README.md`, `SKILL.md`, …) keep their form.
- **Change class:** only repo code/config changes get one — anything else gets no engineering workflow; name it first (Polish / Small / Feature); Polish — styling/copy, no logic — runs suite, review, and one commit at the checkpoint, not per edit; security/auth/payment/data-model flows are never Polish; a class never skips a gate it requires.
- **Implementation discipline:** shortest diff that fully solves it; reuse existing code / stdlib / platform first; no speculative abstractions or unrequested refactors; fix the root cause, not the symptom.
- **Testing:** baseline first, add tests for new behavior, show pasted output — never claim "passing" without evidence.
- **Verification:** self-review is a first draft, not proof; an independent check reproduces the claimed result; dispute wrong findings rather than distorting correct code.
- **Pre-commit security:** no secrets in the diff; validate input; don't disable a security feature to "make it work"; handle errors.
- **Project overrides:** a repo's own `CLAUDE.md`/`AGENTS.md` wins.
