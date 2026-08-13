#!/usr/bin/env bash
# Fail if any tracked file carries a machine-specific absolute path.
#
# Checks BOTH file contents AND symlink targets. This is not belt-and-braces:
# grep follows a symlink and reads its target's contents, so a link pointing at
# /Users/<name>/... passes a contents-only lint silently. Found in the wild.
set -euo pipefail

repo="${1:-.}"
cd "$repo"

git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository: $repo" >&2; exit 1; }

# Move to the repo root so `git ls-files` below always covers the whole
# repo, not just the directory this script happened to be invoked from.
cd "$(git rev-parse --show-toplevel)"

fail=0

# 1. Symlink targets, read from the git index (mode 120000). Any absolute
#    target is non-portable, whatever it points at.
#    core.quotePath=false: non-ASCII names come through raw instead of
#    C-quoted, so readlink sees the real path instead of a literal '"..."'.
while IFS= read -r link; do
  [ -n "$link" ] || continue
  # A tracked symlink can be absent from the worktree (e.g. mid machine:sync);
  # readlink then fails. Don't let that abort the whole lint under set -e —
  # just skip it and keep scanning everything else.
  target="$(readlink "$link" || true)"
  case "$target" in
    /*) printf 'absolute symlink target: %s -> %s\n' "$link" "$target"; fail=1 ;;
  esac
done <<EOF
$(git -c core.quotePath=false ls-files -s | grep '^120000 ' | cut -f2-)
EOF

# 2. File contents. Skip symlinks — handled above, and grep would follow them.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -L "$f" ] && continue
  [ -f "$f" ] || continue
  if grep -nHE '/(Users|home)/[A-Za-z0-9._-]+' "$f" 2>/dev/null; then
    fail=1
  fi
done <<EOF
$(git -c core.quotePath=false ls-files)
EOF

exit "$fail"
