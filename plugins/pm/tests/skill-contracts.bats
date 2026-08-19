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
  [ "$status" -eq 0 ]
}
