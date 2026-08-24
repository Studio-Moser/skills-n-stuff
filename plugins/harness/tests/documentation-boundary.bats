#!/usr/bin/env bats

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  ROOT_README="$REPO/README.md"
  HARNESS_README="$REPO/plugins/harness/README.md"
  PULSE_README="$REPO/plugins/product-pulse/README.md"
}

@test "public docs install Harness before dependent plugins" {
  run python3 - "$ROOT_README" "$PULSE_README" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1]).read_text()
pulse = Path(sys.argv[2]).read_text()
harness_install = "/plugin install harness@studio-moser"
pulse_install = "/plugin install product-pulse@studio-moser"
assert harness_install in root and pulse_install in root
assert root.index(harness_install) < root.index(pulse_install)
assert harness_install in pulse
assert pulse.index(harness_install) < pulse.index(pulse_install)
PY
  [ "$status" -eq 0 ]
}

@test "Harness docs list all six public skills" {
  run python3 - "$ROOT_README" "$HARNESS_README" <<'PY'
from pathlib import Path
import sys

skills = ("setup", "sync", "model-rubric", "execute", "review", "computer-use")
for name in sys.argv[1:]:
    text = Path(name).read_text()
    missing = [skill for skill in skills if f"/harness:{skill}" not in text]
    assert not missing, (name, missing)
PY
  [ "$status" -eq 0 ]
}

@test "migration docs replace Machine only after Harness is enabled" {
  run python3 - "$HARNESS_README" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
install = text.index("/plugin install harness@studio-moser")
enable = text.index('"harness@studio-moser": true')
remove = text.index("machine@studio-moser")
uninstall = text.index("/plugin uninstall machine@studio-moser")
assert install < enable < remove
assert enable < uninstall
PY
  [ "$status" -eq 0 ]
}
