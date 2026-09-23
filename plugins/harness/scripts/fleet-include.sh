#!/usr/bin/env bash
# Make ~/.ssh/config include the fleet inventory globally.
#
#   fleet-include.sh [repo] [ssh_config]
#
# OpenSSH applies an Include that follows a Host or Match line only to that block,
# so the line counts as present only when it appears before the first one;
# otherwise it is prepended. A symlinked config exits 1 untouched, because the
# atomic rename would replace the link with a regular file.
set -euo pipefail

repo="${1:-${AGENTS_REPO:-$HOME/.agents}}"
config="${2:-$HOME/.ssh/config}"
path="$repo/ssh/config"

[ ! -L "$config" ] || { echo "refusing symlinked $config; add 'Include \"$path\"' at the top of its target" >&2; exit 1; }
[ ! -e "$config" ] || [ -f "$config" ] || { echo "refusing non-regular $config" >&2; exit 1; }
# The path is written as one double-quoted OpenSSH argument; a quote, backslash, or
# control character would split or corrupt it.
case "$path" in *[\"\\]* | *[[:cntrl:]]*) echo "unsupported characters in $path" >&2; exit 1 ;; esac
dir="$(dirname "$config")"
mkdir -p "$dir" && chmod 700 "$dir"

if [ -f "$config" ] && awk -v p="$path" '
  { l = $0; sub(/\r$/, "", l); sub(/^[ \t]+/, "", l); k = tolower(l) }
  k ~ /^(host|match)([ \t]*=|[ \t]|$)/ { exit }
  k ~ /^include([ \t]*=|[ \t])/ {
    sub(/^[^ \t=]+[ \t]*=?[ \t]*/, "", l); sub(/[ \t]+$/, "", l)
    if (l == "\"" p "\"" || (l == p && p !~ /[ \t]/)) { found = 1; exit }
  }
  END { exit !found }
' "$config"; then
  echo "already included in $config"; exit 0
fi

tmp="$(mktemp "$dir/.config.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
{ printf 'Include "%s"\n\n' "$path"; [ ! -f "$config" ] || cat "$config"; } > "$tmp"
chmod 600 "$tmp"
mv "$tmp" "$config"
trap - EXIT
echo "included $path in $config"
