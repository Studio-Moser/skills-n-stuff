#!/usr/bin/env bats

# Workflow contracts are separate from the repo-wide YAML frontmatter parser.
# This catches deletion of the work-readiness source of truth or a route a
# later consumer needs to load it at the correct decision point.

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
}

@test "work-readiness reference defines the readiness rules and consumer routes" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

repo = Path(sys.argv[1])
path = repo / "plugins/pm/references/work-readiness.md"
if not path.is_file():
    print(f"missing reference: {path.relative_to(repo)}")
    raise SystemExit(1)

text = path.read_text()
required = {
    "consumer pointers": "## Consumer pointers",
    "verified claims": "Verified claims",
    "testing seams": "Testing seams",
    "delivery slices": "Delivery slices",
    "blocking edges and frontiers": "Blocking edges and frontiers",
    "wide refactors": "Wide refactors",
    "completion conditions": "### Completion conditions",
    "highest stable testing seam": "highest stable boundary",
    "existing seam preference": "prefer an existing seam",
    "wide refactor sequence": "expand → migrate callers in green batches → contract",
    "triage route": "skills/triage/SKILL.md",
    "sprint route": "skills/sprint-dev/SKILL.md",
    "worker route": "skills/dev-task/SKILL.md",
    "implementation route": "skills/codex-implementation/SKILL.md",
}
missing = [label for label, needle in required.items() if needle not in text]
if missing:
    print("missing required work-readiness contract: " + ", ".join(missing))
    raise SystemExit(1)
PY
  if [ "$status" -ne 0 ]; then
    echo "$output"
  fi
  [ "$status" -eq 0 ]
}

@test "triage and specs consume work-readiness before design and preserve slice fields" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import re
import sys

repo = Path(sys.argv[1])
triage = (repo / "plugins/pm/skills/triage/SKILL.md").read_text()
flow = (repo / "plugins/pm/references/triage-spec-flow.md").read_text()
scorecard = (repo / "plugins/pm/references/triage-scorecard.md").read_text()
evaluator = (repo / "plugins/pm/agents/scorecard-evaluator.md").read_text()
template = (repo / "plugins/pm/templates/spec-template.md").read_text()

failures = []

reference_pointer = "references/work-readiness.md"
if reference_pointer not in triage:
    failures.append("triage does not load work-readiness")

for section in ("Readiness Notes", "Delivery Slice"):
    if not re.search(r"\b" + r"\s+".join(section.split()) + r"\b", triage):
        failures.append(f"triage summary omits canonical spec section: {section}")

verification_marker = "## Phase 2: Verify and Spec"
spec_marker = "### Spec creation flow"
if verification_marker not in triage or spec_marker not in triage:
    failures.append("triage has no verification-before-spec structure")
elif triage.index(verification_marker) > triage.index(spec_marker):
    failures.append("bug verification occurs after spec creation")

for field in ("Established", "Unresolved"):
    if field not in triage or field not in flow or field not in template:
        failures.append(f"missing resumption field: {field}")

for field in ("Outcome", "Blockers", "Testing Seam", "Proof"):
    if field not in flow or field not in template:
        failures.append(f"missing delivery-slice field: {field}")

for label, text in (("scorecard", scorecard), ("evaluator", evaluator)):
    if "one delivery slice" not in text:
        failures.append(f"{label} does not require one delivery slice")
    if "Testing Seam" not in text:
        failures.append(f"{label} does not require a testing seam")

if "item's labels" not in scorecard or "Bug claim" not in scorecard:
    failures.append("scorecard prompt does not pass the triage bug signal")
if "item's labels" not in evaluator or "Bug claim" not in evaluator:
    failures.append("evaluator input cannot identify bug claims")

if "S-sized items that skip spec creation" not in triage:
    failures.append("Phase 3 carry-forward omits S-sized items")

if "must not write tracker status" not in scorecard:
    failures.append("Phase 3 does not constrain inline-fix writes")

if "goal epic" not in flow or "child" not in flow:
    failures.append("XL flow does not create child slices under a goal epic")

if failures:
    print("missing triage/spec readiness contract: " + "; ".join(failures))
    raise SystemExit(1)
PY
  if [ "$status" -ne 0 ]; then
    echo "$output"
  fi
  [ "$status" -eq 0 ]
}

@test "readiness notes require explicit approval before persistence" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

triage = (Path(sys.argv[1]) / "plugins/pm/skills/triage/SKILL.md").read_text()
normalized = " ".join(triage.split())
required = [
    "Stage the proposed readiness note in session memory; do not persist it yet.",
    "Approve readiness notes? (yes / edit / skip)",
    "Persist only after explicit user confirmation.",
]
missing = [text for text in required if text not in normalized]
if missing:
    print("readiness-note approval contract missing: " + "; ".join(missing))
    raise SystemExit(1)

positions = [normalized.index(text) for text in required]
if positions != sorted(positions):
    print("readiness-note approval steps are out of order")
    raise SystemExit(1)
PY
  if [ "$status" -ne 0 ]; then
    echo "$output"
  fi
  [ "$status" -eq 0 ]
}

@test "XL splitting has executable procedures for every triage backend" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

repo = Path(sys.argv[1])
triage = (repo / "plugins/pm/skills/triage/SKILL.md").read_text()
contracts = {
    "GitHub": (
        repo / "plugins/pm/references/triage-github.md",
        (
            "## Phase 2, Step 2b.1: Create XL epic and children",
            "gh issue create",
            "status/needs-triage",
            "child_number",
            "epic_number",
            '--add-label "epic"',
            "Blockers",
            "references/github-sub-issues.md",
            "xl_child_ids",
            "Phase 3 carry-forward",
        ),
    ),
    "Local": (
        repo / "plugins/pm/references/triage-local.md",
        (
            "## Phase 2, Step 2b.1: Create XL epic and children",
            "next_num",
            "child_file",
            "status/needs-triage",
            '.labels = ["epic"]',
            "parent_epic",
            "blockers",
            "xl_child_ids",
            'triage_items+=("$child_file")',
        ),
    ),
    "Trello": (
        repo / "plugins/pm/references/triage-trello.md",
        (
            "## Phase 2, Step 2b.1: Create XL epic and children",
            "mcp__trello__add_card_to_list",
            "status/needs-triage",
            "child.id",
            "child.shortUrl",
            "Part of epic",
            'labels: ["epic"]',
            "Blockers",
            "xl_child_ids",
            "Phase 3 carry-forward",
        ),
    ),
}

failures = []
if "Do not write the same relationship again." not in triage:
    failures.append("shared flow does not make existing XL parent links idempotent")
for backend, (path, required) in contracts.items():
    text = path.read_text()
    missing = [needle for needle in required if needle not in text]
    if missing:
        failures.append(f"{backend}: {', '.join(missing)}")
if failures:
    print("incomplete XL backend contract: " + "; ".join(failures))
    raise SystemExit(1)
PY
  if [ "$status" -ne 0 ]; then
    echo "$output"
  fi
  [ "$status" -eq 0 ]
}

@test "spec consumers enforce the canonical testing seam without adding fields" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

repo = Path(sys.argv[1])
flow = (repo / "plugins/pm/references/triage-spec-flow.md").read_text()
scorecard = (repo / "plugins/pm/references/triage-scorecard.md").read_text()
evaluator = (repo / "plugins/pm/agents/scorecard-evaluator.md").read_text()
template = (repo / "plugins/pm/templates/spec-template.md").read_text()

failures = []
for label, text in (("flow", flow), ("template", template)):
    if "Field meanings: `references/work-readiness.md`" not in text:
        failures.append(f"{label} does not defer field meanings to work-readiness")
    if "Seam Selection" in text:
        failures.append(f"{label} adds a non-canonical Seam Selection field")
    for field in ("Established", "Unresolved", "Outcome", "Blockers", "Testing Seam", "Proof"):
        if f"### {field}\n\n{{value}}" not in text:
            failures.append(f"{label} does not expose {field} as a canonical value")

for label, text in (("scorecard", scorecard), ("evaluator", evaluator)):
    normalized = " ".join(text.split())
    if "Seam Selection" in text:
        failures.append(f"{label} evaluates a non-canonical Seam Selection field")
    if "highest stable existing boundary" not in normalized:
        failures.append(f"{label} does not enforce the preferred Testing Seam")
    if "concrete reason" not in normalized:
        failures.append(f"{label} does not require a lower/new Testing Seam reason")

redefinitions = (
    "{Verified evidence and source}",
    "{Remaining hypotheses, gaps, or `none`}",
    "{Required; use `none` when unblocked}",
    "{Required; record current proof state before implementation}",
    "Established: {verified evidence}",
    "Unresolved: {hypotheses and gaps}",
)
for label, text in (("flow", flow), ("template", template)):
    found = [phrase for phrase in redefinitions if phrase in text]
    if found:
        failures.append(f"{label} redefines canonical values: {', '.join(found)}")

if failures:
    print("invalid seam/field consumer contract: " + "; ".join(failures))
    raise SystemExit(1)
PY
  if [ "$status" -ne 0 ]; then
    echo "$output"
  fi
  [ "$status" -eq 0 ]
}

@test "PM readiness eval defines fresh-context behavioral scenarios" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

text = (Path(sys.argv[1]) / "plugins/pm/evals/PM Skill Eval.md").read_text()
required = {
    "unverified bug": (
        "## Unverified bug triage",
        "### Prompt",
        "duplicate invoices",
        "cache invalidation",
        "Write the observed result artifact to",
        "### Pass criteria",
        "Unverified Bug Result.md",
    ),
    "L feature": (
        "## L feature",
        "### Prompt",
        "account-export",
        "tests/account-export.spec.ts",
        "highest stable existing boundary",
        "Write the observed result artifact to",
        "### Pass criteria",
        "L Feature Result.md",
    ),
    "XL split": (
        "## XL split",
        "### Prompt",
        "identifier migration",
        "expand",
        "migrate",
        "contract",
        "Write the observed result artifact to",
        "### Pass criteria",
        "XL Split Result.md",
    ),
}
failures = []
protocol = (
    "## Evaluation protocol",
    "fresh-context",
    "read the current `plugins/pm/skills/triage/SKILL.md`",
    "observed result artifact",
    "commit SHA",
    "controller appends each pass criterion",
)
normalized_text = " ".join(text.split()).lower()
missing_protocol = [needle for needle in protocol if needle.lower() not in normalized_text]
if missing_protocol:
    failures.append("protocol: " + ", ".join(missing_protocol))
for label, needles in required.items():
    start = text.find(needles[0])
    if start == -1:
        failures.append(f"{label}: {needles[0]}")
        continue
    next_start = text.find("\n## ", start + 1)
    section = text[start:] if next_start == -1 else text[start:next_start]
    normalized_section = " ".join(section.split()).lower()
    missing = [needle for needle in needles[1:] if needle.lower() not in normalized_section]
    if missing:
        failures.append(f"{label}: {', '.join(missing)}")
for forbidden in ("bats --filter", "**Reproducible check:**"):
    if forbidden in text:
        failures.append(f"eval mislabels structural checks as behavior: {forbidden}")
if failures:
    print("invalid PM behavioral eval contract: " + "; ".join(failures))
    raise SystemExit(1)
PY
  if [ "$status" -ne 0 ]; then
    echo "$output"
  fi
  [ "$status" -eq 0 ]
}
