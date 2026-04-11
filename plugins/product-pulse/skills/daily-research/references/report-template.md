# Daily Research Report Template

```markdown
# Daily Research — {YYYY-MM-DD}

**Product**: {product name}
**Weekly theme**: {theme or "No weekly brief"}
**Domains scanned**: {N}
**Findings**: {N} total, {N} added to backlog
**Always Check items scanned**: {N}
**Escalations**: {N}

---

## Escalations (Always Check Hits)

{Only populate if one or more Always Check items triggered. Omit the section entirely otherwise.}

### {Always Check ID} — {Topic}

- **Source**: [{source}]({URL})
- **Change detected**: {what shifted vs the hit definition}
- **Reference doc**: {path to Guide doc, if any}
- **Guide doc update required**: {yes/no}
- **Action**: {what the user should do about this}

---

## {Domain Name}

### {Finding Title}
- **Source**: [{source name}]({URL})
- **Summary**: {2-3 sentences}
- **Impact**: {H/M/L} | **Effort**: {H/M/L} | **Confidence**: {H/M/L}
- **Relevance**: {why this matters to the product}
- **Status**: Added to backlog | Noted

{Repeat for each finding in this domain, max 5}

**Sources checked**: {N} ({list with hit/miss})

---

{Repeat for each domain}

---

## Action Items Added to Backlog

### Ideas

| # | Item | Size | Priority | Source | Domain |
|---|------|------|----------|--------|--------|

### Monitor

| # | Item | Trigger | Deadline |
|---|------|---------|----------|

## Noted (Not Added to Backlog)

{Findings that were interesting but didn't make the top 5 cut, with brief reason}

## Source Performance

### Promotions (3+ hits, not in config)
{sources to consider adding}

### Demotions (10+ misses, 0 hits)
{sources to consider removing}

### New Candidates
{sources discovered during research}

## Search Terms Used

| Domain | Terms |
|--------|-------|

## Quiet Domains

{Domains with zero findings — list what was checked}
```
