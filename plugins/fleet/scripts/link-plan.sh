#!/usr/bin/env bash
# Report how this machine's ~/.claude compares to a personal agent repo.
# READ-ONLY. Creates nothing, removes nothing — fleet:sync acts on this output.
set -euo pipefail

repo="${1:-$HOME/.agents}"
repo="${repo%/}"
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# "<name under ~/.claude>|<path under repo>"
entries="skills|skills
CLAUDE.md|claude/CLAUDE.md
settings.json|claude/settings.json
statusline-command.sh|claude/statusline-command.sh"

status=0
while IFS='|' read -r name rel; do
  [ -n "$name" ] || continue
  link="$claude/$name"
  want="$repo/$rel"

  # ponytail: MISSING-IN-REPO is checked before REAL-FILE/RELINK and masks
  # them — if the repo lacks the file AND ~/.claude has a real one, only
  # MISSING-IN-REPO prints. Deliberate: on an unadopted machine that's the
  # actionable message. Upgrade path if both facts are ever needed at once:
  # a combined state string instead of reordering the checks.
  if [ ! -e "$want" ]; then
    state="MISSING-IN-REPO"
  elif [ -L "$link" ]; then
    got="$(readlink "$link")"
    # ponytail: string comparison, not resolved-path comparison. A correct
    # symlink with a relative target (e.g. `ln -s ../.agents/claude/CLAUDE.md`)
    # reports RELINK even though it resolves to the same file. Upgrade path:
    # resolve both sides with `cd "$(dirname ...)" && pwd -P` before comparing.
    if [ "$got" = "$want" ]; then state="ok"; else state="RELINK(->$got)"; fi
  elif [ -e "$link" ]; then
    state="REAL-FILE"
  else
    state="ABSENT"
  fi

  [ "$state" = "ok" ] || status=1
  printf '%-24s -> %-32s %s\n' "$name" "$rel" "$state"
done <<EOF
$entries
EOF

exit "$status"
