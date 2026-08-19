# Triage — Phase 2: Spec creation flow

Loaded by `pm:triage` at Phase 2, once the user has approved the speccing order. Runs for each item classified as M/L/XL or unclear; S-sized items with a complete description skip straight to Phase 3.

Prerequisite: `pm:triage` has loaded `references/work-readiness.md`, verified any bug
claim, and persisted the item's `Established` and `Unresolved` readiness notes. Use that
reference for all readiness decisions; this flow only requires its output fields.

Process one item at a time. For each:

## Step 2a: Brainstorm

Invoke the brainstorming skill with the item as the problem statement. Pass all relevant context as the `args` parameter so the skill has what it needs:

```
Skill({ skill: "superpowers:brainstorming", args: "{item title}: {item description}\n\nEstablished: {value}\nUnresolved: {value}\nDomain context: {relevant CONTEXT.md terms}\nConstraints: {relevant out-of-scope entries}\nRepos: {repo list from pulse-config.yaml with paths}" })
```

The brainstorming skill will explore the design space and produce a recommended
approach. It must not promote an `Unresolved` causal hypothesis into the approach.

## Step 2b: Write implementation plan

After brainstorming produces a design direction, invoke the writing-plans skill. Pass the brainstorming output as context:

```
Skill({ skill: "superpowers:writing-plans", args: "Write a spec for: {item title}\n\nEstablished: {value}\nUnresolved: {value}\nBrainstorming output: {brainstorm result summary}\nTarget repo: {repo path}\nRequired readiness fields: Outcome, Blockers, Testing Seam, Proof\nField meanings: references/work-readiness.md" })
```

The writing-plans skill produces a structured implementation plan with tasks, code,
and acceptance criteria. For M/L work, the resulting agent-ready item must contain one
delivery slice. If planning reveals independent outcomes, split them into separate
items rather than hiding them in chunks.

### Step 2b.1: Split XL work

An XL item is a goal epic, not an implementation assignment. Before writing backend
specs:

1. Present the proposed goal epic, child delivery slices, and blocking edges to the
   user. Do not create or relabel tracker items until the user confirms the split.
2. Order the confirmed children so each prerequisite is created before the child that
   names it as a blocker.
3. **(backend step)** — follow the loaded `references/triage-<backend>.md` section
   `Phase 2, Step 2b.1: Create XL epic and children`. It converts the parent, creates
   and links the children, and returns `xl_child_ids`.
4. Load the returned child IDs as the items to write and score independently. Do not
   send the XL parent to Phase 3.

## Step 2c: Write spec to backend

**(backend step)** — follow your loaded `references/triage-<backend>.md` (§ Phase 2, Step 2c: Write spec to backend).

All backends write the spec using this body structure:

Field meanings: `references/work-readiness.md`. Populate every field with its current
value; do not add local definitions.

```markdown
## Goal

{One paragraph — what this achieves}

## Context

{Why this matters now. Link to source report if applicable.}

## Readiness Notes

### Established

{value}

### Unresolved

{value}

## Code References

{Specific files, modules, APIs in the target repo that this touches}
- `{repo_name}/{path/to/file.ext}` — {what it does}

## Approach

{How to implement. Step-by-step, specific enough for an agent.}

## Delivery Slice

### Outcome

{value}

### Blockers

{value}

### Testing Seam

{value}

### Proof

{value}

## Chunks

{For L items — ordered implementation steps within this one delivery slice}

1. {Chunk 1 — description}
2. {Chunk 2 — description}

## Acceptance Criteria

- [ ] {Criterion 1}
- [ ] {Criterion 2}

## Negative Constraints

- Do NOT {constraint from out-of-scope or brainstorming}
- See `.pm/out-of-scope/{slug}.md` for related rejections

---
*Spec written by /pm:triage on {DATE}*
```

## Step 2d: Checkpoint

After each spec is written, print:

```
Spec complete for: {title}
  Size: {size}  Priority: {priority}
  Spec: {path or issue URL}
  Chunks: {N}
  Slice: {Outcome}
  Testing seam: {Testing Seam}

Continue to next item? (yes / stop)
```

- **yes** — proceed to the next item needing a spec
- **stop** — halt speccing. Remaining items will enter Phase 3 without specs (they will likely fail the scorecard, which is fine — the user can resume triage later).
