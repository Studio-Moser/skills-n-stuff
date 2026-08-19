#!/usr/bin/env bats
#
# Repo-wide guard: every SKILL.md must have YAML frontmatter a strict parser
# accepts. Claude Code is lenient, so a malformed description ships unnoticed —
# but stricter consumers drop the skill silently. `npx skills` skipped
# pm:dev-task entirely for exactly this reason: an unquoted plain scalar
# containing "Do NOT use for: batching …" reads as a nested mapping.
#
# Lives in pm's suite because pm has the only bats harness in the repo; the
# check itself is repo-wide by design.

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
}

@test "every plugins/*/skills/*/SKILL.md has strictly-valid YAML frontmatter" {
  run python3 - "$REPO" <<'PY'
import glob, os, re, sys
try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required for strict skill frontmatter validation. Install it with: python3 -m pip install PyYAML")
    sys.exit(2)

repo = sys.argv[1]
bad = []
checked = 0
for path in sorted(glob.glob(os.path.join(repo, "plugins/*/skills/*/SKILL.md"))):
    text = open(path).read()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    rel = os.path.relpath(path, repo)
    if not m:
        bad.append((rel, "no frontmatter block"))
        continue
    try:
        meta = yaml.safe_load(m.group(1))
    except Exception as e:
        bad.append((rel, f"{type(e).__name__}: {str(e).splitlines()[0]}"))
        continue
    if not isinstance(meta, dict) or not meta.get("name") or not meta.get("description"):
        bad.append((rel, "frontmatter missing name or description"))
        continue
    checked += 1

for rel, why in bad:
    print(f"{rel}: {why}")
print(f"checked={checked} bad={len(bad)}")
sys.exit(1 if bad else 0)
PY
  if [ "$status" -ne 0 ]; then
    echo "$output"
  fi
  [ "$status" -eq 0 ]
}

@test "PM skill descriptions are concise invocation conditions" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import re
import sys

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required for PM description validation. Install it with: python3 -m pip install PyYAML")
    sys.exit(2)

repo = Path(sys.argv[1])
failures = []
for path in sorted((repo / "plugins/pm/skills").glob("*/SKILL.md")):
    match = re.match(r"^---\n(.*?)\n---\n", path.read_text(), re.S)
    if not match:
        continue
    description = yaml.safe_load(match.group(1))["description"].strip()
    relative = path.relative_to(repo)
    if not description.startswith("Use when "):
        failures.append(f"{relative}: description must start with 'Use when '")
    if len(description) > 500:
        failures.append(f"{relative}: description exceeds 500 characters")
    for process_marker in ("Trigger:", "Triggers include", "Workflow:"):
        if process_marker.lower() in description.lower():
            failures.append(f"{relative}: description includes process marker {process_marker!r}")

if failures:
    print("\n".join(failures))
    raise SystemExit(1)
PY
  if [ "$status" -ne 0 ]; then
    echo "$output"
  fi
  [ "$status" -eq 0 ]
}
