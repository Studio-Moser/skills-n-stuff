# Studio Moser House Rules

Conventions for code changes across Studio Moser projects. Canonical source — the `pm:house-rules` skill and every repo's `AGENTS.md` baseline block defer here. Applies to any agent (Claude, Codex, Cursor) and any developer, plugin or not.

<!-- the relocated sections follow verbatim -->

## Branches

- Branch from the repo's default branch. Confirm it: `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`
- Never commit directly to `main`/`master`.
- Name: `{type}/{short-desc}` — a Gitflow type prefix, then a kebab-case summary. Pick the prefix by intent:
  - `feature/` — new functionality (`feature/dark-mode-toggle`)
  - `bugfix/` — fix a non-urgent bug (`bugfix/settings-crash-on-rotation`)
  - `hotfix/` — urgent fix to ship straight away (`hotfix/login-500`)
  - `release/` — release prep (`release/1.4.0`)
  - `chore/` — tooling, deps, docs, refactors with no behavior change (`chore/bump-eslint`)
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

- **Title:** under 72 chars, imperative (`Fix iPad settings crash on rotation`). Say what changed *for the user*, not which internals moved.
  - Bad: `perf(server): negotiate per-message deflate on the websocket`
  - Good: `perf(server): cut websocket frame size by 70% with gzip`
- **Body:** always these three sections:

```
## What
<what changed, in 1-3 bullets>

## Why
<the problem / the ask>

## Testing
<commands run + result; screenshots for UI>
```

- **Open `## Why` with the problem in the reporter's own words, then the fix.** Never lead with an implementation inventory — a reader who wasn't in the thread has to understand the point in one sentence.
  - Bad: `Removed implicit workspace carryover from every new thread entry point; new threads inherit only the project from context.`
  - Good: `Starting a new thread on an existing worktree silently ignored my worktree default. Now the preference always applies.`
- If someone reading the PR cold can't state what problem it solves, rewrite it before filing.
- One PR per task. Don't mix unrelated changes.
- Create with: `gh pr create --title "…" --body "…"`. Link the issue/card if there is one.

## File & documentation naming

Applies to docs, notes, specs, and any file you create whose name you control.

- Default to **Title Case with spaces**: `Design Notes.md`, `Release Checklist.md`.
- When the context can't take spaces, replace them with **underscores**: `Design_Notes.md`.
- Use **dashes only to separate organizational segments** — version, topic, date: `Design_Notes-v2.md`, `API_Reference-Authentication.md`, `Status_Report-2026-06-12.md`.
- **Never default to ALL CAPS.** `SUMMARY.md` → `Summary.md`, `NOTES.md` → `Notes.md`.
- Exception: filenames fixed by tooling or ecosystem convention keep their mandated form — `README.md`, `CLAUDE.md`, `AGENTS.md`, `SKILL.md`, `LICENSE`, `Makefile`, etc.

## Implementation discipline

- Take the shortest diff that fully solves the task. Reuse existing code, the stdlib, and native platform features before adding anything new.
- No speculative abstractions, no unrequested refactors, no scaffolding "for later."
- Fix bugs at the root cause — the shared function all callers route through — not the one symptom the report names.
- Discovered unrelated work stays out of scope: note it, don't do it inline. The definition of done stays fixed.

## Testing

- Establish a baseline first: run the existing suite before you change anything.
- Add tests for new behavior. Cover the obvious edge cases (empty, error, boundary).
- Run the suite after your change and **show the output** — never claim "tests pass" without pasting evidence.
- If tests fail, fix them before opening the PR.

## Verification

- Your own self-review is a first draft, not proof. An independent check — a reviewer, or re-running the suite yourself — reproduces the claimed result rather than trusting the summary. A claimed-passing check that actually fails is a blocker.
- If a review finding is wrong for this codebase, dispute it with a one-line reason. Don't distort correct code to satisfy a bad finding.

## Pre-commit security check

Before every commit, confirm:
- No secrets, tokens, API keys, or credentials in the diff or in logs.
- User input is validated; queries are parameterized.
- No security feature was disabled to "make it work."
- Errors are handled, not swallowed.

## Project overrides

A repo's own `CLAUDE.md` / `AGENTS.md` wins over this file. Read it first; if it sets a different branch prefix, commit style, or test command, follow the repo.
