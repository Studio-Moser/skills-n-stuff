---
name: house-rules
description: Use when making any code change and you need Studio Moser conventions for branch naming, commit messages, PR format, testing discipline, or pre-commit security checks, or when you just need a quick convention lookup. Loaded by pm:dev-task and pm:sprint-dev.
---

# House Rules

Studio Moser conventions for code changes. This is the single source of truth — pm:dev-task and pm:sprint-dev both defer here, so changing a convention here changes it everywhere.

## Branches

- Branch from the repo's default branch. Confirm it: `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`
- Never commit directly to `main`/`master`.
- Name: `{name}/{short-desc}` — your first name, then a kebab-case summary.
  - `tara/fix-settings-crash`
  - `tim/add-dark-mode-toggle`
- Exception: automated sprint batches (pm:sprint-dev) use a `pulse/{cluster}-{date}` prefix — that's expected.

## Commits

Conventional Commits, present tense, one logical change per commit:

- `fix: resolve iPad settings crash on rotation`
- `feat: add dark mode toggle to preferences`
- `refactor: extract auth middleware into shared module`
- `test: cover empty-input path for parser`
- `docs: document the dev-task workflow`

Commit incrementally as you go — don't batch an entire feature into one commit.

## Pull Requests

- **Title:** under 72 chars, imperative (`Fix iPad settings crash on rotation`).
- **Body:** always these three sections:

```
## What
<what changed, in 1-3 bullets>

## Why
<the problem / the ask>

## Testing
<commands run + result; screenshots for UI>
```

- One PR per task. Don't mix unrelated changes.
- Create with: `gh pr create --title "…" --body "…"`. Link the issue/card if there is one.

## Testing

- Establish a baseline first: run the existing suite before you change anything.
- Add tests for new behavior. Cover the obvious edge cases (empty, error, boundary).
- Run the suite after your change and **show the output** — never claim "tests pass" without pasting evidence.
- If tests fail, fix them before opening the PR.

## Pre-commit security check

Before every commit, confirm:
- No secrets, tokens, API keys, or credentials in the diff or in logs.
- User input is validated; queries are parameterized.
- No security feature was disabled to "make it work."
- Errors are handled, not swallowed.

## Project overrides

A repo's own `CLAUDE.md` / `AGENTS.md` wins over this file. Read it first; if it sets a different branch prefix, commit style, or test command, follow the repo.
