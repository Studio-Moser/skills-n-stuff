# Sprint Dev — Local Backend Detail

Backend-specific procedure blocks for `/pm:sprint-dev`, split out of `sprint-dev/SKILL.md` so GitHub/Trello users don't have to read past them. Only relevant when `backend == local`; skip this whole file otherwise. Variables (`$backlog_active`, `$backlog_ideas`, etc.) are the same ones resolved earlier in the SKILL.md flow — read this file in-session and continue where you left off.

## Phase 1.1: Load Ready Items — Local

**Local backend:**
Scan `.pm/items/` for files whose `labels:` contain BOTH `status/ready` AND `owner/ai`. Parse YAML.

## Phase 2D.5: Update Issue Tracker — Local

**Local backend:**
Update `.pm/items/{number}-{slug}.yml` with `status: status/done` and `pr: {pr_url}`.

## Phase 2E: Sync Backlog — Local

**Local backend:**
- **PR open, not yet merged** -> update `.pm/items/{number}-{slug}.yml` with `status: status/in-review` and `pr: {pr_url}`
- **PR already merged** -> update `.pm/items/{number}-{slug}.yml` with `status: status/done` and `pr: {pr_url}`
- **Skipped/failed** -> leave the item file unchanged
