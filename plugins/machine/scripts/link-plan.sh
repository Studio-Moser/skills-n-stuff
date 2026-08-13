#!/usr/bin/env bash
# Report how this machine's ~/.claude compares to a personal agent repo.
# READ-ONLY. Creates nothing, removes nothing — machine:sync acts on this output.
set -euo pipefail

repo="${1:-$HOME/.agents}"
repo="${repo%/}"
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# "<name under ~/.claude>|<path under repo>"
entries="skills|skills
CLAUDE.md|claude/CLAUDE.md
settings.json|claude/settings.json
statusline-command.sh|claude/statusline-command.sh
mcp.json|claude/mcp.json"

# Resolve $1 to an absolute, symlink-free path, following relative and
# chained symlink targets by hand (portable to bash 3.2 / macOS, no
# readlink -f dependency). Prints nothing and returns non-zero if it can't
# be resolved (dangling target, missing directory) — callers must treat
# that as "not a match", never as ok.
resolve_path() {
  p="$1"
  hops=0
  while [ -L "$p" ]; do
    hops=$((hops + 1))
    [ "$hops" -gt 40 ] && return 1
    t="$(readlink "$p")" || return 1
    case "$t" in
      /*) p="$t" ;;
      *) p="$(dirname "$p")/$t" ;;
    esac
  done
  d="$(dirname "$p")"
  [ -d "$d" ] || return 1
  d="$(cd "$d" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s\n' "$d" "$(basename "$p")"
}

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
    # Compare resolved paths, not raw strings, so a correct symlink with a
    # relative target (e.g. `ln -s ../.agents/claude/CLAUDE.md`) is reported
    # ok. A dangling target or anything else that fails to resolve falls
    # through to RELINK rather than a false ok — resolve_path returning
    # empty never counts as a match.
    resolved_got="$(resolve_path "$link" 2>/dev/null || true)"
    resolved_want="$(resolve_path "$want" 2>/dev/null || true)"
    if [ -n "$resolved_got" ] && [ "$resolved_got" = "$resolved_want" ]; then
      state="ok"
    else
      state="RELINK(->$got)"
    fi
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
