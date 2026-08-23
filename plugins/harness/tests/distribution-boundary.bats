#!/usr/bin/env bats

setup() { REPO="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; }

@test "harness is the sole control-plane plugin" {
  [ -d "$REPO/plugins/harness" ]
  retired_plugin="$REPO/plugins/""machine"
  [ ! -e "$retired_plugin" ]
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
needles = (
    "plugins/" + "machine",
    "/" + "machine:",
    "machine:" + "model-rubric",
    "machine:" + "sync",
)
hits = []
for path in [root / ".claude-plugin/marketplace.json", root / "plugins/harness", root / "README.md"]:
    files = [path] if path.is_file() else [p for p in path.rglob("*") if p.is_file()]
    for file in files:
        if file == root / "plugins/harness/tests/distribution-boundary.bats":
            continue
        text = file.read_text(errors="ignore")
        for needle in needles:
            if needle in text:
                hits.append(f"{file.relative_to(root)}: {needle}")
assert not hits, "\n".join(hits)
PY
  [ "$status" -eq 0 ]
}
