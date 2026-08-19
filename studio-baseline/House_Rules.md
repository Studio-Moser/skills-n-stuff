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

## Concurrent sessions in one repo

Several agent sessions often run against the same checkout at once. A checkout has exactly one HEAD and one index, so a second session switching branches between your commands silently re-parents your work — you branch off whatever HEAD happens to be, and `git add -A` stages their in-flight edits as yours. This is not hypothetical: it produced a PR carrying another session's unmerged refactor under an unrelated description, and only a merge conflict exposed it.

**Get your own worktree before starting parallel work:**

```bash
git worktree add ../{repo}-{task} -b {type}/{short-desc} origin/main
```

An isolated working directory with its own HEAD and index. Remove it when the branch merges: `git worktree remove ../{repo}-{task}`.

When you're working directly in a shared checkout anyway, two habits contain the damage:

- **Verify HEAD immediately before branching**, in the same command — not in an earlier one. `git rev-parse --abbrev-ref HEAD` in a separate call proves nothing about where you are a minute later. Chain it: `git checkout main && git pull && git checkout -b {branch}`.
- **Stage explicit paths, never `git add -A`/`git add .`** unless you have just read `git status` in the same command and every listed file is yours. Anything you didn't touch is someone's work in progress.

Before pushing, confirm the branch holds only your commits: `git log --oneline origin/main..HEAD`.

## Commits

Conventional Commits, present tense, one logical change per commit:

- `fix: resolve iPad settings crash on rotation`
- `feat: add dark mode toggle to preferences`
- `refactor: extract auth middleware into shared module`
- `test: cover empty-input path for parser`
- `docs: document the dev-task workflow`

Commit incrementally as you go — don't batch an entire feature into one commit. (A polish batch is one commit, at its checkpoint.)

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

## Change class

Size the ceremony to the change. Name the class in one line before you start ("Polish: gates at the checkpoint") so the human can override it in one word. When unsure, say the class and take the smaller one. This is the explicit instruction that lets a session skip a skill's workflow (brainstorm, plan) when the class doesn't call for it. A class never skips a gate it requires; it decides which gates apply and when they run.

- **Polish** — styling, spacing, copy; no logic change; one file per edit. No brainstorm; no plan (the class line is the plan); no sub-agent for the edits. Edit, verify the one thing that shows it (a screenshot, a targeted check), keep going. Baseline suite once per batch, not per edit. The suite, the review, and the single commit run **at the checkpoint**.
- **Small** — one bug or one behavior with a clear spec, roughly three files or fewer. No brainstorm. A bug goes through systematic debugging; new behavior gets a test for that one behavior. Targeted tests as you go, the full suite before the commit, one reviewer.
- **Feature** — new behavior across files, design choices to make, or anything in a security, auth, payment, or data-model flow. Brainstorm → plan → guided implementation → review, every gate.

**Checkpoint (Polish).** Any of: the human says commit / PR / done; the batch needs logic — commit the batch first, then the logic change proceeds as Small; the human starts an unrelated task; the session ends or hands off. Never leave a polish batch uncommitted in a shared checkout.

**Escalators.** Polish that needs logic is Small. Security, auth, payment, or the data model / persistence / migrations is never Polish — that includes copy and styling inside those flows (an auth error string, a control in a payment screen).

## Implementation discipline

- Take the shortest diff that fully solves the task. Reuse existing code, the stdlib, and native platform features before adding anything new.
- No speculative abstractions, no unrequested refactors, no scaffolding "for later."
- Fix bugs at the root cause — the shared function all callers route through — not the one symptom the report names.
- Discovered unrelated work stays out of scope: note it, don't do it inline. The definition of done stays fixed.

## Testing

- Establish a baseline first: run the existing suite before you change anything. Once per batch for polish.
- Add tests for new behavior. Cover the obvious edge cases (empty, error, boundary).
- Run the suite before each commit, and at minimum before the PR — once per checkpoint for a polish batch, not after every edit — and **show the output**; never claim "tests pass" without pasting evidence.
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
