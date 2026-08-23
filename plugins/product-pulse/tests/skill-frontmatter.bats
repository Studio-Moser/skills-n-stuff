#!/usr/bin/env bats

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
}

@test "Product Pulse skill and analyst frontmatter is strictly valid" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import re
import sys

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required for strict frontmatter validation")
    raise SystemExit(2)

root = Path(sys.argv[1]) / "plugins" / "product-pulse"
paths = sorted((root / "skills").glob("*/SKILL.md")) + sorted((root / "agents").glob("*.md"))
failures = []
for path in paths:
    match = re.match(r"^---\n(.*?)\n---\n", path.read_text(), re.S)
    relative = path.relative_to(root)
    if not match:
        failures.append(f"{relative}: no frontmatter block")
        continue
    try:
        metadata = yaml.safe_load(match.group(1))
    except Exception as error:
        failures.append(f"{relative}: {type(error).__name__}: {str(error).splitlines()[0]}")
        continue
    if not isinstance(metadata, dict) or not metadata.get("name") or not metadata.get("description"):
        failures.append(f"{relative}: frontmatter missing name or description")

assert not failures, "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "Product Pulse skills expose Harness invocation without direct agent dispatch" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import re
import sys
import yaml

root = Path(sys.argv[1]) / "plugins" / "product-pulse" / "skills"
failures = []
for path in sorted(root.glob("*/SKILL.md")):
    match = re.match(r"^---\n(.*?)\n---\n", path.read_text(), re.S)
    metadata = yaml.safe_load(match.group(1)) if match else {}
    description = str(metadata.get("description", "")).strip()
    tools = str(metadata.get("allowed-tools", "")).split()
    relative = path.relative_to(root.parent.parent)
    if not description.startswith("Use when "):
        failures.append(f"{relative}: description must start with 'Use when '")
    if len(description) > 500:
        failures.append(f"{relative}: description exceeds 500 characters")
    if "Skill" not in tools:
        failures.append(f"{relative}: allowed-tools omits Skill")
    if "Agent" in tools:
        failures.append(f"{relative}: allowed-tools retains direct Agent dispatch")

assert not failures, "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}
