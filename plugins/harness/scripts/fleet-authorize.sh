#!/usr/bin/env bash
# Rewrite the Harness fleet block in ~/.ssh/authorized_keys from <repo>/ssh/keys/*.pub.
#
#   fleet-authorize.sh [repo] [authorized_keys]
#
# A key removed from the repo leaves the block on the next run, so revocation
# propagates the same way enrollment does. Outside the block, only plain copies of a
# fleet key (current or just revoked, e.g. from an ssh-copy-id bootstrap) are
# dropped, so a stray duplicate cannot outlive revocation; a copy with options
# aborts instead, since dropping it would change what that key may do. Every key file must hold exactly one plain public key: a
# line with authorized_keys options (command=, from=, ...) is rejected rather
# than copied, and any rejection leaves authorized_keys unchanged.
set -euo pipefail

repo="${1:-${AGENTS_REPO:-$HOME/.agents}}"
target="${2:-$HOME/.ssh/authorized_keys}"
keys="$repo/ssh/keys"
start='# harness:fleet start — managed by fleet-authorize.sh; edits inside are overwritten'
end='# harness:fleet end'

[ -d "$keys" ] || { echo "no key directory: $keys" >&2; exit 2; }

plain_key='^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com) [A-Za-z0-9+/=]+( [^[:cntrl:]]*)?$'
block=""
blobs=""
count=0
for f in "$keys"/*.pub; do
  [ -e "$f" ] || continue
  if [ -L "$f" ] || [ "$(grep -c '' "$f")" -ne 1 ]; then
    echo "rejected $f: expected a regular file with exactly one line" >&2; exit 1
  fi
  line="$(cat "$f")"
  if ! [[ "$line" =~ $plain_key ]]; then
    echo "rejected $f: not a plain public key line" >&2; exit 1
  fi
  block+="$line"$'\n'
  blobs+="$(printf '%s' "$line" | awk '{print $2}') "
  count=$((count + 1))
done

dir="$(dirname "$target")"
# The rename below would replace a symlink with a regular file and silently detach
# whatever manages the link.
[ ! -L "$target" ] || { echo "refusing symlinked $target; fix by hand" >&2; exit 1; }
[ ! -e "$target" ] || [ -f "$target" ] || { echo "refusing non-regular $target" >&2; exit 1; }
mkdir -p "$dir" && chmod 700 "$dir"
touch "$target"

tmp="$(mktemp "$dir/.authorized_keys.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
# Drop at most one well-formed block. Anything else that looks like a marker — out
# of order, repeated, unterminated, or edited in any case — aborts before the
# rename, because guessing would either delete keys this script does not own or
# keep revoked ones. Markers match with surrounding whitespace and a CRLF ending
# trimmed. Pass 1 validates markers and learns the old block's keys; pass 2 writes.
if ! awk -v s="$start" -v e="$end" -v cur="$blobs" '
  BEGIN { n = split(cur, c, " "); for (i = 1; i <= n; i++) fleet[c[i]] = 1 }
  { l = $0; sub(/^[ \t]+/, "", l); sub(/[ \t\r]+$/, "", l) }
  NR == FNR {
    if (l == s) { if (seen) bad = 1; seen = inblock = 1; next }
    if (l == e) { if (!inblock) bad = 1; inblock = 0; next }
    if (index(tolower(l), "harness:fleet")) bad = 1
    if (inblock) { split(l, f, /[ \t]+/); if (f[2] != "") fleet[f[2]] = 1 }
    next
  }
  FNR == 1 && (bad || inblock) { exit }
  l == s { skip = 1; next }
  l == e { skip = 0; next }
  skip { next }
  {
    m = split(l, f, /[ \t]+/)
    for (i = 1; i <= m; i++)
      if (f[i] in fleet) { if (i == 2 && f[1] ~ /^(ssh-|ecdsa-|sk-)/) next; opt = 1 }
    print
  }
  END { exit (bad || inblock || opt) }
' "$target" "$target" > "$tmp"; then
  echo "malformed harness:fleet markers, or a fleet key with options outside the block, in $target; fix by hand" >&2; exit 1
fi
if [ "$count" -gt 0 ]; then
  printf '%s\n%s%s\n' "$start" "$block" "$end" >> "$tmp"
fi
chmod 600 "$tmp"
mv "$tmp" "$target"
trap - EXIT
echo "authorized $count fleet key(s) in $target"
