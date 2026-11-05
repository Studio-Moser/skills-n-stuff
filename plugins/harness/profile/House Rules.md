# House rules

These apply to repo changes. A repo's own `CLAUDE.md` or `AGENTS.md` wins. Examples and reasoning: https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/plugins/harness/references/house-rules.md

- **Branches:** Never commit directly to the default branch. Name branches `{type}/{short-desc}` in kebab-case, with a type from `feat`, `fix`, `style`, `chore`, `docs`, `refactor`, `test`, `perf`, `ci`, `design`, `research`, `hotfix`, `release`. A repo's existing Gitflow names stay; `pm:sprint-dev` batches use `pulse/{cluster}-{date}`. Rename a host placeholder branch (`t3code/*`) with `git branch -m` before the first commit.
- **Parallel work:** Use a worktree only for actual parallel work or when the user explicitly requests isolation: `git worktree add ../{repo}-{task} -b {type}/{short-desc} origin/main`. In a shared checkout, verify HEAD in the same command that creates the branch, stage explicit paths instead of `git add -A`, and run `git log --oneline origin/main..HEAD` before pushing.
- **Commits:** Conventional Commits, one logical change each. Write the message to a temp file and use `git commit -F <file>`.
- **PRs:** One per task. Title under 72 characters, saying what changed for the user. Write the body to a temp file and use `gh pr create --body-file <file>`, with the sections `## What`, `## Why`, `## Testing`, `## Risk / Blast Radius`, and `## How to revert`. Open `## Why` with the problem in the reporter's own words, then the fix.
- **PR comments:** Start every comment an agent posts on your behalf with `> [!NOTE]` and `> 🤖 **<model> responding on behalf of <user>**`.
- **Proof:** Run the existing suite first as a baseline, once per batch for polish. Add tests for new behavior. Before the commit or PR, run a real check at the highest stable existing testing seam and show the output. Say which checks you couldn't run.
- **Security:** No secrets, tokens, or credentials in the diff, logs, PR comments, or PR descriptions. Validate user input and parameterize queries. Never disable a security feature to make something work.
