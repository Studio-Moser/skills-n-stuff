# Backlog Workflow

The backlog is split across two files:

- `planning/todos.md` -- live work queue (Roadmap, Ready, Monitor, Manual, Done, Dismissed)
- `planning/ideas.md` -- incoming ideas staging
- `planning/archive/done-YYYY-QN.md` -- merged items older than 7 days

Item IDs are sequential across both files. Roadmap items use `R{N}` prefix.

## Lifecycle

```
idea -> specced -> ready -> in-progress -> awaiting-pr -> done
```

## Statuses

| Status | Where | Meaning |
|--------|-------|---------|
| idea | ideas.md | Raw finding, not yet evaluated |
| specced | ideas.md | Has a spec, needs user review |
| ready | todos.md Ready | Approved for implementation |
| in-progress | todos.md Ready | Currently being worked on |
| awaiting-pr | todos.md Ready | PR created, waiting for merge |
| done | todos.md Done | PR merged |
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
