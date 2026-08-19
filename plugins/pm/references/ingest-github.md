# GitHub Backend Procedures for /pm:ingest

Load this file only when the configured ingest backend is `github`. The main
skill owns extraction, shared filtering, the candidate body, and watermarks.

## Phase 3: Collect Existing Open Work

Read open issues from the configured owner and repo:

```bash
existing_issues="$(gh issue list \
  --state open \
  --json title,body,labels \
  --limit 200 \
  --repo "{owner}/{repo}")"
```

Keep issues still in the PM pipeline: `status/needs-triage`, `status/ready`,
`status/in-progress`, and `status/in-review`. Exclude terminal work. Return each
title and body to the shared similarity check in ingest Phase 3.

## Phase 4: Create the Candidate

Create every survivor in the configured primary issue repo. Use the neutral title
and body prepared by the main skill:

```bash
gh issue create \
  --title "{candidate title}" \
  --body "{candidate body}" \
  --label "status/needs-triage" \
  --repo "{owner}/{repo}"
```

Do not add size, priority, or target-repo routing labels during ingestion. The
body preserves the proposed target repo for triage. Capture the issue number and
URL. In the final summary, report `Issues created in {owner}/{repo}`.

## Errors

If `gh` is missing or unauthenticated, stop and ask the user to install it or run
`gh auth login`. If a read or create fails, print the error and stop without
switching backends.
