# Reconcile — CONTEXT.md maintenance and ADR proposals

Loaded by `pm:reconcile` at Phase 4. Both phases are backend-independent — they read git history and write repo docs, never the issue tracker.

---

## Phase 4: CONTEXT.md Maintenance

Scan recent commits for new domain concepts that should be documented in CONTEXT.md.

### 4.1 Collect new files and significant changes

For each configured repo, list files added or modified since the last reconcile:

```bash
new_entities=()
for repo in "${repos[@]}"; do
  changed_files=$(cd "$repo" && git log --since="$last_reconcile" \
    --diff-filter=AM --name-only --oneline 2>/dev/null \
    | grep -v '^[a-f0-9]' | sort -u)

  for f in $changed_files; do
    # Look for files that likely define types, interfaces, or modules
    case "$f" in
      *.swift|*.ts|*.py|*.go|*.rs|*.java|*.rb|*.js)
        new_entities+=("$repo:$f")
        ;;
    esac
  done
done
```

### 4.2 Extract candidate domain terms

For each source file in `new_entities`, scan for patterns that indicate new domain concepts:

- **Type/struct/class definitions**: `struct Foo`, `class Bar`, `type Baz`, `interface Qux`, `enum Quux`
- **Protocol/trait definitions**: `protocol Foo`, `trait Bar`
- **Module/namespace declarations**: `module Foo`, `namespace Bar`, `package foo`
- **New API endpoints**: route definitions, controller actions
- **New constants or configuration keys** that represent domain concepts

Exclude obvious infrastructure types (e.g., `ViewModel`, `Controller`, `Manager`, `Helper`, `Utils`) unless they embed a meaningful domain term.

### 4.3 Propose additions

Read the existing CONTEXT.md:

```bash
context_md_path="$primary_repo_root/$(yq '.context_md // "CONTEXT.md"' "$pm_config")"
```

If CONTEXT.md does not exist, print `"No CONTEXT.md found. Run /pm:setup to create one, or skip."` and move to Phase 5.

For each candidate term, check whether it already appears in CONTEXT.md. If not, propose adding it:

```
Proposed term: {TermName}
  Source: {repo}/{file}:{line}
  Suggested definition: {inferred from context — type declaration, doc comment, or surrounding code}
  Add to CONTEXT.md? (yes / edit / skip)
```

- **yes** -- Add the term to the Terms table in CONTEXT.md as proposed.
- **edit** -- User provides their own definition. Add with the user's text.
- **skip** -- Do not add this term.

When adding a term, append a row to the `## Terms` table:

```markdown
| {TermName} | {definition} | {aliases if any, or "---"} |
```

Print: `"Phase 4 — {X} candidate term(s) found. {Y} added to CONTEXT.md, {Z} skipped."`

---

## Phase 5: ADR Proposals

Scan recent commits for architectural decisions that should be documented.

### 5.1 Identify decision-worthy commits

For each configured repo, review commits since the last reconcile:

```bash
for repo in "${repos[@]}"; do
  cd "$repo" && git log --since="$last_reconcile" --oneline --all \
    --diff-filter=AM --stat 2>/dev/null
done
```

A commit is a candidate for an ADR if it meets ALL THREE criteria:

1. **Hard to reverse** -- introduces a new dependency, changes a data model, adopts a new pattern across multiple files, modifies a public API, or changes a persistence layer.
2. **Surprising without context** -- a future reader would ask "why did we do it this way?" The commit message alone does not explain the trade-off.
3. **Real trade-off** -- there were plausible alternatives that were rejected. Pure bug fixes and minor refactors do not qualify.

Signals to look for:
- New entries in `Package.swift`, `package.json`, `Cargo.toml`, `go.mod`, `Gemfile`, `requirements.txt`, `build.gradle`
- Schema migrations or model changes
- Commits touching 10+ files with a consistent pattern change
- New directories representing architectural boundaries (e.g., `Sources/NewModule/`)
- Replacement of one library with another

### 5.2 Propose ADRs

For each candidate, present to the user:

```
ADR candidate:
  Commit: {sha} — {message}
  Repo: {repo_name}
  Signal: {what triggered the detection — e.g., "new dependency: libfoo added to Package.swift"}
  Proposed title: ADR-{next_number}: {title}
  Create this ADR? (yes / edit / skip)
```

- **yes** -- Create the ADR using the template.
- **edit** -- User adjusts the title or provides additional context before creation.
- **skip** -- Do not create an ADR for this commit.

### 5.3 Write ADRs

Read the ADR template from `plugins/pm/templates/adr-template.md`. Determine the next ADR number:

```bash
adr_dir="$primary_repo_root/$(yq '.adr_dir // "docs/adr"' "$pm_config")"
mkdir -p "$adr_dir"

last_adr=$(ls "$adr_dir" | grep -oE '^[0-9]+' | sort -n | tail -1)
next_adr=$(printf '%04d' $(( ${last_adr:-0} + 1 )))
```

Write the ADR file:

```markdown
# ADR-{next_adr}: {Title}

**Date:** {TODAY}
**Status:** Proposed

## Context

{Why this decision was made. Reference the commit, the problem it solved, and
what alternatives existed. Infer from the commit diff, message, and surrounding
code. Keep factual -- do not speculate beyond what the code shows.}

## Decision

{What was done. Reference specific files, patterns, or dependencies introduced.}

## Consequences

### Positive
- {benefit inferred from the change}

### Negative
- {trade-off or limitation introduced}

### Neutral
- {side-effect worth noting}
```

Save to `{adr_dir}/{next_adr}-{slug}.md`:

```bash
slug=$(echo "{title}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//' | cut -c1-60)
adr_file="$adr_dir/${next_adr}-${slug}.md"
```

Print: `"Phase 5 — {X} ADR candidate(s) found. {Y} created, {Z} skipped."`
