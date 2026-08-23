#!/usr/bin/env bats

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  SKILLS_ROOT="${HARNESS_SKILLS_ROOT:-$REPO/plugins/harness/skills}"
}

@test "provider-neutral Harness skills have valid frontmatter and focused references" {
  run python3 - "$SKILLS_ROOT" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
expected_references = {
    "setup": {"harness-contract.md", "shelby-integration.md"},
    "execute": {
        "context.md", "handoff.md", "harness-contract.md", "routing.md",
        "shelby-integration.md", "verification.md",
    },
    "review": {
        "context.md", "handoff.md", "harness-contract.md", "routing.md",
        "shelby-integration.md", "verification.md",
    },
    "computer-use": {
        "context.md", "handoff.md", "harness-contract.md", "routing.md",
        "shelby-integration.md", "verification.md",
    },
}

missing = sorted(name for name in expected_references if not (root / name / "SKILL.md").is_file())
assert not missing, f"missing Harness skills: {', '.join(missing)}"

failures = []
for name, expected in expected_references.items():
    path = root / name / "SKILL.md"
    text = path.read_text()
    if not text.startswith("---\n") or "\n---\n" not in text[4:]:
        failures.append(f"{name}: invalid frontmatter delimiters")
        continue
    frontmatter = text.split("---\n", 2)[1]
    match = re.search(r"(?m)^name:\s*(\S+)\s*$", frontmatter)
    if not match or match.group(1) != name:
        failures.append(f"{name}: frontmatter name must be {name}")
    description = re.search(
        r"(?ms)^description:\s*(?:>-\s*\n(?P<folded>(?:^[ \t]+.*\n?)+)|(?P<plain>[^\n]+))",
        frontmatter,
    )
    value = " ".join((description.group("folded") if description and description.group("folded") else description.group("plain") if description else "").split())
    if len(value) < 40 or "Harness" not in value:
        failures.append(f"{name}: description must identify its Harness trigger and boundary")
    actual = set(re.findall(r"references/([a-z-]+\.md)", text))
    if actual != expected:
        failures.append(
            f"{name}: references {sorted(actual)!r}, expected {sorted(expected)!r}"
        )

assert not failures, "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "execution skills preserve request authority and return the complete result contract" {
  run python3 - "$SKILLS_ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
skill_paths = {name: root / name / "SKILL.md" for name in ("execute", "review", "computer-use")}
missing = [name for name, path in skill_paths.items() if not path.is_file()]
assert not missing, f"missing Harness skills: {', '.join(missing)}"
skills = {name: path.read_text() for name, path in skill_paths.items()}

result_fields = (
    "status", "route.requested", "route.actual_model", "route.effort",
    "route.provider", "route.executor", "artifacts.files", "artifacts.report",
    "evidence.fixed_target", "evidence.checks", "evidence.outcome",
    "telemetry.attempts", "telemetry.elapsed", "telemetry.verification_failures",
    "telemetry.token_or_quota_usage", "shelby.project_id", "shelby.run_id",
    "shelby.checkpoint_ids", "blockers",
)
failures = []
for name, text in skills.items():
    normalized = " ".join(text.split())
    if f"`operation` must be `{name}`." not in normalized:
        failures.append(f"{name}: does not accept its HarnessRequest operation")
    missing_fields = [field for field in result_fields if f"`{field}`" not in text]
    if missing_fields:
        failures.append(f"{name}: missing HarnessResult fields {', '.join(missing_fields)}")
    for clause in (
        "Preserve `authority.working_directory` exactly",
        "Pass the resolved model and effort explicitly",
        "Only the parent or accepting workflow may return `status: accepted`",
    ):
        if clause not in normalized:
            failures.append(f"{name}: missing contract clause: {clause}")

execute = " ".join(skills["execute"].split())
for clause in (
    "Default delegated implementation to `fresh`",
    "If `via` is absent, dispatch through the native runtime",
    "outcome, working directory, allowed paths, constraints, verification seam, and the required HarnessResult return shape",
    "Never put secrets in the prompt",
    "never widen sandbox, path, tool, or approval authority",
):
    if clause not in execute:
        failures.append(f"execute: missing adapter clause: {clause}")
for token in ('command -v codex', '-C "$HARNESS_CWD"', '-m "$HARNESS_MODEL"', 'model_reasoning_effort="$HARNESS_EFFORT"'):
    if token not in skills["execute"]:
        failures.append(f"execute: Codex adapter omits {token}")

review = " ".join(skills["review"].split())
for clause in (
    "Require `verification.fixed_target` before dispatch",
    "Only `review` and `independent` are valid review routes",
    "explicit user approval",
    "Treat the worker report as a claim",
    "reproduce the relevant checks",
):
    if clause not in review:
        failures.append(f"review: missing fixed-target clause: {clause}")

computer = " ".join(skills["computer-use"].split())
for clause in (
    "Confirm every required computer-use capability",
    "Preserve the runtime confirmation policy",
    "return `status: blocked`",
):
    if clause not in computer:
        failures.append(f"computer-use: missing capability clause: {clause}")

assert not failures, "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "setup composes existing mechanics and degrades cleanly without Shelby" {
  run python3 - "$SKILLS_ROOT" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1]) / "setup" / "SKILL.md"
assert path.is_file(), "missing Harness skill: setup"
text = path.read_text()
normalized = " ".join(text.split())

required = (
    "Invoke `harness:sync`",
    "Invoke `harness:model-rubric`",
    "discover runtime capabilities with `command -v`",
    "reconcile the rubric's `capabilities` with the observed inventory",
    "Invoke `harness:sync` again if the rubric changed inside the agents repository",
    "version-controlled",
    "local-only",
    "Return the exact `HarnessResult`",
    "For Setup, use `route.requested: default`",
    "Only the parent or accepting workflow may return `status: accepted`",
)
missing = [clause for clause in required if clause not in normalized]
assert not missing, "setup contract missing: " + ", ".join(missing)
assert "$harness/scripts/" not in text, "setup duplicates script mechanics instead of composing skills"

def apply_fixture(tool_names):
    shelby_available = any("shelby" in name.lower() for name in tool_names)
    if shelby_available:
        assert "When Shelby tool names are present, continue setup and return only identifiers from successful Shelby calls" in normalized
        return "finished", ("project-id", "run-id", ["checkpoint-id"])
    assert "When Shelby tool names are absent, continue setup and leave all optional `shelby` identifiers empty" in normalized
    return "finished", (None, None, [])

present = apply_fixture(["mcp__shelby_memory__get_brief", "mcp__shelby_memory__log_run"])
absent = apply_fixture(["read", "bash", "edit"])
assert present[0] == absent[0] == "finished"
assert all(present[1])
assert absent[1] == (None, None, [])
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "Codex remains an internal Harness adapter with no public PM vendor skills" {
  [ ! -e "$REPO/plugins/pm/skills/codex-implementation" ]
  [ ! -e "$REPO/plugins/pm/skills/codex-review" ]
  [ ! -e "$REPO/plugins/pm/skills/codex-computer-use" ]

  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
hits = []
for path in (root / "plugins").glob("*/skills/*/SKILL.md"):
    if path.is_relative_to(root / "plugins" / "harness"):
        continue
    text = path.read_text()
    for needle in ("codex exec", "codex review", "pm:codex-", "/pm:codex-"):
        if needle in text:
            hits.append(f"{path.relative_to(root)}: {needle}")
assert not hits, "Codex adapter leaked outside Harness:\n" + "\n".join(hits)

seed = (root / "plugins/harness/skills/model-rubric/Default_Rubric.yml").read_text()
assert "pm:codex" not in seed, "the Harness seed still advertises removed public PM Codex skills"
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}
