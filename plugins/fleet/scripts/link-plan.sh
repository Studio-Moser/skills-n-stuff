#!/usr/bin/env bash
# Report how this machine's ~/.claude compares to a personal agent repo.
# READ-ONLY. Creates nothing, removes nothing — fleet:sync acts on this output.
set -euo pipefail

repo="${1:-$HOME/.agents}"
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

  if [ ! -e "$want" ]; then
    state="MISSING-IN-REPO"
  elif [ -L "$link" ]; then
    got="$(readlink "$link")"
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
