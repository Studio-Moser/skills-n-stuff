#!/usr/bin/env bats

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
}

@test "PM and Product Pulse never discover or call memory providers directly" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
needles = (
    "search_" + "thoughts(",
    "capture_" + "thought(",
    "get_" + "brief(",
    "mcp__" + "shelby",
    "look for MCP tools",
    "Use whatever memory mechanism is available",
    "If a memory MCP is connected",
    "when a memory MCP is available",
)
hits = []
for plugin in ("pm", "product-pulse"):
    base = root / "plugins" / plugin
    for path in sorted(base.rglob("*")):
        if not path.is_file() or "tests" in path.relative_to(base).parts:
            continue
        text = path.read_text(errors="ignore")
        for needle in needles:
            if needle.lower() in text.lower():
                hits.append(f"{path.relative_to(root)}: direct memory provider behavior")
assert not hits, "\n".join(hits)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "Harness owns canonical optional recall and post-proof capture" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1]) / "plugins" / "harness"
contract = " ".join((root / "references/harness-contract.md").read_text().split()).lower()
shelby = " ".join((root / "references/shelby-integration.md").read_text().split()).lower()
execute = " ".join((root / "skills/execute/SKILL.md").read_text().split()).lower()
review = " ".join((root / "skills/review/SKILL.md").read_text().split()).lower()
failures = []
for phrase in ("memory:", "enabled:", "recall:", "capture:"):
    if phrase not in contract:
        failures.append(f"contract missing {phrase}")
for phrase in (
    "canonical project",
    "before any memory read or write",
    "capture intent",
    "evidence.outcome: proven",
    "does not block",
):
    if phrase not in shelby:
        failures.append(f"Shelby boundary missing {phrase}")
for name, text in (("execute", execute), ("review", review)):
    for phrase in ("context.memory", "recall intent", "capture intent"):
        if phrase not in text:
            failures.append(f"{name} missing {phrase}")
assert not failures, "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "memory-enabled workflows pass intent through Harness requests" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
paths = {
    "pm dev task": root / "plugins/pm/skills/dev-task/SKILL.md",
    "pm sprint": root / "plugins/pm/skills/sprint-dev/SKILL.md",
    "daily": root / "plugins/product-pulse/skills/daily-research/SKILL.md",
    "weekly": root / "plugins/product-pulse/skills/weekly-strategist/SKILL.md",
    "deep-dive": root / "plugins/product-pulse/skills/deep-dive/SKILL.md",
}
failures = []
for name, path in paths.items():
    packets = re.findall(r"```yaml\n(operation: .*?)\n```", path.read_text(), re.DOTALL)
    memory_packets = [packet for packet in packets if re.search(r"^\s+memory:\s*$", packet, re.MULTILINE)]
    if not memory_packets:
        failures.append(f"{name}: no Harness request carries memory intent")
        continue
    normalized = " ".join(memory_packets).lower()
    if "enabled:" not in normalized:
        failures.append(f"{name}: memory intent has no optional enable gate")
    if "recall:" not in normalized and "capture:" not in normalized:
        failures.append(f"{name}: memory intent has no recall or capture purpose")
assert not failures, "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}
