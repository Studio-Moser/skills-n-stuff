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
