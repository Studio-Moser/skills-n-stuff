#!/usr/bin/env bats

setup() { REPO="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; }

@test "Harness owns the universal rules and project baseline template" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
rules = root / "plugins/harness/references/house-rules.md"
template = root / "plugins/harness/templates/AGENTS_Baseline.md"
legacy = root / ("studio" + "-baseline")

assert rules.is_file(), f"missing Harness rules: {rules.relative_to(root)}"
assert template.is_file(), f"missing Harness template: {template.relative_to(root)}"
assert not legacy.exists(), f"parallel baseline source remains: {legacy.relative_to(root)}"
PY
  [ "$status" -eq 0 ]
}

@test "project baseline states the semantic Harness contract only" {
  run python3 - "$REPO/plugins/harness/templates/AGENTS_Baseline.md" <<'PY'
from pathlib import Path
import sys

text = " ".join(Path(sys.argv[1]).read_text().split())
lower = text.lower()
for phrase in ("Harness Request", "Harness Result"):
    assert phrase in text, f"baseline omits {phrase}"
required = (
    "semantic route",
    "harness resolves the model and executor",
    "propagates authority",
    "workers return evidence",
    "parent agents reproduce",
)
missing = [phrase for phrase in required if phrase not in lower]
assert not missing, "baseline omits Harness responsibilities: " + ", ".join(missing)

forbidden = (
    "model-rubric.yml", "via:", "command -v", "routing.bulk",
    "routing.quick", "routing.review", "claude-", "codex-",
    "matching namespaced harness skill before acting", "/harness:execute",
)
found = [token for token in forbidden if token in text]
assert not found, "baseline embeds personal route/provider mechanics: " + ", ".join(found)
PY
  [ "$status" -eq 0 ]
}

@test "distributed live tree uses Harness-owned paths" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
legacy_tokens = (
    "studio" + "-baseline",
    "Machine" + "_Setup.md",
    "Rubric" + "_Setup.md",
    "plugins/" + "machine",
    "/" + "machine:",
    "plugins/pm/skills/" + "codex-",
    "plugins/pm/references/" + "model-orchestration",
)
hits = []
tracked = subprocess.check_output(
    ["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard", "-z"]
).decode().split("\0")
for name in filter(None, tracked):
    relative = Path(name)
    if relative.parts[:1] == (".superpowers",) or relative.parts[:2] == ("docs", "superpowers"):
        continue
    path = root / relative
    if not path.is_file():
        continue
    text = path.read_text(errors="ignore")
    for token in legacy_tokens:
        if token in text:
            hits.append(f"{relative}: {token}")
assert not hits, "retired distributed caller remains:\n" + "\n".join(hits)

pm_setup = (root / "plugins/pm/skills/setup/SKILL.md").read_text()
pm_rules = (root / "plugins/pm/skills/house-rules/SKILL.md").read_text()
harness_readme = (root / "plugins/harness/README.md").read_text()
assert "plugins/harness/templates/AGENTS_Baseline.md" in pm_setup
assert "plugins/harness/references/house-rules.md" in pm_rules
assert "/harness:setup" in harness_readme
assert "/harness:model-rubric" in harness_readme
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "marketplace distributes one Harness and no Machine plugin" {
  run python3 - "$REPO/.claude-plugin/marketplace.json" <<'PY'
import json
from pathlib import Path
import sys

plugins = json.loads(Path(sys.argv[1]).read_text())["plugins"]
assert sum(plugin.get("name") == "harness" for plugin in plugins) == 1
assert sum(plugin.get("name") == "machine" for plugin in plugins) == 0
PY
  [ "$status" -eq 0 ]
}
