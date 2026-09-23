#!/usr/bin/env bash
# Print every concrete Host alias in <repo>/ssh/config, one per line.
#
#   fleet-hosts.sh [repo]
#
# Accepts OpenSSH's case-insensitive keyword and `Host a`, `Host=a`, `Host = a`.
# Wildcard and negated patterns are not machines and are skipped. Any alias that is
# not a plain hostname token exits 1, so a caller never passes it to ssh, where a
# leading `-` would be read as an option. No alias at all also exits 1: a silent
# empty list would let a propagate or revoke run skip every machine.
set -euo pipefail

repo="${1:-${AGENTS_REPO:-$HOME/.agents}}"
config="$repo/ssh/config"
[ -f "$config" ] || { echo "no inventory: $config" >&2; exit 2; }

hosts="$(awk '
  { l = $0; sub(/\r$/, "", l); sub(/^[ \t]+/, "", l) }
  tolower(l) ~ /^host([ \t]*=|[ \t])/ {
    sub(/^[^ \t=]+[ \t]*=?[ \t]*/, "", l)
    sub(/#.*/, "", l)
    n = split(l, f, /[ \t]+/)
    for (i = 1; i <= n; i++)
      if (f[i] != "" && f[i] !~ /[*?!]/ && !(f[i] in seen)) { seen[f[i]] = 1; print f[i] }
  }
' "$config")"

[ -n "$hosts" ] || { echo "no Host aliases in $config" >&2; exit 1; }
if bad="$(printf '%s\n' "$hosts" | grep -vE '^[A-Za-z0-9][A-Za-z0-9._-]*$')"; then
  echo "invalid Host alias in $config: $bad" >&2; exit 1
fi
printf '%s\n' "$hosts"
