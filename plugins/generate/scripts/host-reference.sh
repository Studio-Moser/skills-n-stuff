#!/usr/bin/env bash
# Upload a local file to litterbox (catbox's ephemeral tier) so Kie models can
# fetch it as a reference URL. Prints the URL.
#
# ponytail: litterbox because it expires on its own — no bucket, no credentials,
# no cleanup job. Swap for a real bucket only if references need to outlive the
# session, or if the assets can't be publicly reachable even briefly.
#
#   host-reference.sh FILE [--ttl 1h|12h|24h|72h]
#   host-reference.sh --self-check
set -euo pipefail

API=${LITTERBOX_API:-https://litterbox.catbox.moe/resources/internals/api.php}

# Litterbox answers failures with plain text ("File too large", an error page, or
# nothing) at HTTP 200. Feeding that string to a model as a reference URL burns a
# paid generation on a request that was never going to work, so reject it here.
validate_url() {
  case "${1:-}" in
    https://*) printf '%s\n' "$1" ;;
    *) echo "upload failed: ${1:-empty response}" >&2; return 1 ;;
  esac
}

self_check() {
  validate_url "https://files.catbox.moe/ab12cd.png" >/dev/null \
    || { echo "FAIL: rejected a valid URL" >&2; exit 1; }
  if validate_url "File too large" >/dev/null 2>&1; then
    echo "FAIL: accepted an error string as a URL" >&2; exit 1
  fi
  if validate_url "" >/dev/null 2>&1; then
    echo "FAIL: accepted an empty response as a URL" >&2; exit 1
  fi
  echo "self-check OK"
}

[ "${1:-}" = "--self-check" ] && { self_check; exit 0; }

file=${1:-}; ttl=1h
shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --ttl) ttl=$2; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$file" ]; then
  echo "usage: host-reference.sh FILE [--ttl 1h|12h|24h|72h]" >&2
  exit 2
fi
[ -f "$file" ] || { echo "no such file: $file" >&2; exit 2; }

case "$ttl" in 1h|12h|24h|72h) ;; *) echo "ttl must be 1h, 12h, 24h, or 72h" >&2; exit 2 ;; esac

response=$(curl -sf -F "reqtype=fileupload" -F "time=$ttl" -F "fileToUpload=@$file" "$API")
validate_url "$response"
