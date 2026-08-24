#!/usr/bin/env bats

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SKILL="$REPO/plugins/harness/skills/sync/SKILL.md"
}

@test "sync performs every reconciliation before one guarded final transaction" {
  run python3 - "$SKILL" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
failures = []
required = (
    "reconcile_shared_settings.py",
    "mcp-manifest.sh",
    "skills-manifest.sh",
    "render-codex-agents.sh",
    "portability-lint.sh",
    "sync-finalize.sh",
)
for value in required:
    if value not in text:
        failures.append(f"missing sync operation: {value}")

finalizer = text.find('"$harness/scripts/sync-finalize.sh"')
for value in required[:-1]:
    position = text.rfind(value)
    if position < 0 or position > finalizer:
        failures.append(f"{value} is not completed before finalization")

for direct in ('git -C "$repo" commit', 'git -C "$repo" push'):
    if direct in text:
        failures.append(f"direct transaction bypass remains: {direct}")
for phrase in (
    "exactly one commit, pull, and push",
    "final clean worktree",
    "remote SHA",
    "staged secret",
    "machine-local state",
):
    if phrase.lower() not in text.lower():
        failures.append(f"missing final gate: {phrase}")

assert not failures, "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "every shell block resolves the repo it uses" {
  run python3 - "$SKILL" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
blocks = re.findall(r"```(?:bash|sh)\n(.*?)\n```", text, re.DOTALL)
failures = []
assignment = re.compile(r'^repo="\$\{AGENTS_REPO:-\$HOME/\.agents\}"', re.MULTILINE)
for number, block in enumerate(blocks, 1):
    if "$repo" in block and not assignment.search(block):
        first = block.strip().splitlines()[0] if block.strip() else "<empty>"
        failures.append(f"block {number} uses stale repo: {first}")
assert not failures, "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}
