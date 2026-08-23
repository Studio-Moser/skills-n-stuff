# Backlog Workflow

The backlog is split across two files:

- `planning/todos.md` -- live work queue (Roadmap, Ready, Monitor, Manual, Done, Dismissed)
- `planning/ideas.md` -- incoming ideas staging
- `planning/archive/done-YYYY-QN.md` -- merged items older than 7 days

Item IDs are sequential across both files. Roadmap items use `R{N}` prefix.

## Lifecycle

```
idea -> specced -> status/ready -> status/in-progress -> status/in-review -> status/done
```

## Statuses

| Status | Where | Meaning |
|--------|-------|---------|
| idea | ideas.md | Raw finding, not yet evaluated |
| specced | ideas.md | Has a spec, needs user review |
| status/ready | todos.md Ready | Approved for implementation (pair with `owner/ai` or `owner/human`) |
| status/in-progress | todos.md Ready | Currently being worked on |
| status/in-review | todos.md Ready | PR created, waiting for merge |
| status/done | todos.md Done | PR merged |
| monitor | todos.md Monitor | Watch-and-wait |
| manual | todos.md Manual | Requires human action |
| dismissed | todos.md Dismissed | No longer relevant |

## Size Guide

| Size | Meaning | Typical Effort |
|------|---------|---------------|
| S | Small / trivial | < 1 hour |
| M | Medium | 1-4 hours |
| L | Large -- needs a spec | 4+ hours |
| XL | Extra large -- needs spec + chunking | Multi-day |
