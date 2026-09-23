#!/usr/bin/env bash
# Rewrite the Harness fleet block in ~/.ssh/authorized_keys from <repo>/ssh/keys/*.pub.
#
#   fleet-authorize.sh [repo] [authorized_keys]
#
# Lines outside the marked block are never touched. A key removed from the repo
# leaves the block on the next run, so revocation propagates the same way
# enrollment does. Every key file must hold exactly one plain public key: a
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
  count=$((count + 1))
done

dir="$(dirname "$target")"
# The rename below would replace a symlink with a regular file and silently detach
# whatever manages the link.
[ ! -L "$target" ] || { echo "refusing symlinked $target; fix by hand" >&2; exit 1; }
mkdir -p "$dir" && chmod 700 "$dir"
touch "$target"

tmp="$(mktemp "$dir/.authorized_keys.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
# Drop at most one well-formed block. Anything else that looks like a marker — out
# of order, repeated, unterminated, or edited — aborts before the rename, because
# guessing would either delete keys this script does not own or keep revoked ones.
# Markers match with a trailing CR stripped so a CRLF file is still recognized.
if ! awk -v s="$start" -v e="$end" '
  { l = $0; sub(/\r$/, "", l) }
  l == s { if (seen) bad = 1; seen = skip = 1; next }
  l == e { if (!skip) bad = 1; skip = 0; next }
  index(l, "# harness:fleet") == 1 { bad = 1 }
  !skip
  END { exit (bad || skip) }
' "$target" > "$tmp"; then
  echo "malformed harness:fleet markers in $target; fix by hand" >&2; exit 1
fi
if [ "$count" -gt 0 ]; then
  printf '%s\n%s%s\n' "$start" "$block" "$end" >> "$tmp"
fi
chmod 600 "$tmp"
mv "$tmp" "$target"
trap - EXIT
echo "authorized $count fleet key(s) in $target"
