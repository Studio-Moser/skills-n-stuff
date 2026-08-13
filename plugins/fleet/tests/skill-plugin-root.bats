#!/usr/bin/env bats
#
# Guard: no skill body may call a plugin script through $CLAUDE_PLUGIN_ROOT.
#
# Claude Code expands $CLAUDE_PLUGIN_ROOT for a skill's load-time `!`…``
# substitution, but does not export it into the environment the agent's Bash
# tool runs in. A ```bash block running "$CLAUDE_PLUGIN_ROOT/scripts/foo.sh"
# therefore fails with "no such file or directory" — every script invocation
# in fleet:sync and fleet:model-rubric was broken this way, and it only
# surfaced on a real run.
#
# Each block must resolve the root itself, the same way it re-resolves repo=
# and claude= (nothing persists between blocks):
#
#   fleet="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/fleet/*/ \
#     2>/dev/null | sort -V | tail -1)}"; fleet="${fleet%/}"
#
# which honours the variable when it is set and falls back to the newest
# installed copy when it is not.

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
}

@test "no skill body invokes a plugin script via \$CLAUDE_PLUGIN_ROOT" {
  # Repo-wide. Was fleet-scoped when first written because pm and generate
  # carried the same defect; both were fixed, so this now guards everything.
  #
  # Load-time `!`…`` substitution is expanded by Claude Code before the agent
  # sees it and is unaffected — pm relies on that form in four skills and it
  # must keep working. Only bash the agent executes itself is checked.
  run python3 - "$REPO" <<'PY'
import glob, os, re, sys

repo = sys.argv[1]
bad = []
for path in sorted(glob.glob(os.path.join(repo, "plugins/*/skills/*/SKILL.md"))):
    src = open(path).read()
    rel = os.path.relpath(path, repo)
    for block in re.findall(r"```bash\n(.*?)\n```", src, re.S):
        for line in block.split("\n"):
            if line.lstrip().startswith("#"):
                continue
            # Using it as a path prefix is the bug: "$CLAUDE_PLUGIN_ROOT/scripts/…".
            # Reading it with a fallback is the *fix* and must not be flagged:
            #   fleet="${CLAUDE_PLUGIN_ROOT:-$(…)}"
            # `!`…`` load-time substitution is expanded by Claude Code before the
            # agent ever sees it, so it is fine too — this only covers bash the
            # agent executes itself.
            if re.search(r'\$\{?CLAUDE_PLUGIN_ROOT\}?/', line):
                bad.append((rel, line.strip()))

for rel, line in bad:
    print(f"{rel}: {line}")
    print("    ^ $CLAUDE_PLUGIN_ROOT is unset in the Bash tool; resolve the root in-block")
print(f"offenders={len(bad)}")
sys.exit(1 if bad else 0)
PY
  [ "$status" -eq 0 ] || return 1
  [ -n "$output" ]
}

@test "every fleet skill block calling a plugin script resolves the root first" {
  run python3 - "$REPO" <<'PY'
import glob, os, re, sys

repo = sys.argv[1]
bad = []
checked = 0
for path in sorted(glob.glob(os.path.join(repo, "plugins/fleet/skills/*/SKILL.md"))):
    rel = os.path.relpath(path, repo)
    for block in re.findall(r"```bash\n(.*?)\n```", open(path).read(), re.S):
        if '"$fleet/scripts/' not in block:
            continue
        checked += 1
        if 'fleet="${CLAUDE_PLUGIN_ROOT' not in block:
            first = next((l for l in block.split("\n") if '"$fleet/scripts/' in l), "")
            bad.append((rel, first.strip()))

for rel, line in bad:
    print(f"{rel}: {line}")
    print("    ^ block uses $fleet without resolving it; nothing persists between blocks")
print(f"checked={checked} offenders={len(bad)}")
sys.exit(1 if bad else 0)
PY
  [ "$status" -eq 0 ] || return 1
  [ -n "$output" ]
}
