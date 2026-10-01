#!/usr/bin/env bash
# Structural checks for the design plugin: every skill's frontmatter name
# matches its folder, every relative path a skill or template mentions exists,
# and the capture script parses.
set -euo pipefail

plugin_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
fail=0

for skill in "$plugin_root"/skills/*/; do
  name="$(basename "$skill")"
  declared="$(sed -nE '1,/^---$/!d; s/^name:[[:space:]]*//p' "$skill/SKILL.md" | head -1)"
  if [ "$declared" != "$name" ]; then
    echo "FAIL $name: frontmatter name '$declared' != folder" >&2
    fail=1
  fi
  # Relative links inside backticks: references/…, ../../templates/…, scripts/…
  while IFS= read -r rel; do
    if [ ! -e "$skill/$rel" ]; then
      echo "FAIL $name: referenced path missing: $rel" >&2
      fail=1
    fi
  done < <(grep -oE '`(\.\./\.\./templates|references|scripts)/[^`]+`' "$skill/SKILL.md" | tr -d '`' | sort -u)
done

for t in "Direction Brief.md" "Round Sheet.md" "Variant Build Brief.md" "Copy Direction.md" "Frozen Brief.md"; do
  [ -f "$plugin_root/templates/$t" ] || { echo "FAIL template missing: $t" >&2; fail=1; }
done

node --check "$plugin_root/skills/capture/scripts/capture.mjs" || fail=1
node --check "$plugin_root/skills/capture/scripts/views.mjs" || fail=1
node --check "$plugin_root/skills/capture/scripts/freeze.mjs" || fail=1

# check-brief.mjs: a filled direction passes; the bare templates do not.
check="$plugin_root/skills/direction-brief/scripts/check-brief.mjs"
fixtures="$plugin_root/tests/fixtures"
node "$check" "$fixtures/01 Ledger" --copy "$fixtures/Copy 01 Proof First.md" >/dev/null || { echo "FAIL check-brief: filled fixture rejected" >&2; fail=1; }
blank="$(mktemp -d)"
cp "$plugin_root/templates/Direction Brief.md" "$blank/Brief.md"
if node "$check" "$blank" --copy "$plugin_root/templates/Copy Direction.md" 2>/dev/null; then
  echo "FAIL check-brief: unfilled templates accepted" >&2; fail=1
fi
rm -rf "$blank"

# gallery.mjs: serves the fixture directions, and nothing outside them.
node --check "$plugin_root/skills/gallery/scripts/gallery.mjs" || fail=1
node --check "$plugin_root/skills/gallery/scripts/frames.mjs" || fail=1
node --check "$plugin_root/skills/gallery/scripts/import-build.mjs" || fail=1
port=$((20000 + RANDOM % 20000))
(cd "$plugin_root" && exec node skills/gallery/scripts/gallery.mjs --dir tests/fixtures --port "$port" --project Acme) >/dev/null 2>&1 &
gallery_pid=$!
trap 'kill "$gallery_pid" 2>/dev/null || true' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -fs -o /dev/null "http://127.0.0.1:$port/" && break; sleep 0.3; done
expect() { # expect <path> <status> [text the body must contain]
  body="$(curl -s -w '\n%{http_code}' "http://127.0.0.1:$port$1")"
  status="${body##*$'\n'}"
  if [ "$status" != "$2" ]; then echo "FAIL gallery: $1 returned $status, expected $2" >&2; fail=1; fi
  if [ -n "${3:-}" ] && ! printf '%s' "$body" | grep -qF -- "$3"; then echo "FAIL gallery: $1 lacks \"$3\"" >&2; fail=1; fi
}
expect "/" 200 "Ledger"
expect "/direction/01%20Ledger" 200 "Entries First"
expect "/direction/01%20Ledger" 200 "--accent"
expect "/direction/01%20Ledger" 200 "02 Ledger Page"
expect "/tests/fixtures/01%20Ledger/Homepage%20A%20-%20Entries%20First.html" 200 "forty launches"
expect "/thumb/tests/fixtures/01%20Ledger/Homepage%20A%20-%20Entries%20First.html" 200 "<base href="
expect "/doc/tests/fixtures/Copy%2001%20Proof%20First.md" 200 "The bet"
expect "/edit/tests/fixtures/01%20Ledger/Homepage%20A%20-%20Entries%20First.html" 409 "has no DESIGN.md yet"
# A static build is mounted under /build/<folder>/ and its own root-absolute
# references are prefixed; a path that is not part of the build is left alone.
expect "/build/01%20Ledger/v/a/" 200 'href="/build/01%20Ledger/assets/site.css"'
expect "/build/01%20Ledger/v/a/" 200 '/build/01%20Ledger/assets/mark.svg 2x'
expect "/build/01%20Ledger/v/a/" 200 'var p="/build/01%20Ledger/assets/"'
expect "/build/01%20Ledger/v/a/" 200 'href="/elsewhere/"'
expect "/build/01%20Ledger/assets/site.css" 200 "url(/build/01%20Ledger/assets/mark.svg)"
expect "/build/01%20Ledger/..%2F..%2FBrief.md" 404
# Editing is offered only to a browser on this machine.
expect "/direction/01%20Ledger" 200 'href="/edit/'
if curl -s -H "Host: gallery.example.ts.net" "http://127.0.0.1:$port/direction/01%20Ledger" | grep -qF 'href="/edit/'; then echo "FAIL gallery: edit offered to another host" >&2; fail=1; fi
[ "$(curl -s -o /dev/null -w '%{http_code}' -H "Host: gallery.example.ts.net" "http://127.0.0.1:$port/edit/tests/fixtures/01%20Ledger/Homepage%20A%20-%20Entries%20First.html")" = 403 ] || { echo "FAIL gallery: edit route open to another host" >&2; fail=1; }
expect "/api/directions.json" 200 '"preview":"/tests/fixtures/01%20Ledger/Homepage%20A%20-%20Entries%20First.html"'
expect "/.claude-plugin/plugin.json" 404
expect "/skills/gallery/SKILL.md" 404
expect "/tests/fixtures/..%2F..%2FREADME.md" 404
kill "$gallery_pid" 2>/dev/null; wait "$gallery_pid" 2>/dev/null || true

python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$plugin_root/.claude-plugin/plugin.json" || fail=1

[ "$fail" -eq 0 ] && echo "design plugin: all checks passed"
exit "$fail"
