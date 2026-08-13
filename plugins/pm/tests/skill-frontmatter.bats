#!/usr/bin/env bats
#
# Repo-wide guard: every SKILL.md must have YAML frontmatter a strict parser
# accepts. Claude Code is lenient, so a malformed description ships unnoticed —
# but stricter consumers drop the skill silently. `npx skills` skipped
# pm:dev-task entirely for exactly this reason: an unquoted plain scalar
# containing "Do NOT use for: batching …" reads as a nested mapping.
#
# Lives in pm's suite because pm has the only bats harness in the repo; the
# check itself is repo-wide by design.

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
}

@test "every plugins/*/skills/*/SKILL.md has strictly-valid YAML frontmatter" {
  run python3 - "$REPO" <<'PY'
import glob, os, re, sys
try:
    import yaml
except ImportError:
    print("SKIP: pyyaml unavailable")
    sys.exit(0)

repo = sys.argv[1]
bad = []
checked = 0
for path in sorted(glob.glob(os.path.join(repo, "plugins/*/skills/*/SKILL.md"))):
    text = open(path).read()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    rel = os.path.relpath(path, repo)
    if not m:
        bad.append((rel, "no frontmatter block"))
        continue
    try:
        meta = yaml.safe_load(m.group(1))
    except Exception as e:
        bad.append((rel, f"{type(e).__name__}: {str(e).splitlines()[0]}"))
        continue
    if not isinstance(meta, dict) or not meta.get("name") or not meta.get("description"):
        bad.append((rel, "frontmatter missing name or description"))
        continue
    checked += 1

for rel, why in bad:
    print(f"{rel}: {why}")
print(f"checked={checked} bad={len(bad)}")
sys.exit(1 if bad else 0)
PY
  [ "$status" -eq 0 ]
}
