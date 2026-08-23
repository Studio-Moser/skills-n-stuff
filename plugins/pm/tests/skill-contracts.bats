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
    "lower or new seam exception": "If the selected seam is lower than an existing stable boundary or must be newly added",
    "pull request slice packaging": "Each proposed pull request completes one delivery slice",
    "frontier execution pool": "The execution pool is the unblocked frontier",
    "wide refactor sequence": "expand → migrate callers in green batches → contract",
    "triage route": "skills/triage/SKILL.md",
    "sprint route": "skills/sprint-dev/SKILL.md",
    "worker route": "skills/dev-task/SKILL.md",
    "Harness execution route": "harness:execute",
    "Harness contract": "../../harness/references/harness-contract.md",
    "Harness handoff": "../../harness/references/handoff.md",
    "Harness verification": "../../harness/references/verification.md",
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
            "# xl-phase3-selection:start",
            'triage_items=("${phase3_items[@]}")',
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

@test "local XL selection replaces the goal epic with its children" {
  local reference="$REPO/plugins/pm/references/triage-local.md"
  local selection_code

  selection_code="$(awk '/# xl-phase3-selection:start/{capture=1; next} /# xl-phase3-selection:end/{capture=0} capture' "$reference")"
  [ -n "$selection_code" ] || {
    echo "triage-local.md has no executable XL Phase 3 selection block"
    return 1
  }

  run env SELECTION_CODE="$selection_code" bash -c '
    triage_items=("/tmp/104-parent.yml" "/tmp/88-other.yml")
    item_file="/tmp/104-parent.yml"
    child_file="/tmp/119-child.yml"
    eval "$SELECTION_CODE"
    child_file="/tmp/120-child.yml"
    eval "$SELECTION_CODE"
    printf "%s\n" "${triage_items[@]}"
  '

  [ "$status" -eq 0 ]
  [ "$output" = $'/tmp/88-other.yml\n/tmp/119-child.yml\n/tmp/120-child.yml' ]
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
    if "canonical Testing Seam selection rule" not in normalized:
        failures.append(f"{label} does not apply the canonical Testing Seam rule")
    if "references/work-readiness.md" not in normalized:
        failures.append(f"{label} does not route Testing Seam evaluation to work-readiness")
    for copied_definition in (
        "highest stable existing boundary",
        "If it chooses a lower boundary or adds a new seam",
    ):
        if copied_definition in normalized:
            failures.append(f"{label} duplicates the canonical Testing Seam definition")

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
protocol_start = text.find("## Evaluation protocol")
protocol_end = text.find("\n## ", protocol_start + 1)
protocol_section = text[protocol_start:protocol_end]
protocol = (
    "## Evaluation protocol",
    "fresh-context",
    "skill or agent named by the scenario's `Prompt`",
    "every reference it routes to",
    "observed result artifact",
    "commit SHA",
    "controller appends each pass criterion",
)
normalized_text = " ".join(text.split()).lower()
normalized_protocol = " ".join(protocol_section.split()).lower()
missing_protocol = [needle for needle in protocol if needle.lower() not in normalized_protocol]
if missing_protocol:
    failures.append("protocol: " + ", ".join(missing_protocol))
if "plugins/pm/skills/triage/SKILL.md".lower() in normalized_protocol:
    failures.append("protocol hard-codes the triage route for every scenario")

route_contracts = {
    "triage": ("## Unverified bug triage", "/pm:triage", "routed references"),
    "sprint": ("## Colliding sprint items", "/pm:sprint-dev", "local sprint backend reference"),
    "review": ("## Schema-changing review", "plugins/pm/agents/code-reviewer.md", "every reference it routes to"),
}
for label, (section_heading, *needles) in route_contracts.items():
    start = text.find(section_heading)
    end = text.find("\n## ", start + 1)
    section = text[start:] if end == -1 else text[start:end]
    normalized_section = " ".join(section.split()).lower()
    missing = [needle for needle in needles if needle.lower() not in normalized_section]
    if start == -1 or missing:
        failures.append(f"{label} route: " + ", ".join(missing or [section_heading]))
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

@test "execution consumers use readiness fields and schedule the unblocked frontier" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

repo = Path(sys.argv[1])
sprint = (repo / "plugins/pm/skills/sprint-dev/SKILL.md").read_text()
dev_task = (repo / "plugins/pm/skills/dev-task/SKILL.md").read_text()
evaluation = (repo / "plugins/pm/evals/PM Skill Eval.md").read_text()

failures = []
for label, text in (("sprint-dev", sprint), ("dev-task", dev_task)):
    if "references/work-readiness.md" not in text:
        failures.append(f"{label} does not load work-readiness")
    for field in ("Outcome", "Blockers", "Testing Seam", "Proof"):
        if field not in text:
            failures.append(f"{label} omits {field}")
    normalized = " ".join(text.split())
    for clause in ("harness:execute", "operation: execute", "authority:",
                   "working_directory:", "allowed_paths:", "verification:",
                   "seam:", "expected:"):
        if clause not in normalized:
            failures.append(f"{label} omits Harness execution request field: {clause}")

normalized_sprint = " ".join(sprint.split()).lower()
for phrase in (
    "unblocked frontier",
    "scheduling collision",
    "delivery slice",
    "run sequentially",
):
    if phrase not in normalized_sprint:
        failures.append(f"sprint-dev omits execution rule: {phrase}")
if "max 8 items per batch" in normalized_sprint:
    failures.append("sprint-dev retains the numeric batch cap")
if "same files must go in the same cluster" in normalized_sprint:
    failures.append("sprint-dev still forces colliding outcomes into one batch")

for copied_definition in (
    "the execution pool is the unblocked frontier",
    "each proposed pr must complete one delivery slice",
    "shared paths are a scheduling collision",
):
    if copied_definition in normalized_sprint:
        failures.append(f"sprint-dev duplicates canonical definition: {copied_definition}")
for application_rule in (
    "apply the canonical unblocked-frontier and delivery-slice packaging rules",
    "for each scheduling collision",
):
    if application_rule not in normalized_sprint:
        failures.append(f"sprint-dev omits canonical application instruction: {application_rule}")

eval_section = evaluation[evaluation.find("## Colliding sprint items"):]
for needle in (
    "### Prompt",
    "Write the observed result artifact to",
    "### Pass criteria",
    "Colliding Sprint Result.md",
    "Sources/AppState.swift",
    "A -> C",
    "unblocked frontier",
    "scheduling collision",
):
    if needle.lower() not in eval_section.lower():
        failures.append(f"colliding-item eval omits {needle}")

if failures:
    print("invalid execution readiness contract: " + "; ".join(failures))
    raise SystemExit(1)
PY
  if [ "$status" -ne 0 ]; then
    echo "$output"
  fi
  [ "$status" -eq 0 ]
}

@test "review consumers use one fixed-point and blast-radius proof contract" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

repo = Path(sys.argv[1])
reference_path = repo / "plugins/pm/references/review-proof.md"
if not reference_path.is_file():
    print(f"missing reference: {reference_path.relative_to(repo)}")
    raise SystemExit(1)

reference = reference_path.read_text()
consumers = {
    "code-reviewer": (repo / "plugins/pm/agents/code-reviewer.md").read_text(),
    "dev-task": (repo / "plugins/pm/skills/dev-task/SKILL.md").read_text(),
    "sprint-dev": (repo / "plugins/pm/skills/sprint-dev/SKILL.md").read_text(),
}
evaluation = (repo / "plugins/pm/evals/PM Skill Eval.md").read_text()

failures = []
required_reference = {
    "consumer pointers": "## Consumer pointers",
    "Harness boundary": "## Harness boundary",
    "quality axis": "### Quality",
    "spec axis": "### Spec Fidelity",
    "blast-radius axis": "### Blast Radius",
    "persisted-schema trigger": "Persisted data, schema, or migration",
    "public-contract trigger": "Public API, protocol, wire format, or serialization",
    "security trigger": "Authentication, authorization, permissions, or another security boundary",
    "shared-runtime trigger": "Shared runtime, dependency, build, deployment, or configuration behavior",
    "Harness request/result": "../../harness/references/harness-contract.md",
    "Harness execution": "../../harness/skills/review/SKILL.md",
    "Harness evidence": "../../harness/references/verification.md",
    "central assumption": "central safety assumption",
    "completion": "## Completion conditions",
    "new request rule": "new Harness review request",
}
missing = [label for label, needle in required_reference.items() if needle not in reference]
if missing:
    failures.append("reference: " + ", ".join(missing))

for label, text in consumers.items():
    if "references/review-proof.md" not in text:
        failures.append(f"{label} does not load review-proof")
    normalized = " ".join(text.split())
    for clause in ("harness:review", "operation: review", "route: review",
                   "verification:", "fixed_target:"):
        if clause not in normalized:
            failures.append(f"{label} omits Harness review request field: {clause}")

eval_start = evaluation.find("## Schema-changing review")
if eval_start == -1:
    failures.append("schema-review eval section missing")
else:
    eval_section = evaluation[eval_start:]
    for needle in (
        "### Prompt",
        "Schema Review Result.md",
        "3333333333333333333333333333333333333333",
        "fresh-install",
        "upgrade-from-V1",
        "central safety assumption",
        "### Pass criteria",
    ):
        if needle.lower() not in eval_section.lower():
            failures.append(f"schema-review eval omits {needle}")

if failures:
    print("invalid review-proof contract: " + "; ".join(failures))
    raise SystemExit(1)
PY
  if [ "$status" -ne 0 ]; then
    echo "$output"
  fi
  [ "$status" -eq 0 ]
}

@test "ingest preserves source claims and loads only the selected backend procedure" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

repo = Path(sys.argv[1])
skill = (repo / "plugins/pm/skills/ingest/SKILL.md").read_text()
analyst = (repo / "plugins/pm/agents/ingestion-analyst.md").read_text()
references = {
    name: repo / f"plugins/pm/references/ingest-{name}.md"
    for name in ("github", "local", "trello")
}

failures = []
for name, path in references.items():
    if not path.is_file():
        failures.append(f"missing {path.relative_to(repo)}")

for label, text in (("ingest", skill), ("ingestion analyst", analyst)):
    normalized = " ".join(text.split()).lower()
    for field in ("evidence", "proposed outcome", "rationale", "source", "confidence", "target repo"):
        if field not in normalized:
            failures.append(f"{label} omits {field}")
    for stale_field in ("suggested_size", "suggested_priority"):
        if stale_field in text:
            failures.append(f"{label} still promotes source advice through {stale_field}")

normalized_skill = " ".join(skill.split()).lower()
for phrase in (
    "references/ingest-${backend}.md",
    "load exactly one",
    "do not load any other ingest backend reference",
    "proposal, not a commitment",
):
    if phrase.lower() not in normalized_skill:
        failures.append(f"ingest dispatch omits: {phrase}")

for backend_marker in (
    "gh issue list",
    "gh issue create",
    "mcp__trello__get_cards_by_list_id",
    "mcp__trello__add_card_to_list",
    'items_dir="$primary_repo_root/',
):
    if backend_marker in skill:
        failures.append(f"ingest keeps backend procedure inline: {backend_marker}")

if all(path.is_file() for path in references.values()):
    texts = {name: path.read_text() for name, path in references.items()}
    required = {
        "github": ("gh issue list", "gh issue create"),
        "local": (".pm/items", "item_file", "status/needs-triage"),
        "trello": ("mcp__trello__get_cards_by_list_id", "mcp__trello__add_card_to_list"),
    }
    for name, needles in required.items():
        missing = [needle for needle in needles if needle not in texts[name]]
        if missing:
            failures.append(f"{name} ingest reference omits: {', '.join(missing)}")
    contamination = {
        "github": ("mcp__trello__", ".pm/items/"),
        "local": ("gh issue ", "mcp__trello__"),
        "trello": ("gh issue ", ".pm/items/"),
    }
    for name, forbidden in contamination.items():
        found = [needle for needle in forbidden if needle in texts[name]]
        if found:
            failures.append(f"{name} ingest reference contains another backend: {', '.join(found)}")

if failures:
    print("invalid ingest disclosure contract: " + "; ".join(failures))
    raise SystemExit(1)
PY
  if [ "$status" -ne 0 ]; then
    echo "$output"
  fi
  [ "$status" -eq 0 ]
}

@test "setup loads one backend reference and keeps backend procedures behind it" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

repo = Path(sys.argv[1])
skill = (repo / "plugins/pm/skills/setup/SKILL.md").read_text()
references = {
    name: (repo / f"plugins/pm/references/setup-{name}.md").read_text()
    for name in ("github", "local", "trello")
}

failures = []
normalized = " ".join(skill.split()).lower()
for phrase in (
    "references/setup-${backend}.md",
    "load exactly one",
    "do not load another setup backend reference",
    "harness:execute",
    "harness:review",
    "run /harness:setup, then rerun /pm:setup",
    "pm must not inspect or create harness routing configuration",
):
    if phrase.lower() not in normalized:
        failures.append(f"setup dispatch omits: {phrase}")

for backend_marker in (
    "gh label create",
    "mcp__trello__list_boards",
    "mcp__trello__add_list_to_board",
    "TRELLO_API_KEY",
    "backend: trello",
    "setup-github-projects.md",
):
    if backend_marker in skill:
        failures.append(f"setup keeps backend procedure inline: {backend_marker}")

for harness_owned in ("harness:model-rubric", "harness:sync", "/machine:",
                      "Rubric" + "_Setup.md"):
    if harness_owned in skill:
        failures.append(f"setup restates Harness setup mechanics: {harness_owned}")

required = {
    "github": ("## Generate .pm/config.yml", "gh label create", "setup-github-projects.md"),
    "local": ("## Generate .pm/config.yml", ".pm/items"),
    "trello": ("## Generate .pm/config.yml", "backend: trello", "mcp__trello__list_boards", "mcp__trello__add_list_to_board"),
}
for name, needles in required.items():
    missing = [needle for needle in needles if needle not in references[name]]
    if missing:
        failures.append(f"{name} setup reference omits: {', '.join(missing)}")

if "only if the user wants" not in references["github"].lower():
    failures.append("GitHub setup does not gate the optional Projects reference")

contamination = {
    "github": ("mcp__trello__", ".pm/items/"),
    "local": ("gh label create", "mcp__trello__"),
    "trello": ("gh label create", ".pm/items/"),
}
for name, forbidden in contamination.items():
    found = [needle for needle in forbidden if needle in references[name]]
    if found:
        failures.append(f"{name} setup reference contains another backend: {', '.join(found)}")

if failures:
    print("invalid setup disclosure contract: " + "; ".join(failures))
    raise SystemExit(1)
PY
  if [ "$status" -ne 0 ]; then
    echo "$output"
  fi
  [ "$status" -eq 0 ]
}

@test "House Rules and PM README expose the work-readiness behavior without redefining it" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

repo = Path(sys.argv[1])
house = " ".join((repo / "plugins/harness/references/house-rules.md").read_text().split()).lower()
readme_text = (repo / "plugins/pm/README.md").read_text()
readme = " ".join(readme_text.split()).lower()
failures = []

for phrase in (
    "highest stable existing testing seam",
    "procedure and expected result",
    "nearest observable indirect contract",
):
    if phrase not in house:
        failures.append(f"House Rules omits {phrase!r}")

for phrase in (
    "references/work-readiness.md",
    "references/review-proof.md",
    "verified claims",
    "unblocked frontier",
    "scheduling collisions",
    "harness contract",
    "harness:execute",
    "harness:review",
    "spec fidelity",
    "blast radius",
    "selected backend reference",
):
    if phrase not in readme:
        failures.append(f"PM README omits {phrase!r}")

if "## verified claims" in readme_text or "## delivery slices" in readme_text:
    failures.append("PM README redefines canonical work-readiness sections")
if "## harness boundary" in readme_text or "## harness evidence" in readme_text:
    failures.append("PM README redefines canonical review-proof sections")

if failures:
    print("invalid Task 7 documentation contract: " + "; ".join(failures))
    raise SystemExit(1)
PY
  if [ "$status" -ne 0 ]; then
    echo "$output"
  fi
  [ "$status" -eq 0 ]
}
