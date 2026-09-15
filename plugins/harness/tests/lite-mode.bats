#!/usr/bin/env bats

setup() { REPO="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; }

@test "risk gate is mechanical and defaults ordinary work to direct execution" {
  run python3 - "$REPO/plugins/harness/skills/risk-gate/SKILL.md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
assert path.is_file(), f"missing risk gate: {path}"
text = " ".join(path.read_text().split()).lower()

required = (
    "direct",
    "structured",
    "independent review",
    "authentication",
    "payment",
    "persisted data",
    "public api",
    "multiple repositories",
    "testing seam",
    "context window",
    "explicitly requests",
    "max_children",
    "max_depth",
    "token_budget",
    "one independently useful substantial track",
)
missing = [phrase for phrase in required if phrase not in text]
assert not missing, "risk gate omits Lite rule: " + ", ".join(missing)

forbidden = ("estimate complexity from vibes", "always delegate", "always review")
found = [phrase for phrase in forbidden if phrase in text]
assert not found, "risk gate contains non-mechanical policy: " + ", ".join(found)
PY
  [ "$status" -eq 0 ]
}

@test "managed PM workflows keep delegation and independent review conditional" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

repo = Path(sys.argv[1])
dev = " ".join((repo / "plugins/pm/skills/dev-task/SKILL.md").read_text().split()).lower()
sprint = " ".join((repo / "plugins/pm/skills/sprint-dev/SKILL.md").read_text().split()).lower()

for phrase in (
    "manual only",
    "current agent implements by default",
    "harness:risk-gate",
    "delegate only",
    "independent review",
    "one verification pass",
):
    assert phrase in dev, f"dev-task omits {phrase}"

for phrase in (
    "harness:risk-gate",
    "current agent implements by default",
    "delegate only",
    "independent review",
    "one verification pass",
):
    assert phrase in sprint, f"sprint-dev omits {phrase}"

for text, label in ((dev, "dev-task"), (sprint, "sprint-dev")):
    assert "always uses harness:execute" not in text, f"{label} forces delegation"
    assert "each harness execution request requires self-review and the full test suite" not in text, f"{label} duplicates verification"
    assert "superpowers:" not in text, f"{label} auto-loads Superpowers"
PY
  [ "$status" -eq 0 ]
}

@test "execute loads branch references progressively and keeps full results internal" {
  run python3 - "$REPO/plugins/harness/skills/execute/SKILL.md" <<'PY'
from pathlib import Path
import sys

text = " ".join(Path(sys.argv[1]).read_text().split())
for phrase in (
    "The consumer decides direct versus delegated execution before invoking this skill",
    "Read [references/context.md](../../references/context.md) only when",
    "Read [references/shelby-integration.md](../../references/shelby-integration.md) only when",
    "Keep the complete HarnessResult in the workflow state",
    "render a concise user update",
    "Populate `HARNESS_ACTIVE_CANDIDATE` from the host's declared runtime identity",
):
    assert phrase in text, f"execute omits Lite boundary: {phrase}"
PY
  [ "$status" -eq 0 ]
}

@test "PM planning uses Superpowers only when explicitly selected" {
  run python3 - "$REPO/plugins/pm/references/triage-spec-flow.md" <<'PY'
from pathlib import Path
import sys

text = " ".join(Path(sys.argv[1]).read_text().split())
for phrase in (
    "When the user explicitly requests Superpowers planning",
    "Otherwise, plan directly",
    "Do not require Superpowers",
):
    assert phrase in text, f"triage planning omits optional boundary: {phrase}"
PY
  [ "$status" -eq 0 ]
}

@test "managed PM workflows are explicit-only for OpenAI runtimes" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys
import yaml

repo = Path(sys.argv[1])
for name in ("dev-task", "sprint-dev"):
    path = repo / "plugins/pm/skills" / name / "agents/openai.yaml"
    assert path.is_file(), f"{name} omits OpenAI invocation policy"
    data = yaml.safe_load(path.read_text())
    assert data == {"policy": {"allow_implicit_invocation": False}}, data
PY
  [ "$status" -eq 0 ]
}

@test "house rules scale proof and review from risk instead of change size" {
  run python3 - "$REPO/plugins/harness/references/house-rules.md" <<'PY'
from pathlib import Path
import sys

text = " ".join(Path(sys.argv[1]).read_text().split()).lower()
for phrase in (
    "ordinary changes stay with the current agent",
    "one verification pass",
    "highest stable existing testing seam",
    "use the risk gate",
    "independent review only when",
):
    assert phrase in text, f"house rules omit {phrase}"

for phrase in (
    "the full suite before the commit, one reviewer",
    "brainstorm → plan → guided implementation → review, every gate",
):
    assert phrase not in text, f"house rules retain heavyweight default: {phrase}"
PY
  [ "$status" -eq 0 ]
}

@test "self-review requires observed contract coverage including state transitions" {
  run python3 - "$REPO/plugins/harness/skills/risk-gate/SKILL.md" <<'PY'
from pathlib import Path
import sys

text = " ".join(Path(sys.argv[1]).read_text().split()).lower()
for phrase in (
    "map each changed public contract to a named assertion and its observed result",
    "each required transition (both directions for reversible states)",
    "every affected control",
    "accessibility state",
    "planned tests and a green suite alone do not establish complete coverage",
    "revisit the review decision after verification",
    "missing or indirect assertions remain coverage gaps",
):
    assert phrase in text, f"coverage evidence rule missing: {phrase}"
PY
  [ "$status" -eq 0 ]
}

@test "verification selection avoids unavailable optional checklist tools" {
  run python3 - "$REPO/plugins/harness/references/house-rules.md" "$REPO/plugins/harness/templates/AGENTS_Baseline.md" <<'PY'
from pathlib import Path
import sys
for source in sys.argv[1:]:
    text = " ".join(Path(source).read_text().split()).lower()
    for phrase in (
        "select checks from repository instructions, configured scripts, and the changed behavior",
        "do not add a generic build/format/lint checklist",
        "confirm availability before scheduling",
        "report an unavailable required check as an unmet gate",
        "run the remaining independent checks",
        "do not install optional tooling solely to complete a checklist",
    ):
        assert phrase in text, f"{source}: verification selection rule missing: {phrase}"
PY
  [ "$status" -eq 0 ]
}
