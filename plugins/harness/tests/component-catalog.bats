#!/usr/bin/env bats

setup() {
  PLUGIN="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
}

@test "component catalog entries are well formed and every anchor still exists" {
  run python3 - "$PLUGIN" <<'PY'
from pathlib import Path
import re
import sys
import tomllib

plugin = Path(sys.argv[1])
items = tomllib.loads((plugin / "Component_Catalog.toml").read_text())["component"]
kinds = {"model-shim", "environment-shim", "preference", "guard"}
failures = []
ids = [item.get("id") for item in items]
for duplicate in sorted({i for i in ids if ids.count(i) > 1}):
    failures.append(f"duplicate id {duplicate}")

def normalized(text):
    return re.sub(r"\s+", " ", text)

def check_anchor(cid, source, anchor):
    path = plugin / source
    if not path.is_file():
        failures.append(f"{cid}: missing source {source}")
    elif normalized(anchor) not in normalized(path.read_text()):
        failures.append(f"{cid}: anchor not found in {source}: {anchor!r}")

for item in items:
    cid = item.get("id", "?")
    for field in ("id", "kind", "source", "anchor"):
        if not isinstance(item.get(field), str) or not item[field]:
            failures.append(f"{cid}: missing {field}")
    if item.get("kind") not in kinds:
        failures.append(f"{cid}: unknown kind {item.get('kind')!r}")
    if str(item.get("kind", "")).endswith("-shim"):
        for field in ("added_for", "retire_test"):
            if not item.get(field):
                failures.append(f"{cid}: shims need {field}")
    detector = item.get("detector", "none")
    if detector.startswith("regex:"):
        re.compile(detector[len("regex:"):])
    elif detector != "none" and not detector.startswith("events:"):
        failures.append(f"{cid}: detector must be none, regex:, or events:")
    check_anchor(cid, item.get("source", ""), item.get("anchor", ""))
    for other in item.get("also", []):
        check_anchor(cid, other.get("source", ""), other.get("anchor", ""))

assert not failures, "\n".join(failures)
print(f"components={len(items)}")
PY
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&2; fi
  [ "$status" -eq 0 ]
}

@test "the silent-routing detector flags announcements and ignores ordinary prose" {
  run python3 - "$PLUGIN" <<'PY'
from pathlib import Path
import re
import sys
import tomllib

plugin = Path(sys.argv[1])
items = {i["id"]: i for i in tomllib.loads((plugin / "Component_Catalog.toml").read_text())["component"]}
pattern = re.compile(items["silent-routing"]["detector"][len("regex:"):])
assert pattern.search("I've classified this as a Small change.")
assert pattern.search("This is Feature-class work, so I'll plan first.")
assert not pattern.search("This is a small fix to the parser.")
assert not pattern.search("The feature flag is off.")
PY
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&2; fi
  [ "$status" -eq 0 ]
}
