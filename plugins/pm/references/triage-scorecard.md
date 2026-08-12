# Triage — Phase 3: Score

Loaded by `pm:triage` at Phase 3. Backend-independent — scoring reads the item and its spec, and writes nothing to the tracker (Phase 4 does that).

Evaluate each item that survived Phase 1 (both specced and unspecced) against the agent-ready scorecard.

## Dispatch the scorecard evaluator

For each item, read `plugins/pm/agents/scorecard-evaluator.md` and use its content as the system prompt for an Agent tool call. Scoring against a fixed checklist is clear-spec work: pass `model` explicitly, set to `routing.bulk` from the rubric (`${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`). Omitting `model` inherits the session model. Provide in the user prompt:

- The item's title, description, and spec (if one was written in Phase 2)
- The project's CONTEXT.md content
- The `.pm/out-of-scope/` directory listing
- The list of configured repos from `pulse-config.yaml`

The agent returns a per-criterion PASS/FAIL with explanations and a verdict.

## Agent-Ready Scorecard

```
Agent-Ready Scorecard:
1. [ ] Clear description (what, not how)
2. [ ] Explicit acceptance criteria
3. [ ] Linked code references with target repo
4. [ ] Negative constraints (cross-refs .pm/out-of-scope/)
5. [ ] Bounded scope (single deliverable, one repo)
6. [ ] No open design questions
```

## Present results

For each item, show:

```
--- Scorecard: {title} ---
Score: {X}/6

1. {PASS|FAIL} Clear description        — {explanation}
2. {PASS|FAIL} Acceptance criteria       — {explanation}
3. {PASS|FAIL} Code references           — {explanation}
4. {PASS|FAIL} Negative constraints      — {explanation}
5. {PASS|FAIL} Bounded scope             — {explanation}
6. {PASS|FAIL} No open design questions  — {explanation}

Verdict: {status/ready+owner/ai | status/ready+owner/human | needs-info}
```

## Claim verification (bugs)

A bug report's description is a claim, not a fact — verification is the step that separates triage from ad-hoc labelling. Before any bug-flavored item (label `bug`, or a body describing broken behavior) can receive a `status/ready` verdict, attempt to verify it:

- **Reproduce it** from the reported steps, or confirm the failing code path by reading the code (cite the path).
- **Confirmed** → note the repro/code path in the spec or a comment; proceed to the verdict.
- **Could not reproduce / claim contradicts the code** → cap the verdict at `needs-info` and record what you tried. The user can override to promote anyway.
- **Verification impractical** (needs hardware, credentials, or a long-running setup) → say so explicitly and let the user decide; never silently skip.

Enhancements skip this gate — there is no claim to verify.

## Verdict thresholds

| Score | Verdict | Meaning |
|-------|---------|---------|
| 6/6 | `status/ready` + `owner/ai` | Fully specced, agent can pick up immediately |
| 4-5/6 | `status/ready` + `owner/human` | Minor gaps — human should review before agent work |
| 0-3/6 | `needs-info` (stays as `status/needs-triage`) | Major gaps — not ready for anyone |

## User decision

For items scoring 6/6, recommend `status/ready` + `owner/ai`. For 4-5/6, recommend `status/ready` + `owner/human`. For 0-3/6, recommend `needs-info`.

Ask the user:

```
Accept verdict? (yes / fix / human / info / skip)
```

- **yes** — accept the recommended verdict
- **fix** — fix the failing criteria now. For each FAIL, present the suggested fix from the scorecard evaluator and apply it to the spec inline. After fixing, re-score (loop back through the scorecard for changed criteria only).
- **human** — override to `status/ready` + `owner/human` regardless of score
- **info** — override to `needs-info` (leave as `status/needs-triage` for later)
- **skip** — skip this item, leave unchanged

### Fixing inline

When the user chooses **fix**, iterate through each failing criterion:

```
Fix {criterion name}?
  Current: {what's there now, or "missing"}
  Suggested: {scorecard evaluator's suggestion}

Apply this fix? (yes / edit / skip)
```

- **yes** — apply the suggested fix to the spec
- **edit** — user provides their own text for this criterion
- **skip** — leave this criterion as-is (it will still FAIL)

After all fixes are applied, update the spec in the backend (same write path as Phase 2 Step 2c) and re-evaluate only the fixed criteria.
