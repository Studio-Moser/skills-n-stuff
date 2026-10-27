---
name: ship
description: >-
  Carries the current change, or someone else's pull request, to a ready-to-merge or merged PR without further check-ins: proves it, files the PR, watches checks and reviews, fixes findings, and asks only when blocked. Use when the user says "full stop" (stop when ready to merge) or "full send" (merge once the merge gate passes), or asks to take over, finish, or land a PR or branch unattended.
allowed-tools: "Bash Read Write Edit Skill AskUserQuestion"
---

# PM — Ship

The user is not watching this thread. Updates and the final message go unread until
long after you stop. Own the work from its current state to the end state below.
This skill applies only when the user asked for unattended delivery; without a clear
trigger, do not assume this autonomy.

## End state and permission

| Trigger | End state |
|---------|-----------|
| "full stop", or no explicit request to merge | PR passes the merge gate; never merge |
| "full send", or an explicit request to merge | PR merged once the merge gate passes |

A merge trigger grants exactly two actions beyond ordinary branch work: merging this
PR when the merge gate passes, and `git push --force-with-lease` to this PR's own
branch after a rebase. It never grants pushing to the base or a protected branch,
`gh pr merge --admin`, or bypassing branch protection.

Stop at ready and ask, even after a merge trigger, when `harness:risk-gate` matched
destructive persistence, a migration, authentication, or payment, unless the user
named that risk when asking to merge.

## Starting point

- **Work in this thread:** finish it.
- **Someone else's PR or branch ("take over"):** read its description, linked issue,
  and diff, then rebase it on the base. If work already on the base makes it
  unnecessary, close it with a comment linking that work and stop. Otherwise continue
  on it when you can push to it, or start a new branch that uses it as reference.
  Keep the original author's credit: preserve their commits or add a
  `Co-authored-by:` trailer, and link the original PR. Close a superseded PR with a
  link to the replacement once the replacement is filed.

## Flow

1. **Finish** the change under `pm:house-rules`.
2. **Prove it.** Proof is evidence you observed in this session at the highest stable
   testing seam: reproduce the original failure, apply the fix, and watch the same
   reproduction pass; run the checks the repository's CI runs. For UI or runtime
   behavior, run the app and look at the change; green mocked tests do not prove
   what a user sees.
3. **Review.** Apply `harness:risk-gate`. When it requires independent review, run
   it through `harness:delegate` with `operation: review` before filing, under the
   round limit in [review-proof.md](../../references/review-proof.md). Fix findings
   that are right; dispute wrong ones with a one-line reason. Review makes the change
   correct, not bigger: record out-of-scope findings as follow-ups.
4. **File the PR** with the house-rules body, including the review disclosure.
5. **Watch it.** When the host provides a pull-request watcher tool (such as
   `watch_pull_request`), use it and end the turn; it wakes you on checks, comments,
   and conflicts. Call its unwatch tool before you stop. Otherwise poll with
   `gh pr checks <n> --watch` and
   `gh pr view <n> --json reviewDecision,mergeStateStatus,reviews,comments`.
   Fix CI failures and review comments from bots and people, or reply to each with
   a written reason. Rebase when the branch falls behind.
6. **Merge gate.** All of these hold on the current head commit:
   - the proof covers every change in the diff;
   - required checks are green (`gh pr checks <n> --required`), none pending;
   - every review bot has finished, and each finding is fixed or answered in writing;
   - a required independent review approved the current head;
   - no human review requests changes (`reviewDecision` is not `CHANGES_REQUESTED`);
   - the branch is up to date with the base and GitHub reports it mergeable
     (`mergeStateStatus` is `CLEAN`).

   "Full stop" ends here. "Full send" merges with the method the repository already
   uses, as in `pm:tidy-up` § 3, then confirms `gh pr view <n> --json state` reports
   `MERGED`.
7. **Report** in five lines or fewer: PR link, final state, proof, and anything skipped.

## Asking the user

A question in a normal message goes unseen and the thread looks finished. Ask only
when you cannot continue alone: a choice the user owns, missing access, or a gate you
cannot make pass. Use the host's structured question tool (`AskUserQuestion` in
Claude Code) so the thread shows it is waiting, and put everything in the question:
the PR link, what blocks you, and the options with your recommendation first. When
access or confidence is missing, take the safe path: stop at ready rather than merge.
