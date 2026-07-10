# Sprint Dev — GitHub Backend Detail

Backend-specific procedure blocks for `/pm:sprint-dev`, split out of `sprint-dev/SKILL.md` so Trello/local users don't have to read past them. Only relevant when `backend == github`; skip this whole file otherwise. Variables (`$gh_owner`, `$gh_repo`, etc.) are the same ones resolved earlier in the SKILL.md flow — read this file in-session and continue where you left off.

## Phase 1.1: Load Ready Items — GitHub

**GitHub backend:**
```bash
gh issue list --label "status/ready" --label "owner/ai" --state open --json number,title,body,labels --limit 50 --repo "$gh_owner/$gh_repo"
```
Parse each issue. Extract from the body:
- Acceptance criteria (look for `## Acceptance Criteria` header)
- Code references (look for `## Code References` header)
- Target repo (from labels or body)
- Size (from size/* label)
- Priority (from body or label)

## Phase 2D.5: Update Issue Tracker — GitHub

**GitHub backend:**
```bash
# Comment on the issue with PR link
gh issue comment {number} --body "Implemented in PR {pr_url}. Spec compliance: {met/partial}. Tests: {pass/fail}." --repo "$gh_owner/$gh_repo"

# Close the issue if PR is merged
gh issue close {number} --repo "$gh_owner/$gh_repo"
```

If the item has a parent epic, check epic progress:
```bash
# Count open vs closed sub-issues
gh api graphql -f query='{ node(id: "{epic_node_id}") { ... on Issue { subIssues { totalCount } closedSubIssues: subIssues(states: CLOSED) { totalCount } } } }'
```

## Phase 2E: Sync Backlog — GitHub

**GitHub backend:**
- **PR open, not yet merged** -> the issue remains open with a comment linking the PR (added in 2D.5)
- **PR already merged** -> the issue is closed (done in 2D.5) and a row is added to `## Done (last 7 days)` in `$backlog_active` if one exists
- **Skipped/failed** -> leave the issue open with status unchanged
