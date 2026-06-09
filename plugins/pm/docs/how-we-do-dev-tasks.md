# How we do dev tasks

One entry point: when you have a coding task, say what you want or run
`/pm:dev-task`. It walks you through it and stops for your OK at the key gates.

## Which tool?

| You have… | Use |
|---|---|
| One focused change to make | `/pm:dev-task` |
| A whole backlog to burn down | `/pm:sprint-dev` |
| A vague idea to shape first | brainstorming, then `/pm:dev-task` |
| A baffling bug | systematic-debugging, then `/pm:dev-task` |

## What dev-task guarantees
1. It plans first and waits for your approval before writing code.
2. It branches, commits, and PRs the house way (see the house-rules skill).
3. It runs tests and shows you the output before claiming success.
4. It won't quietly expand scope.

You stay in control at every gate. When in doubt, just describe the task in
plain language — you don't need to remember the skill name.
