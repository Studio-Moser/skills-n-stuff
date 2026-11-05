# Review proof

This reference is the source of truth for PM's development review axes, Blast Radius
triggers, and PM completion conditions. Harness owns the fixed target, authority,
review execution, and universal evidence semantics.

## Consumer pointers

| Consumer | Load this reference when |
| --- | --- |
| `agents/code-reviewer.md` | Building any PM review request. |
| `skills/dev-task/SKILL.md` | Entering the review gate. |
| `skills/sprint-dev/SKILL.md` | Beginning the fixed-target check for a PR. |
| `skills/ship/SKILL.md` | Entering its review step. |
| `harness:delegate` | Executing the provider-neutral review request against its fixed target. |

## Harness boundary

PM supplies the exact review target, approved requirements, relevant files, Testing
Seam proof, and the Quality, Spec Fidelity, and Blast Radius constraints in a complete
Harness Request. Use the
[Harness contract](../../harness/references/harness-contract.md) for request/result and
authority fields, [Harness delegate](../../harness/skills/delegate/SKILL.md) for fixed-target
execution, and [Harness verification](../../harness/references/verification.md) for
evidence levels, invalidation, and parent reverification.

PM does not approve a changed target or reinterpret an unproven Harness Result. It
submits a new review request whenever Harness reports that the target or oracle changed.

## Project review contract

When the repository root contains `REVIEW.md`, include it in the Reviewer Input Set and
apply its project-specific failure modes, sensitive paths, required checks, and
exclusions. The project contract is additive: it may strengthen or focus this reference,
but it cannot weaken Harness evidence semantics, omit a required review axis, authorize
an unproven result, or expand the reviewer's authority.

If `REVIEW.md` changes after the target was fixed, the review oracle changed. Materialize
a new target and submit a new review request. If it conflicts with this reference, keep
the non-negotiable PM and Harness requirement and report the conflict as a blocker.

Record the contract oracle as `present` plus the SHA-256 digest of its exact bytes, or
as `absent`, when constructing the request. Give the reviewer those exact bytes and
recompute the state and digest before accepting the result. Creation, removal, or a
digest change invalidates the review even when the code artifact is unchanged.

## Review axes

One reviewer reports each applicable axis separately so evidence on one cannot hide a
failure on another.

### Quality

Inspect the fixed-point diff and affected paths for correctness, regressions, security,
edge cases, error handling, performance, maintainability, and adequate tests. Reproduce
the relevant verification instead of accepting an implementer's claim.

### Spec Fidelity

Compare the fixed-point diff with the approved issue, plan, or acceptance criteria.
Report missing or partial requirements, unrequested behavior, and implementations that
do not match the stated requirement. State when no spec is available.

### Blast Radius

Apply this axis when the fixed-point diff changes any of these contracts:

- Persisted data, schema, or migration behavior.
- Public API, protocol, wire format, or serialization behavior.
- Authentication, authorization, permissions, or another security boundary.
- Shared runtime, dependency, build, deployment, or configuration behavior.

For every matched trigger, name the central safety assumption whose failure would harm
existing data, callers, users, deployments, or recovery. Require evidence aimed at that
assumption, not only a green general suite. If no trigger matches, record the axis as
not applicable.

## Harness evidence

Record the Harness Result's fixed target, decisive checks, evidence outcome, and
blockers beside the PM axis report. PM may require additional checks aimed at a Blast
Radius assumption, but their evidence classification and acceptance follow the linked
Harness verification contract. A missing check stays visible as a PM review blocker.

## Actionable findings

A blocking finding names its severity, file and line or narrowest location, trigger or
execution path, concrete failure mode and consequence, evidence that the reviewed
change introduced or exposed it, and a fix direction or proof needed to dispute it.
Block on actionable correctness, security, specification, or Blast Radius failures.

Grade every finding against the approved intent:

- `blocker`: the intended case is wrong, or the finding is a security, permission,
  data-loss, or recovery defect.
- `should`: a real bug that callers will hit within the approved intent.
- `nit`: everything else, including another code path, a rare case, or a small cost.

`blocker` and `should` block completion until fixed or disputed with evidence. The
parent re-grades each finding before fixing it, whatever label it arrived with, and
declines a `nit` in one line as a follow-up. A rare case stays a `blocker` when it
is a security, permission, data-loss, or recovery defect; lower it only with evidence.
When several reviewers disagree, count confirmed defects, not votes.

Do not use a numerical confidence threshold as an acceptance gate. Report a severe
concern without enough proof as an unresolved risk, not a proven defect. Omit optional
cleanup, style preferences, and speculative maintainability suggestions unless the
approved task requires them. Mark a verified pre-existing issue separately from a
regression in the fixed target. If nothing actionable remains, state `No findings`.

## Rereview convergence

The first review covers the full fixed target. After a remediation, review the delta
from the previously reviewed head and the behavior affected by that delta while retaining
unresolved earlier blockers. Verify every prior disposition, suppress repeated findings
without new evidence, and report all observed instances of one bug class together.

Stop early when neither the target nor a relevant risk changed. The two-round PM limit
stops automated correction; it never authorizes merging with residual blockers. A new
unrelated discovery becomes separate work unless it blocks the approved outcome.

### Round accounting

Round 0 is the initial review. Rounds 1 and 2 are the two allowed fix/review rounds, so
a target gets at most three reviews. A further round runs only when the user explicitly
approves it; record that approval. Without it, report residual blockers and stop.

Run `git diff --shortstat <base> <head>` each round and report the size before and after
review. If review grew the diff, confirm each addition is needed for a fix and cut what
is not. Necessary fixes and regression tests legitimately grow a diff, so growth is a
question to answer, not a reason to cut automatically.

### Finding ledger

The parent keeps one ledger per fixed review loop. Each entry has a stable ID that never
changes between rounds, the graded severity, a disposition of `fixed`, `disputed`,
`declined`, or `open`, and the evidence for it. Send the ledger with every rereview as
claims to verify: the reviewer checks each disposition against the current target and
marks it confirmed or still open. A disposition is never proof that a finding is resolved.

Once a round's dispositions are decided, record one line per reviewer. Take the model and
provider from that reviewer's Harness Result. Count `unique` as confirmed findings no
other reviewer raised on this target, and `regraded` as findings whose severity you
changed. A recording failure never blocks review or completion.

```bash
harness="${HARNESS_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/telemetry.py" record-review --consumer "$CONSUMER" --target "$PR_OR_SLUG" \
  --model "$MODEL" --provider "$PROVIDER" --round "$ROUND" --limit 2 \
  --findings '{"fixed":0,"disputed":0,"declined":0,"open":0,"unique":0,"regraded":0}' \
  --diff-lines "$INSERTIONS_PLUS_DELETIONS"
```

Add `--extension-approved` only for a round the user approved past the limit.

## Repeated findings become project rules

After the review loop for a PR ends, on a GitHub-hosted repository, compare its confirmed
and disputed findings with the review comments and PR comments on the last 20 merged PRs
(`gh pr list --state merged --limit 20`, `gh pr view <n> --comments`, and
`gh api --paginate repos/{owner}/{repo}/pulls/<n>/comments`). Propose a rule only when:

- the same failure mode was also reported on an earlier PR, which becomes a one-line
  entry under `REVIEW.md` project failure modes; or
- a finding was disputed with evidence as false, which becomes a one-line exclusion
  naming that false pattern. An exclusion cannot weaken a PM review axis or a Harness
  evidence requirement.

List each proposal in the final report with its one-line text and the PR numbers behind
it, and say nothing when there are none. This step never blocks completion or a merge,
and it asks nothing of an unattended run.

Add a rule only after the user approves that exact line, in its own PR. Never edit
`REVIEW.md` on the reviewed branch, because a digest change invalidates the review.

### Reviewer Input Set

Give the reviewer only the approved requirements, immutable fixed target and exact
artifact, relevant project files, the pinned root `REVIEW.md` oracle when present, and current Testing Seam proof. Exclude builder reasoning,
summaries, proposed verdicts, and prior review verdicts; they are claims, not reviewer
inputs or evidence. On rereview, also give the reviewer the finding ledger, labeled as
claims to verify, because a reviewer cannot verify a disposition it cannot see.

At least one decisive check must contain a positive acceptance signal that exercises or
observes the expected behavior. A missing or skipped check, or one that runs zero relevant cases,
is unproven even when its process exits zero. Empty output supports proof only when emptiness is
the explicit oracle and the actual status/output is recorded.

## Completion conditions

Review is complete only when Harness returns current proven evidence for the requested
fixed target; Quality and Spec Fidelity are reported; every triggered Blast Radius
entry names its central safety assumption and required check; PM reproduces the
relevant verification with a positive acceptance signal; and every blocker is resolved or disputed
with evidence. Every applicable `REVIEW.md` requirement must also be satisfied. Any
unproven assumption, changed target, or changed review contract requires a new Harness review request.
