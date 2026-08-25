#!/usr/bin/env bats

setup() {
  SEED_PATH="${BATS_TEST_DIRNAME}/../skills/model-rubric/Default_Rubric.yml"
}

@test "seed records work-efficiency evidence instead of legacy cost scores" {
  run python3 - "$SEED_PATH" <<'PY'
from pathlib import Path
import re
import sys

seed_path = sys.argv[1]
text = Path(seed_path).read_text()
for field in (
    "provider:", "trust:", "efficiency:", "benchmark:", "suite: deepswe",
    "pass_at_1:", "mean_task_cost_usd:", "cost_per_success_usd:",
    "mean_output_tokens:", "mean_duration_seconds:",
):
    assert field in text, f"seed missing {field}"
assert not re.search(r"(?m)^\s+cost:\s", text), "legacy model cost score remains"
assert "gpt-5.6-terra" in text, "current delegated candidate missing"
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "benchmark cost per success is derived from observed task cost and pass rate" {
  run python3 - "$SEED_PATH" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
pattern = re.compile(
    r"pass_at_1:\s*([0-9.]+).*?"
    r"mean_task_cost_usd:\s*([0-9.]+).*?"
    r"cost_per_success_usd:\s*([0-9.]+)",
    re.S,
)
rows = pattern.findall(text)
assert rows, "no benchmark observations"
for pass_at_1, task_cost, cost_per_success in rows:
    expected = float(task_cost) / float(pass_at_1)
    assert abs(expected - float(cost_per_success)) <= 0.02
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "model rubric derives explicit compatible cross-provider fallback chains" {
  run python3 - "${BATS_TEST_DIRNAME}/../skills/model-rubric/SKILL.md" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
normalized = " ".join(text.split())
required = (
    "derive an ordered `fallbacks.<route>` chain",
    "every fallback provider differs from every earlier provider in its chain",
    "`taste` fallback meets `routing.taste_min`",
    "`independent` fallback remains distinct from every named authoring provider",
    "legacy `routing.fallback` is never automatic authorization",
    "remove `routing.fallback` only after every replacement chain validates",
    "single-provider rubrics remain valid with no fallback chains",
    "show the fallback chains before writing",
)
missing = [clause for clause in required if clause not in normalized]
assert not missing, "model-rubric fallback contract missing: " + ", ".join(missing)

completed = """fallbacks:
  orchestrator: [backup-model@high]
  default: [backup-model@high]
  quick: [backup-model@high]
  review: [backup-model@high]"""
assert completed in text, "completed-rubric example missing explicit fallback chains"
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "seed defers fallback derivation until after the developer interview" {
  run python3 - "$SEED_PATH" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
assert re.search(r"(?m)^fallbacks:\s*\{\}\s*(?:#.*)?$", text), "seed missing empty fallbacks map"
assert len(re.findall(r"(?m)^fallbacks:", text)) == 1, "seed declares multiple fallback maps"
assert "Setup derives values only after the developer interview" in text
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}
