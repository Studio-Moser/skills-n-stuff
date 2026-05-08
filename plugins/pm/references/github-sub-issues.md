# GitHub Sub-Issues API

GitHub Sub-Issues (GA since March 2025) let you link child issues under a parent epic. This reference documents how to create and query sub-issue relationships via the GraphQL API.

## Link a child issue to a parent epic

```bash
# Get node IDs for both issues
parent_id=$(gh issue view {parent_number} --json id --jq '.id' --repo "$gh_owner/$gh_repo")
child_id=$(gh issue view {child_number} --json id --jq '.id' --repo "$gh_owner/$gh_repo")

# Create the sub-issue relationship
gh api graphql -f query='
  mutation {
    addSubIssue(input: {
      issueId: "'"$parent_id"'"
      subIssueId: "'"$child_id"'"
    }) {
      issue { id }
      subIssue { id }
    }
  }
'
```

**Fallback** — if the GraphQL mutation fails (sub-issues API may not be available on all GitHub plans), fall back to a comment-based link:

```bash
gh issue comment {child_number} \
  --body "Part of epic #{parent_number}" \
  --repo "$gh_owner/$gh_repo"
```

## Query epic progress (count open vs closed sub-issues)

```bash
gh api graphql -f query='
  {
    node(id: "'"$epic_node_id"'") {
      ... on Issue {
        subIssues { totalCount }
        closedSubIssues: subIssues(states: CLOSED) { totalCount }
      }
    }
  }
'
```

To get the `epic_node_id`, first fetch it:

```bash
epic_node_id=$(gh issue view {epic_number} --json id --jq '.id' --repo "$gh_owner/$gh_repo")
```

## Local backend equivalent

For the local YAML backend, link via a `parent_epic` field:

```bash
yq -i '.parent_epic = {parent_number}' "$item_file"
```
