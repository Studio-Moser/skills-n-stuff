#!/usr/bin/env bats

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  HOOK="$REPO/plugins/harness/scripts/activate-execute-skill.mjs"
  SKILL="$REPO/plugins/harness/skills/execute/SKILL.md"
  CONFIG="$REPO/plugins/harness/hooks/hooks.json"
}

@test "execute activation hook stays silent for ordinary prompts" {
  run python3 - "$HOOK" <<'PY'
import json
from pathlib import Path
import subprocess
import sys

hook = Path(sys.argv[1])
for prompt in (
    "Change this button color.",
    "How do a Harness Request and Harness Result relate?",
):
    result = subprocess.run(
        ["node", str(hook)],
        input=json.dumps({"hook_event_name": "UserPromptSubmit", "prompt": prompt}),
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout == "", result.stdout
    assert result.stderr == "", result.stderr
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "execute activation hook supplies the installed skill for explicit contracts" {
  run python3 - "$HOOK" "$SKILL" <<'PY'
import json
from pathlib import Path
import subprocess
import sys

hook = Path(sys.argv[1])
skill = Path(sys.argv[2]).read_text()
result = subprocess.run(
    ["node", str(hook)],
    input=json.dumps(
        {
            "hook_event_name": "UserPromptSubmit",
            "prompt": (
                "Read /app/Routing_Request.json and write a complete blocked "
                "HarnessResult to /app/Harness_Result.json."
            ),
        }
    ),
    capture_output=True,
    text=True,
)
assert result.returncode == 0, result.stderr
payload = json.loads(result.stdout)
output = payload["hookSpecificOutput"]
assert output["hookEventName"] == "UserPromptSubmit"
context = output["additionalContext"]
assert context.startswith("Detected environment state:")
assert context.index("Follow this order:") < context.index("Installed excerpts:")
assert "Read its public contract or schema before the first operational call" in context
assert "copy its exact `check` value" in context
assert "invoke the full `/harness:execute` skill" in context
assert skill not in context
assert len(context.encode()) < 4_000
assert "missing-rubric" not in context
assert "copy the returned `reason` to" in context
assert "`route.fallback_reason`" in context
assert "`path:<absolute-path>`" in context
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "Claude plugin registers one bounded command hook without a model call" {
  run python3 - "$CONFIG" <<'PY'
import json
from pathlib import Path
import sys

config = json.loads(Path(sys.argv[1]).read_text())
groups = config["hooks"]["UserPromptSubmit"]
assert len(groups) == 1
handlers = groups[0]["hooks"]
assert handlers == [
    {
        "type": "command",
        "command": "node",
        "args": ["${CLAUDE_PLUGIN_ROOT}/scripts/activate-execute-skill.mjs"],
        "timeout": 5,
    }
]
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}
