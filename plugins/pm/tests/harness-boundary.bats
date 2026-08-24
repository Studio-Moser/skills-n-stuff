#!/usr/bin/env bats

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
}

@test "PM contains no Harness control-plane implementation" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1]) / "plugins" / "pm"
forbidden = [
    "model-" + "rubric.yml",
    "references/model-orchestration.md",
    "via" + ":",
    "codex-" + "implementation",
    "codex-" + "review",
    "codex-" + "computer-use",
    "command -v codex",
    "routing.bulk",
    "routing.review",
    "model@" + "effort",
]
hits = []
for path in sorted(root.rglob("*")):
    if not path.is_file() or "tests" in path.relative_to(root).parts:
        continue
    text = path.read_text(errors="ignore")
    for needle in forbidden:
        if needle in text:
            hits.append(f"{path.relative_to(root)}: {needle}")

assert not hits, "PM owns Harness control-plane behavior:\n" + "\n".join(hits)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "PM workflows send semantic Harness operations with domain constraints" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1]) / "plugins" / "pm"
contracts = {
    "dev-task": (
        root / "skills/dev-task/SKILL.md",
        ("harness:execute", "operation: execute", "harness:review", "operation: review",
         "Outcome", "Blockers", "Testing Seam", "Proof", "Spec Fidelity", "Blast Radius"),
    ),
    "sprint-dev": (
        root / "skills/sprint-dev/SKILL.md",
        ("harness:execute", "operation: execute", "harness:review", "operation: review",
         "unblocked frontier", "delivery slice", "Blockers", "Testing Seam",
         "Spec Fidelity", "Blast Radius"),
    ),
    "ingest": (
        root / "skills/ingest/SKILL.md",
        ("harness:execute", "operation: execute", "route: bulk", "source claims",
         "status/needs-triage"),
    ),
    "triage-scorecard": (
        root / "references/triage-scorecard.md",
        ("harness:execute", "operation: execute", "route: bulk", "work-readiness.md",
         "one delivery slice", "Blockers", "Testing Seam"),
    ),
    "code-reviewer": (
        root / "agents/code-reviewer.md",
        ("harness:review", "operation: review", "route: review", "fixed target",
         "Quality", "Spec Fidelity", "Blast Radius"),
    ),
}

failures = []
for name, (path, required) in contracts.items():
    text = path.read_text()
    normalized = " ".join(text.split()).lower()
    missing = [value for value in required if value.lower() not in normalized]
    if missing:
        failures.append(f"{name}: {', '.join(missing)}")

assert not failures, "incomplete PM Harness requests:\n" + "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "fresh Harness packets embed PM-owned instructions without private plugin paths" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]) / "plugins" / "pm"
sources = {
    "dev-task": root / "skills/dev-task/SKILL.md",
    "sprint-dev": root / "skills/sprint-dev/SKILL.md",
    "ingest": root / "skills/ingest/SKILL.md",
    "triage-scorecard": root / "references/triage-scorecard.md",
    "code-reviewer": root / "agents/code-reviewer.md",
}

def packets(path):
    return re.findall(r"```yaml\n(operation: .*?)\n```", path.read_text(), re.DOTALL)

packet_sets = {name: packets(path) for name, path in sources.items()}
failures = []
for name, values in packet_sets.items():
    if not values:
        failures.append(f"{name}: no Harness packet")
    for packet in values:
        for unresolved in (
            "plugins/pm/",
            "references/review-proof.md",
            "references/work-readiness.md",
            "pm:house-rules",
            "against this reference",
        ):
            if unresolved in packet:
                failures.append(f"{name}: unresolved private instruction {unresolved}")

ingest = " ".join(packet_sets["ingest"][0].split())
for rule in (
    "Daily research and deep dives",
    "Weekly recommendations",
    "Weekly briefs",
    "one source finding per item",
    "Preserve named URLs and tools",
    "return an empty list",
    "Do not fabricate, editorialize, assign size or priority",
    "evidence, proposed outcome, rationale, source, confidence, and target repo",
):
    if rule.lower() not in ingest.lower():
        failures.append(f"ingest packet omits analyst rule: {rule}")

scorecard = " ".join(packet_sets["triage-scorecard"][0].split())
for rule in (
    "Clear description",
    "Explicit acceptance criteria and Testing Seam",
    "Linked code references",
    "Negative constraints",
    "Bounded scope",
    "No controlling unknowns",
    "failed readiness gate is always needs-info",
    "Suggested fixes",
):
    if rule.lower() not in scorecard.lower():
        failures.append(f"scorecard packet omits evaluator rule: {rule}")

for name in ("dev-task", "sprint-dev", "code-reviewer"):
    reviews = [packet for packet in packet_sets[name] if "operation: review" in packet]
    if not reviews:
        failures.append(f"{name}: no review packet")
        continue
    review = " ".join(reviews[0].split())
    for rule in (
        "correctness, regressions, security, edge cases, error handling, performance, maintainability, and adequate tests",
        "missing or partial requirements, unrequested behavior",
        "Persisted data, schema, or migration behavior",
        "Public API, protocol, wire format, or serialization behavior",
        "Authentication, authorization, permissions, or another security boundary",
        "Shared runtime, dependency, build, deployment, or configuration behavior",
        "central safety assumption",
        "record Blast Radius as not applicable",
    ):
        if rule.lower() not in review.lower():
            failures.append(f"{name} packet omits review rule: {rule}")

assert not failures, "non-self-contained Harness packets:\n" + "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "sprint review materializes one immutable snapshot digest" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import re
import sys

text = (Path(sys.argv[1]) / "plugins/pm/skills/sprint-dev/SKILL.md").read_text()
packets = re.findall(r"```yaml\n(operation: review.*?)\n```", text, re.DOTALL)
failures = []
if len(packets) != 1:
    failures.append(f"expected one sprint review packet, found {len(packets)}")
else:
    packet = packets[0]
    fixed_targets = re.findall(r"^\s*fixed_target:\s*(.+)$", packet, re.MULTILINE)
    if fixed_targets != ["${REVIEW_FIXED_TARGET}"]:
        failures.append(f"fixed_target is not one materialized identifier: {fixed_targets}")
    if "base commit ${BASE_SHA} and head commit ${HEAD_SHA}" not in packet:
        failures.append("base/head commits are not preserved as context")

for required in (
    'materialize-review-artifact.sh',
    'REVIEW_ARTIFACT_RESULT=',
    'REVIEW_DIGEST="${REVIEW_FIXED_TARGET#snapshot:sha256:}"',
    "^snapshot:sha256:[0-9a-f]{64}$",
):
    if required not in text:
        failures.append(f"snapshot materialization omits: {required}")

assert not failures, "invalid sprint review target:\n" + "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "sprint review packet exposes a repository-relative artifact until verification" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import re
import sys

text = (Path(sys.argv[1]) / "plugins/pm/skills/sprint-dev/SKILL.md").read_text()
packets = re.findall(r"```yaml\n(operation: review.*?)\n```", text, re.DOTALL)
failures = []
if len(packets) != 1:
    failures.append(f"expected one sprint review packet, found {len(packets)}")
else:
    packet = packets[0]
    files = re.findall(r"^\s*files:\s*(.+)$", packet, re.MULTILINE)
    allowed = re.findall(r"^\s*allowed_paths:\s*(.+)$", packet, re.MULTILINE)
    if files != ["[{changed and review-relevant repository paths, plus ${REVIEW_ARTIFACT_REL}}]"]:
        failures.append(f"context.files is not repository-relative: {files}")
    if allowed != ["[{read-only PR scope, plus ${REVIEW_ARTIFACT_REL}}]"]:
        failures.append(f"allowed_paths is not repository-relative: {allowed}")
    for leak in ("${REVIEW_PATCH}", "${REVIEW_ARTIFACT_ABS}", "${WORKTREE_ROOT}", "${TMPDIR", "/tmp/"):
        if leak in "\n".join(files + allowed):
            failures.append(f"review packet leaks absolute artifact path: {leak}")

for required in (
    'REVIEW_ARTIFACT_ABS="$WORKTREE_ROOT/$REVIEW_ARTIFACT_REL"',
    '"state") REVIEW_ARTIFACT_STATE="$value"',
    '"fixed_target") REVIEW_FIXED_TARGET="$value"',
    '"artifact") REVIEW_ARTIFACT_REL="$value"',
    'REVIEW_DIGEST="{recorded 64-character digest from the request}"',
    'REVIEW_ARTIFACT_REL="{exact repository-relative artifact path from the request}"',
    '[ "$REVIEW_ARTIFACT_REL" = ".harness-review/review-${REVIEW_DIGEST}.patch" ] || exit 1',
    'REVIEW_ARTIFACT_DIR_ABS="$WORKTREE_ROOT/.harness-review"',
    'rm -f "$REVIEW_ARTIFACT_ABS"',
):
    if required not in text:
        failures.append(f"artifact lifecycle omits: {required}")

if "review artifact already exists" in text:
    failures.append("sprint-dev keeps the pre-idempotency unconditional collision exit")

verify_marker = "confirm the returned fixed target equals `${REVIEW_FIXED_TARGET}`"
cleanup_marker = 'rm -f "$REVIEW_ARTIFACT_ABS"'
if verify_marker not in text:
    failures.append("artifact lifecycle omits returned-target verification")
elif cleanup_marker in text and text.index(cleanup_marker) < text.index(verify_marker):
    failures.append("review artifact is cleaned before result verification")

assert not failures, "invalid review artifact boundary:\n" + "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "pm setup consumes Harness configured status instead of installation presence" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

repo = Path(sys.argv[1])
pm_setup = (repo / "plugins/pm/skills/setup/SKILL.md").read_text()
harness_setup = (repo / "plugins/harness/skills/setup/SKILL.md").read_text()
failures = []

for required in (
    'allowed-tools: "Bash Read Write Edit ToolSearch Skill"',
    "Invoke `harness:setup` with `mode: status`",
    "available skill names do not establish configuration",
    "status: accepted",
    "evidence.outcome: proven",
    "Harness is not configured. Run /harness:setup, then rerun /pm:setup.",
    "Harness: configured for provider-neutral execution and review (verified by Harness)",
    "run Step 1d before any keep-existing early exit",
):
    if required not in pm_setup:
        failures.append(f"PM setup omits: {required}")

for required in (
    "## Configured-status mode",
    "`mode: status`",
    "read-only",
    "status: accepted",
    "status: blocked",
    "evidence.outcome: proven",
):
    if required not in harness_setup:
        failures.append(f"Harness setup omits status seam: {required}")

assert not failures, "invalid configured-status seam:\n" + "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "PM README describes PM as a Harness operation consumer" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import re
import sys

text = (Path(sys.argv[1]) / "plugins/pm/README.md").read_text()
normalized = " ".join(text.split()).lower()
failures = []

historical = re.compile(r"\b(formerly|historically|previously|legacy|before harness)\b", re.I)
pm_subject = re.compile(r"\b(pm|sprint-dev|dev-task|execution)\b|/pm:", re.I)
dispatch = re.compile(
    r"\bdispatch(?:es|ing)?\b(?=\s+(?:(?:approved|delegated)\s+)?(?:sub[- ]?agents?|agents?|workers?|slices?|work|tasks?|operations?|prs?))",
    re.I,
)
direct_worker = (
    re.compile(r"\b(?:filed|created|opened|updated|implemented|written)\s+by\s+(?:an?\s+)?sub[- ]?agent\b", re.I),
    re.compile(r"\bsub[- ]?agents?\s+(?:know|read|use|follow|work|implement|file|create)s?\b", re.I),
)

def pm_owns_dispatch(clause):
    if historical.search(clause):
        return False
    match = dispatch.search(clause)
    if not match:
        return False
    actor = clause[:match.start()]
    if re.search(r"\bharness\b", actor, re.I):
        return False
    return bool(pm_subject.search(actor) or re.search(r"\bsub[- ]?agents?\b", clause[match.end():], re.I))

for blocked_example in (
    "PM dispatch workers.",
    "Sprint-dev dispatches agents.",
    "Execution is dispatching sub-agents.",
):
    if not pm_owns_dispatch(blocked_example):
        failures.append(f"semantic dispatch guard misses: {blocked_example}")

for allowed_example in (
    "Harness dispatches workers.",
    "Historically, PM dispatches agents before Harness.",
    "The dispatch queue is domain-neutral.",
):
    if pm_owns_dispatch(allowed_example):
        failures.append(f"semantic dispatch guard rejects allowed context: {allowed_example}")

for line_number, line in enumerate(text.splitlines(), 1):
    for clause in re.split(r"(?<=[.!?;])\s+", line):
        if historical.search(clause):
            continue
        if pm_owns_dispatch(clause):
            failures.append(f"line {line_number}: PM directly owns dispatch: {clause.strip()}")
        for pattern in direct_worker:
            match = pattern.search(clause)
            if match and not re.search(r"\bharness\b", clause[:match.start()], re.I):
                failures.append(f"line {line_number}: PM directly owns a sub-agent: {clause.strip()}")

for required in (
    "pm defines the development axes and constraints and submits harness operations",
    "harness owns dispatch, fixed-target materialization, and evidence mechanics",
    "harness may delegate workers",
):
    if required not in normalized:
        failures.append(f"README omits ownership statement: {required}")

for forbidden in ("owns the fixed review target", "pm supplies the exact review target"):
    if forbidden in normalized:
        failures.append(f"README assigns fixed-target mechanics to PM: {forbidden}")

assert not failures, "contradictory README ownership:\n" + "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}
