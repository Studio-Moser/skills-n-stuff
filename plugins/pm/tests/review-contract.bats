#!/usr/bin/env bats

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SCRIPT="$REPO/plugins/pm/scripts/stamp-review-contract.sh"
  TMPROOT="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPROOT"
}

@test "review contract creates managed baseline and editable project sections" {
  run "$SCRIPT" "$TMPROOT"
  [ "$status" -eq 0 ]
  run grep -cF '<!-- pm:review-baseline:start -->' "$TMPROOT/REVIEW.md"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
  grep -qF '## Project failure modes' "$TMPROOT/REVIEW.md"
  grep -qF 'No findings' "$TMPROOT/REVIEW.md"
}

@test "review contract refresh preserves project-owned content" {
  "$SCRIPT" "$TMPROOT"
  printf '\nProject-owned sentinel.\n' >> "$TMPROOT/REVIEW.md"
  run "$SCRIPT" "$TMPROOT"
  [ "$status" -eq 0 ]
  [ "$(grep -cF '<!-- pm:review-baseline:start -->' "$TMPROOT/REVIEW.md")" -eq 1 ]
  [ "$(grep -cF 'Project-owned sentinel.' "$TMPROOT/REVIEW.md")" -eq 1 ]
}

@test "review contract adopts an existing file without overwriting it" {
  printf '# Existing review policy\n\nKeep me.\n' > "$TMPROOT/REVIEW.md"
  run "$SCRIPT" "$TMPROOT"
  [ "$status" -eq 0 ]
  grep -qF 'Keep me.' "$TMPROOT/REVIEW.md"
  grep -qF '<!-- pm:review-baseline:start -->' "$TMPROOT/REVIEW.md"
}

@test "review contract refuses symlink targets and malformed markers" {
  outside="$TMPROOT-outside"
  printf 'outside\n' > "$outside"
  ln -s "$outside" "$TMPROOT/REVIEW.md"
  run "$SCRIPT" "$TMPROOT"
  [ "$status" -eq 2 ]
  [ "$(cat "$outside")" = outside ]

  rm "$TMPROOT/REVIEW.md"
  printf '<!-- pm:review-baseline:start -->\nbroken\n' > "$TMPROOT/REVIEW.md"
  run "$SCRIPT" "$TMPROOT"
  [ "$status" -eq 2 ]
  grep -qF broken "$TMPROOT/REVIEW.md"

  printf '<!-- pm:review-baseline:end -->\nbroken\n<!-- pm:review-baseline:start -->\n' > "$TMPROOT/REVIEW.md"
  run "$SCRIPT" "$TMPROOT"
  [ "$status" -eq 2 ]

  printf '<!-- pm:review-baseline:start -->\none\n<!-- pm:review-baseline:end -->\n<!-- pm:review-baseline:start -->\ntwo\n<!-- pm:review-baseline:end -->\n' > "$TMPROOT/REVIEW.md"
  run "$SCRIPT" "$TMPROOT"
  [ "$status" -eq 2 ]
}

@test "review contract refuses CRLF without altering project-owned text" {
  printf '# Existing policy\r\n\r\nKeep me.\r\n' > "$TMPROOT/REVIEW.md"
  cp "$TMPROOT/REVIEW.md" "$TMPROOT/original"
  run "$SCRIPT" "$TMPROOT"
  [ "$status" -eq 2 ]
  case "$output" in
    *"normalize it to LF"*) ;;
    *) return 1 ;;
  esac
  cmp "$TMPROOT/original" "$TMPROOT/REVIEW.md"
}

@test "PM setup installs review policy and guards GitHub enforcement" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

repo = Path(sys.argv[1])
pm = repo / "plugins/pm"
setup = (pm / "skills/setup/SKILL.md").read_text()
reference = (pm / "references/setup-review-system.md").read_text()
readme = (pm / "README.md").read_text()
pr_template = (pm / "templates/pull-request-template.md").read_text()
workflow = (pm / "templates/github-verification-workflow.yml").read_text()
failures = []

for path in (
    pm / "templates/review-baseline.md",
    pm / "templates/review-project.md",
    pm / "templates/pull-request-template.md",
    pm / "templates/github-verification-workflow.yml",
    pm / "scripts/stamp-review-contract.sh",
):
    if not path.is_file():
        failures.append(f"missing {path.relative_to(repo)}")

for needle in (
    "references/setup-review-system.md",
    "every configured repository",
    "managed `REVIEW.md` contract",
    "explicit approval",
    "keep_existing_pm: true",
    "skip Phases 2–7",
    "Keeping PM configuration is not an early exit",
):
    if needle not in setup:
        failures.append(f"setup omits {needle}")

for needle in (
    "issue tracker does not determine the code host",
    "positive acceptance signal",
    "Never insert a placeholder owner",
    "PM_SETUP_VERIFICATION_STEPS",
    "PM verification",
    "combined preview",
    "explicit approval",
    "PM merge requirements",
    "strict mode enabled",
    "never edit an unrelated ruleset",
    "Do not claim the check is operational",
):
    if needle.lower() not in reference.lower():
        failures.append(f"review setup omits {needle}")

if "REVIEW.md" not in readme or "cannot weaken PM or Harness" not in readme:
    failures.append("README omits project review-contract precedence")
for heading in ("## What", "## Why", "## Testing", "## Risk / Blast Radius", "## How to revert"):
    if heading not in pr_template:
        failures.append(f"PR template omits {heading}")
for needle in ("pull_request:", "merge_group:", "contents: read", "name: PM verification", "PM_SETUP_RUNNER", "PM_SETUP_VERIFICATION_STEPS"):
    if needle not in workflow:
        failures.append(f"verification workflow template omits {needle}")

assert not failures, "; ".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    echo "$output"
  fi
  [ "$status" -eq 0 ]
}

@test "review consumers use additive project policy and evidence-based convergence" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

repo = Path(sys.argv[1])
pm = repo / "plugins/pm"
reference = (pm / "references/review-proof.md").read_text()
loop = (pm / "references/sprint-review-loop.md").read_text()
consumers = [
    (pm / "agents/code-reviewer.md").read_text(),
    (pm / "skills/dev-task/SKILL.md").read_text(),
    (pm / "skills/sprint-dev/SKILL.md").read_text() + loop,
]
evaluation = (pm / "evals/PM Skill Eval.md").read_text()
failures = []

for needle in (
    "## Project review contract",
    "Record the contract oracle",
    "recompute the state and digest",
    "## Actionable findings",
    "Do not use a numerical confidence threshold",
    "## Rereview convergence",
    "suppress repeated findings",
    "all observed instances of one bug class",
    "No findings",
):
    if needle not in reference:
        failures.append(f"review proof omits {needle}")

for index, text in enumerate(consumers, start=1):
    normalized = " ".join(text.split()).lower()
    for needle in ("review.md", "additive project policy", "cannot weaken"):
        if needle not in normalized:
            failures.append(f"consumer {index} omits {needle}")

for forbidden in ("above 24", ">24", "score each finding from 0–100"):
    if forbidden.lower() in loop.lower():
        failures.append(f"sprint loop retains numerical acceptance rule: {forbidden}")

for needle in (
    "actionable blockers",
    "REVIEW_CONTRACT_STATE",
    "REVIEW_CONTRACT_DIGEST",
    "RECOMPUTED_REVIEW_CONTRACT_DIGEST",
    "previously reviewed head",
    "remediation delta",
    "suppress repeated findings",
    "one bug class",
):
    if needle.lower() not in loop.lower():
        failures.append(f"sprint loop omits {needle}")

for needle in (
    "## Review-system setup safety",
    "## Convergent rereview",
    "## Review-contract oracle changes",
    "Review System Setup Result.md",
    "Convergent Rereview Result.md",
    "Review Contract Oracle Result.md",
):
    if needle not in evaluation:
        failures.append(f"evals omit {needle}")

assert not failures, "; ".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    echo "$output"
  fi
  [ "$status" -eq 0 ]
}
