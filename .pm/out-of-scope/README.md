# Out-of-Scope Rejection KB

This directory holds rejection records for features, ideas, and requests that have
been evaluated and deliberately excluded from the project's scope.

## Purpose

When an agent encounters a request or idea that has been previously rejected,
it can check this directory to find the decision record. This prevents:

- Re-litigating settled decisions
- Wasting triage time on known rejections
- Losing the reasoning behind past rejections

## Format

Each file is a markdown document named `{slug}.md` with this structure:

- **Feature/Concept Name** — what was rejected
- **Decided date** — when the decision was made
- **Status** — always "Rejected"
- **Decision** — one paragraph on what was rejected and why
- **Reasoning** — trade-offs considered
- **Prior requests** — log of each time this was requested, with date and context

## Usage

- Triage adds entries here when dismissing items with reusable reasoning.
- Agents check this directory before promoting similar ideas.
- If circumstances change, move the file to an `archived/` subdirectory and
  re-evaluate the request.

See the entry template at `plugins/pm/templates/out-of-scope-entry.md`.
