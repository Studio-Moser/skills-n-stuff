---
name: ship
description: >-
  Carries the current change, or someone else's pull request, to a ready-to-merge or merged PR without further check-ins: proves it, files the PR, watches checks and reviews, fixes findings, and asks only when blocked. Use when the user says "full stop" (stop when ready to merge) or "full send" (merge once the merge gate passes), or asks to take over or finish a PR or branch unattended.
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

Either trigger grants force-pushing your own PR branch after a rebase, with
`git push --force-with-lease=<branch>:<sha you rebased from>`, and closing a PR as
§ Starting point allows. Only a merge trigger grants merging, and only when the merge
gate passes. Neither grants rewriting another author's branch, pushing to the base or
a protected branch, `gh pr merge --admin`, or bypassing branch protection. Ask when
the work grows beyond what the user asked for.

## Starting point

- **Work in this thread:** finish it.
- **Someone else's PR or branch ("take over"):** read its description, linked issue,
  and diff against a fresh fetch of the base. If work already on the base makes it
  unnecessary, close it with a comment linking that work and stop. Otherwise add
  commits to it when you can push to it, never rewriting its history, or start your
  own branch that uses it as reference. Keep the original author's credit: preserve
  their commits or add a `Co-authored-by:` trailer, and link the original PR. Comment
  on the original with a link to the replacement; close it only once the replacement
  merges.

## Flow

1. **Finish** the change under `pm:house-rules`.
2. **Prove it.** Proof is evidence you observed in this session at the highest stable
   testing seam: reproduce the original failure, apply the fix, and watch the same
   reproduction pass; run the checks the repository's CI runs. For UI or runtime
   behavior, run the app and look at the change; green mocked tests do not prove
   what a user sees.
3. **Review.** Apply `harness:risk-gate`. When it requires independent review,
   submit the same fixed-target `harness:delegate` request with `operation: review`
   that `pm:dev-task` § 5 builds, including its review axes and its cost-approval rule
   for `route: independent`, under the round limit in
   [review-proof.md](../../references/review-proof.md). A rebase whose
   `git range-diff` shows no content change keeps the approval and does not use a
   round. Fix findings that are right; dispute wrong ones with a one-line reason.
   Review makes the change correct, not bigger: record out-of-scope findings as
   follow-ups.
4. **File the PR** with the house-rules body, including the review disclosure.
5. **Watch it.** When the host provides a pull-request watcher tool (such as
   `watch_pull_request`), use it and end the turn; it wakes you on checks, comments,
   and conflicts. Call its unwatch tool before you stop. Otherwise poll with
   `gh pr checks <n> --watch`,
   `gh pr view <n> --json headRefOid,mergeStateStatus,reviews,comments`,
   and `gh api --paginate repos/{owner}/{repo}/pulls/<n>/comments` for inline review
   comments. Fix CI failures and review comments from bots and people, or reply to
   each with a written reason. Rebase when the branch falls behind. Keep the PR's
   review disclosure current after every review round.
6. **Merge gate.** All of these hold on one head commit, recorded as `headRefOid`:
   - the proof covers every change in the diff;
   - required checks are green (`gh pr checks <n> --required`), none pending; when
     the repository reports none, nothing in `gh pr checks <n>` is failing or pending;
   - every review bot has finished, and each finding, inline ones included, is fixed
     or answered in writing;
   - a required independent review approved this head, or one it differs from only
     by a content-free rebase;
   - no person's last `APPROVED` or `CHANGES_REQUESTED` review in `reviews` requests
     changes; a `COMMENTED` review or a written reply does not clear a change request,
     only their approving re-review does, so ask the user when one stands;
   - the base is an ancestor of the head after a fresh fetch, and GitHub reports
     `mergeStateStatus` as `CLEAN`.

   "Full stop" ends here. "Full send" merges with the method the repository already
   uses, as in `pm:tidy-up` § 3, adding `--match-head-commit <headRefOid>` so a push
   after the gate cannot merge unproven; a mismatch reopens the gate. Then confirm
   `gh pr view <n> --json state` reports `MERGED`, waiting out a merge queue first.
7. **Report** in five lines or fewer: PR link, final state, proof, and anything skipped.

## Asking the user

A question in a normal message goes unseen and the thread looks finished. Ask only
when you cannot continue alone: a choice the user owns, missing access, or a gate you
cannot make pass. Use the host's structured question tool (`AskUserQuestion` in
Claude Code, `request_user_input` in Codex) so the thread shows it is waiting, and put everything in the question:
the PR link, what blocks you, and the options with your recommendation first. When
access or confidence is missing, take the safe path: stop at ready rather than merge.
