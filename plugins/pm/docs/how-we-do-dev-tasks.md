# How we do dev tasks

For ordinary coding work, say what you want. The current agent implements it directly
under the house rules. Run `/pm:dev-task` when you want a visible plan and approval
gates around one change.

## Which tool?

| You have… | Use |
|---|---|
| One focused change to make | Describe it; the current agent handles it directly |
| One focused change needing managed gates | `/pm:dev-task` |
| A whole backlog to burn down | `/pm:sprint-dev` |
| A vague idea to shape first | brainstorming, then direct implementation or `/pm:dev-task` |
| A baffling bug | systematic-debugging, then direct implementation or `/pm:dev-task` |

## What dev-task guarantees
1. It plans first and waits for your approval before writing code.
2. It branches, commits, and PRs the house way (see the house-rules skill).
3. It runs tests and shows you the output before claiming success.
4. It won't quietly expand scope.

The workflow loads the Harness risk gate. The current agent still implements by
default; it delegates only a substantial independent track and requests a separate
review only when the matched risk requires one.
