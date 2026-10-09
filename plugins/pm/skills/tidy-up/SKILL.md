---
name: tidy-up
description: >-
  Cleans up the current repository after merged work: fetches the remote first, proves which branches, worktrees, and stashes are already in the base branch, integrates or keeps unmerged work, and deletes merged local and remote branches after one approved plan. Use when the user asks to tidy up, clean up branches or worktrees, or merge a PR and clean up after it.
effort: medium
allowed-tools: "Bash Read Write Edit AskUserQuestion"
---

# PM — Tidy Up

Leave the current repository with nothing but the base branch, protected branches,
and work that is still in flight. Scope is git and GitHub for **the current repository
only**; issue state belongs to `/pm:reconcile`.

## Hard rules

- **Fetch before reading anything.** Every classification uses refs fetched in this
  run. Never classify against a stale local base.
- **Never overwrite the base.** Fast-forward only. If the local base has diverged from
  its remote, stop and report it.
- **Prove before deleting.** Delete a branch only when §4 proves its tip is in the
  base. "Upstream gone" and "not an ancestor" prove nothing on their own.
- **Remote branches: yours only.** Delete a remote branch only when a merged PR from
  it was authored by the authenticated `gh` user. List everything else; never
  delete it.
- **No force on worktrees.** Never use `git worktree remove --force` or `rm -rf` on a
  worktree. A dirty worktree is kept and its files are listed.
- **One approval.** Nothing destructive runs before the user approves the §5 plan.
  Do only what the plan names.
- **Never push to the base or a protected branch.** Integrated work lands through a PR.

## 1. Resolve the repository and its branch rules

```bash
main_root="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
current_wt="$(git rev-parse --show-toplevel)"
recovery_dir="$(git rev-parse --path-format=absolute --git-common-dir)/pm-tidy-up"
config_path=""; dir="$main_root"
while [ -z "$config_path" ] && [ "$dir" != "/" ]; do
  for sub in "" research/ Research/ docs/research/; do
    [ -f "$dir/${sub}pulse-config.yaml" ] && config_path="$dir/${sub}pulse-config.yaml" && break
  done
  dir="$(dirname "$dir")"
done
```

`main_root` is the main checkout even when the session runs inside a worktree. The
config lookup matches `scripts/discover-config.sh`; PM setup is not required.

When `config_path` is set, find this repository's entry in its `repos:` (the entry
whose `path`, resolved against the git root of the config's directory, equals
`main_root`) and read:

- `base_branch` — falls back to top-level `default_branch`
- `protected_branches` — list; the base is always protected

If `pulse-config.yaml` is missing, or the entry lacks either key, ask in §2 and, when
the config exists, offer to save the answers to the repo entry so the next run does
not ask. Suggest protected-branch candidates from remote branches matching
`main|master|develop|dev|staging|stage|production|prod|live|release*`.

## 2. Ask once, then run

Ask every open question in one batch before touching anything:

1. Base branch and protected branches, only when §1 could not resolve them.
2. **Merge first?** Only when the user named a PR or asked to merge: confirm the PR
   number and that its base matches the configured base.

Do not ask anything else before the plan. Decide implementation details yourself.

## 3. Freshen

```bash
git -C "$main_root" fetch --all --prune --tags
gh auth status && me="$(gh api user -q .login)"
```

Fast-forward the local base without overwriting it:

- Base checked out in some worktree: `git -C <that worktree> merge --ff-only origin/$base`.
  If dirty files block it, stop and list them.
- Base not checked out: `git -C "$main_root" fetch origin "$base:$base"` (refuses
  non-fast-forward updates).

If the fast-forward fails because local base has commits missing from `origin/$base`,
stop: report those commits and ask how to land them. Do not reset.

**Merge first (optional).** When §2 confirmed a PR: wait for checks with
`gh pr checks <n> --watch`; stop on failure. Merge with the method the repository
already uses (read `gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed`
and recent history on the base). Do **not** pass `--delete-branch`; §6 does deletion.
If `gh pr merge` errors locally, re-read `gh pr view <n> --json state,mergedAt`
before retrying — GitHub often merged anyway. Then fetch and fast-forward again.

## 4. Inventory and prove

Collect, from fresh refs:

```bash
git -C "$main_root" worktree list --porcelain
git -C "$main_root" for-each-ref --format='%(refname:short) %(objectname) %(upstream:short) %(upstream:track)' refs/heads
git -C "$main_root" for-each-ref --format='%(refname:short) %(objectname)' refs/remotes/origin
git -C "$main_root" stash list
gh pr list --state all --limit 200 --json number,headRefName,headRefOid,baseRefName,state,author,isDraft
```

Ignore `origin/HEAD`. When a branch has no match in the PR list, look it up with
`gh pr list --head <b> --state all`. For every tip `T` (branch or stash) other than
the base and protected branches, the tip is **merged** when the first of these holds:

1. `git merge-base --is-ancestor T origin/$base`.
2. A PR merged into `$base` has `headRefOid == T` (squash and rebase merges).
3. `git cherry origin/$base T` prints no `+` lines (rebased or cherry-picked).
4. The first line of `git merge-tree --write-tree origin/$base T` equals
   `git rev-parse "origin/$base^{tree}"` (the tip adds nothing the base lacks).

Record which proof matched. A tip that matches none is **unmerged**, even if its
upstream is `[gone]` or a PR with the same name merged at a different head.

Classify each item:

| Item | Class | Default action |
|------|-------|----------------|
| Local branch | merged | delete |
| Local branch | unmerged, open PR | keep |
| Local branch | unmerged, no PR | ask: integrate, keep, or delete |
| Remote branch | merged, PR author = `$me` | delete |
| Remote branch | merged, other or unknown author | list only |
| Remote branch | unmerged | keep; list |
| Worktree | branch merged, clean, not current, not locked | remove |
| Worktree | dirty, current, locked, or branch unmerged | keep; list dirty files |
| Worktree | under a host tool's directory (T3, Codex, Cursor, Conductor, `.claude/worktrees`) | keep unless the user selects it |
| Stash | merged by rule 4, no untracked files (`git rev-parse -q --verify 'stash@{n}^3'` fails) | drop |
| Stash | otherwise | keep; summarize contents |

"Clean" means `git -C <wt> status --porcelain --ignored=no` is empty. Ignored build
output (`node_modules`, `.build`) does not make a worktree dirty, but it can make
`git worktree remove` refuse. In that case, list the ignored paths, delete only
ignored paths with `git -C <wt> clean -fdX`, and retry without `--force`.

## 5. Plan and approve

Present one table per class: item, tip SHA, proof, action. Then list in-flight work
being kept and anything you could not classify. Ask for one approval. The user may
change any row; apply their edits and do not re-ask.

## 6. Execute in this order

Before any deletion, write every tip and stash you will touch to
`$recovery_dir/<UTC timestamp>.log`, and save each stash you will drop with
`git stash show -p --include-untracked stash@{n} > $recovery_dir/<timestamp>-stash-<n>.patch`.

1. **Integrate** each branch the user chose to integrate: rebase (or merge, matching
   the repository's history) onto `origin/$base`. Resolve conflicts by keeping both
   sides' intent; when the intent conflicts, stop and ask. Run the checks the
   repository's instructions and scripts define. Push the branch and open or update
   its PR against the base. Merge it only if the plan said so, using the §3 merge
   steps. Unmerged integrated branches are kept, not deleted.
2. **Worktrees:** `git worktree remove <path>`, then `git worktree prune`.
3. **Local branches:** `git branch -d`; use `-D` only for a tip proven by §4 rules 2–4.
4. **Remote branches:** `git push origin --force-with-lease=refs/heads/<b>:<T> :refs/heads/<b>`
   so a branch that moved since the fetch is kept.
5. **Stashes:** drop the approved ones from the highest index down.

If a command is blocked by a permission prompt or classifier, do not work around it:
print the exact command for the user and continue with the rest.

## 7. Verify and report

Fetch again and re-run the §4 inventory. Report:

- What was deleted, with the recovery log path.
- What remains and why (in flight, protected, someone else's, blocked command).
- Any PR opened or merged, with its URL and check status.
- Local base vs `origin/$base` (must be equal) and any dirty files in `main_root`.

Restore a deleted branch with `git branch <b> <sha>` from the recovery log.
