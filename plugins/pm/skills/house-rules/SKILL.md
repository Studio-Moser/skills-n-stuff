---
name: house-rules
description: Use when making any code change and you need Studio Moser conventions for branch naming, file/documentation naming, commit messages, PR format, testing discipline, or pre-commit security checks, or when you just need a quick convention lookup. Loaded by pm:dev-task and pm:sprint-dev.
---

# House Rules

Studio Moser conventions for code changes. **Canonical source:** [`studio-baseline/House_Rules.md`](https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/House_Rules.md) — the same rules every repo's `AGENTS.md` baseline block points at, so plugin and non-plugin devs follow one set. Read the canonical doc for the full text; the essentials:

- **Branches:** never commit to `main`/`master`; branch `{type}/{short-desc}` (feature/bugfix/hotfix/release/chore). Sprint batches use `pulse/{cluster}-{date}`.
- **Commits:** Conventional Commits, present tense, one logical change each.
- **PRs:** imperative title < 72 chars; body always `## What` / `## Why` / `## Testing`; one PR per task.
- **File naming:** Title Case with spaces; underscores when spaces can't be used; dashes only for version/topic segments; never default to ALL CAPS; tooling-fixed names (`README.md`, `SKILL.md`, …) keep their form.
- **Implementation discipline:** shortest diff that fully solves it; reuse existing code / stdlib / platform first; no speculative abstractions or unrequested refactors; fix the root cause, not the symptom.
- **Testing:** baseline first, add tests for new behavior, show pasted output — never claim "passing" without evidence.
- **Verification:** self-review is a first draft, not proof; an independent check reproduces the claimed result; dispute wrong findings rather than distorting correct code.
- **Pre-commit security:** no secrets in the diff; validate input; don't disable a security feature to "make it work"; handle errors.
- **Project overrides:** a repo's own `CLAUDE.md`/`AGENTS.md` wins.
