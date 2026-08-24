#!/usr/bin/env bats

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
}

@test "Product Pulse exposes no directly callable analyst agents" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1]) / "plugins" / "product-pulse"
agents = sorted((root / "agents").glob("*.md")) if (root / "agents").exists() else []
assert not agents, "callable analyst bypasses remain: " + ", ".join(
    str(path.relative_to(root)) for path in agents
)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "weekly role packets stay self-contained and Harness-routed" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1]) / "plugins/product-pulse/skills/weekly-strategist/SKILL.md"
text = " ".join(path.read_text().split())
failures = []
for role in (
    "Market Scout",
    "Competitor Tracker",
    "Audience Analyst",
    "Growth Analyst",
    "Product Scout",
):
    if role not in text:
        failures.append(f"missing embedded role: {role}")
for clause in (
    "Invoke `harness:execute` five times",
    "route: bulk",
    "full context package",
    "do not modify files",
):
    if clause.lower() not in text.lower():
        failures.append(f"missing routed packet clause: {clause}")
assert not failures, "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}
