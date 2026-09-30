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

for t in "Direction Brief.md" "Round Sheet.md" "Variant Build Brief.md"; do
  [ -f "$plugin_root/templates/$t" ] || { echo "FAIL template missing: $t" >&2; fail=1; }
done

node --check "$plugin_root/skills/capture/scripts/capture.mjs" || fail=1
node --check "$plugin_root/skills/capture/scripts/views.mjs" || fail=1

python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$plugin_root/.claude-plugin/plugin.json" || fail=1

[ "$fail" -eq 0 ] && echo "design plugin: all checks passed"
exit "$fail"
