# Sprint Dev — Fixed-target review loop

## Contents

- [Materialize the fixed target](#materialize-the-fixed-target)
- [Submit the review request](#submit-the-review-request)
- [Verify the result and clean up](#verify-the-result-and-clean-up)
- [Fix loop](#fix-loop)
- [Report](#report)

Loaded by `skills/sprint-dev/SKILL.md` § 2C only when the risk gate requires
independent review or the user explicitly asks for a separate review.

## Materialize the fixed target

Resolve the approved PR base and head to commits, materialize their exact binary
full-index diff under a repository-relative review-artifact path, and identify that
immutable snapshot by its SHA-256 digest. Base and head describe the snapshot in
request context; they are not the fixed target. Stop if any command fails or the
identifier does not have the required shape. Use PM's materializer so a retained exact
artifact is reusable, while a retained path with different bytes blocks review without
being overwritten.

```bash
BASE_SHA="$(git rev-parse "${BASE_REF}^{commit}")" || exit 1
HEAD_SHA="$(git rev-parse "${HEAD_REF}^{commit}")" || exit 1
WORKTREE_ROOT="$(git rev-parse --show-toplevel)" || exit 1
pm="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/pm/*/ 2>/dev/null | sort -V | tail -1)}"; pm="${pm%/}"
REVIEW_ARTIFACT_STATUS=0
REVIEW_ARTIFACT_RESULT="$("$pm/scripts/materialize-review-artifact.sh" "$WORKTREE_ROOT" "$BASE_SHA" "$HEAD_SHA")" || REVIEW_ARTIFACT_STATUS=$?
if [ "$REVIEW_ARTIFACT_STATUS" -eq 3 ]; then
  echo "Review blocked: the retained digest path conflicts with the expected snapshot; inspect the reported path before retrying." >&2
  exit 3
elif [ "$REVIEW_ARTIFACT_STATUS" -ne 0 ]; then
  exit "$REVIEW_ARTIFACT_STATUS"
fi

REVIEW_ARTIFACT_STATE=""
REVIEW_FIXED_TARGET=""
REVIEW_ARTIFACT_REL=""
while IFS='=' read -r key value; do
  case "$key" in
    "state") REVIEW_ARTIFACT_STATE="$value" ;;
    "fixed_target") REVIEW_FIXED_TARGET="$value" ;;
    "artifact") REVIEW_ARTIFACT_REL="$value" ;;
  esac
done <<EOF
$REVIEW_ARTIFACT_RESULT
EOF

case "$REVIEW_ARTIFACT_STATE" in created|reused) ;; *) exit 1 ;; esac
REVIEW_DIGEST="${REVIEW_FIXED_TARGET#snapshot:sha256:}"
printf '%s\n' "$REVIEW_FIXED_TARGET" | grep -Eq '^snapshot:sha256:[0-9a-f]{64}$' || exit 1
[ "$REVIEW_ARTIFACT_REL" = ".harness-review/review-${REVIEW_DIGEST}.patch" ] || exit 1
```

Retain the parsed fixed target and artifact values in PM's orchestrator state through
the Harness call and replace the request placeholders with them. A `created` or
`reused` state may proceed. Exit 3 is a visible review blocker carrying the helper's
path, actual digest, and expected digest; do not delete or replace the conflicting
artifact. Do not rely on shell variables surviving between the materialization,
Harness invocation, and cleanup commands.

## Submit the review request

```yaml
operation: review
route: {review | independent}
outcome: Report whether this fixed PR target satisfies its approved delivery slice
context:
  project: {canonical project identifier when known}
  mode: fresh
  state: {approved item/spec, acceptance criteria, current Testing Seam Proof, base commit ${BASE_SHA} and head commit ${HEAD_SHA}; ${REVIEW_ARTIFACT_REL} is their exact materialized diff}
  files: [{changed and review-relevant repository paths, plus ${REVIEW_ARTIFACT_REL}}]
  memory:
    enabled: {memory.connector is not null}
    recall: []
    capture:
      - when: accepted
        type: decision
        summary: Sprint delivery accepted for {item identifiers}
        content: {proven outcome, durable decisions or gotchas, fixed target, and verification result}
        topics: [pm-sprint-dev, {canonical project identifier}, {item identifiers}]
authority:
  working_directory: {absolute PR worktree}
  allowed_paths: [{read-only PR scope, plus ${REVIEW_ARTIFACT_REL}}]
  tools: [{read-only inspection and project verification tools}]
  approvals: []
constraints:
  - |
    PM review axes:
    Quality: inspect the fixed-point diff and affected paths for correctness,
    regressions, security, edge cases, error handling, performance, maintainability,
    and adequate tests. Reproduce relevant verification instead of accepting the
    implementer's claim.
    Spec Fidelity: compare the fixed-point diff with the approved issue, plan, and
    acceptance criteria. Report missing or partial requirements, unrequested behavior,
    and implementations that do not match the requirement; state when no spec exists.
    Blast Radius: apply this axis when the diff changes Persisted data, schema, or
    migration behavior; Public API, protocol, wire format, or serialization behavior;
    Authentication, authorization, permissions, or another security boundary; or
    Shared runtime, dependency, build, deployment, or configuration behavior. For each
    trigger, name the central safety assumption and require a check aimed at it. If no
    trigger matches, record Blast Radius as not applicable.
    Report each applicable axis separately. Completion requires current proven Harness
    evidence for this fixed target, Quality and Spec Fidelity reports, every triggered
    Blast Radius assumption and check, reproduced verification, and no unresolved or
    unevidenced blocker.
  - Score each finding from 0–100 confidence and report file, line, failure mode, and fix direction
  - Do not modify the fixed target
verification:
  seam: {Testing Seam plus applicable blast-radius checks}
  expected: {approved acceptance result and no unresolved finding above 24 confidence}
  fixed_target: ${REVIEW_FIXED_TARGET}
```

## Verify the result and clean up

Treat the Harness review report as a claim. Recompute the repository-relative
artifact's digest and confirm the returned fixed target equals `${REVIEW_FIXED_TARGET}`.
A changed artifact, digest, or returned target invalidates the review and requires a
new snapshot and request; retain the artifact so the failure remains inspectable.
Reproduce the relevant checks and keep only findings with confidence above 24 while
the artifact remains available.

Only after result-target verification and the relevant reproduced checks succeed,
remove the exact artifact created above. Remove its directory only when empty; never
delete another run's evidence.

```bash
WORKTREE_ROOT="$(git rev-parse --show-toplevel)" || exit 1
REVIEW_DIGEST="{recorded 64-character digest from the request}"
REVIEW_FIXED_TARGET="snapshot:sha256:${REVIEW_DIGEST}"
REVIEW_ARTIFACT_REL="{exact repository-relative artifact path from the request}"
printf '%s\n' "$REVIEW_DIGEST" | grep -Eq '^[0-9a-f]{64}$' || exit 1
[ "$REVIEW_ARTIFACT_REL" = ".harness-review/review-${REVIEW_DIGEST}.patch" ] || exit 1
REVIEW_ARTIFACT_DIR_ABS="$WORKTREE_ROOT/.harness-review"
REVIEW_ARTIFACT_ABS="$WORKTREE_ROOT/$REVIEW_ARTIFACT_REL"
HARNESS_RESULT_FIXED_TARGET="{exact evidence.fixed_target from the returned Harness Result}"
RECOMPUTED_REVIEW_DIGEST="$(shasum -a 256 "$REVIEW_ARTIFACT_ABS" | awk '{print $1}')"
[ "$RECOMPUTED_REVIEW_DIGEST" = "$REVIEW_DIGEST" ] || exit 1
[ "$HARNESS_RESULT_FIXED_TARGET" = "$REVIEW_FIXED_TARGET" ] || exit 1
# Run and confirm the request's verification seam before cleanup.
rm -f "$REVIEW_ARTIFACT_ABS" || exit 1
rmdir "$REVIEW_ARTIFACT_DIR_ABS" 2>/dev/null || true
```

## Fix loop

If required review findings clear the bar, run the fix loop for at most two rounds:

1. Resolve findings using the Phase 2B execution-choice rule. If a worker is justified,
   submit a new complete `harness:delegate` request on the same branch.
2. Fix each finding or dispute it with concrete evidence when it is false or contradicts
   the approved spec.
3. Require one verification pass at the named Testing Seam plus any additional check
   required by the matched risk, with actual output in the returned evidence.
4. After Harness returns the normal follow-up commit, PM pushes it to the existing PR;
   never force-push.
5. Pin the new commit and submit another complete Harness review request. Confirm every
   prior finding is resolved or evidenced as disputed. If a round remains, repeat;
   otherwise report residual issues instead of merging over them.
6. Post a PR comment summarizing fixes, disputes, evidence, and unresolved findings.

No author is above this check. PM-authored fixes use the same fixed-target Harness
review path.

## Report

Report inline:

```
Fixed-target Check: {cluster}
  Fixed point: ${REVIEW_FIXED_TARGET} (base ${BASE_SHA}, head ${HEAD_SHA} in context)
  Axes: {contract report summary}
  Issues found: {N}   Above threshold (>24): {N}
  Round 1 fixed: {N}  disputed: {N}
  Round 2 fixed: {N}  disputed: {N}   (only if a 2nd round ran)
  Re-check: {clean / N residual}
  Completion: {complete / blocked and missing proof}
  Verify output: {pass/fail, pasted}
```

If nothing clears the threshold on the first pass, note "clean" and proceed.
