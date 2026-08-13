#!/usr/bin/env bash
# Download one generated asset and append its provenance to Generations.jsonl.
#
# ponytail: curl + one python json.dumps, no SDK and no database. The JSONL is
# grep-able and append-only; move to sqlite only if you ever need to query it.
#
#   save-generation.sh --url URL --dir DIR --model M --prompt P [--cost C] [--slug S]
#   save-generation.sh --self-check
#
# Prints the path it wrote.
set -euo pipefail

self_check() {
  t=$(mktemp -d)
  printf 'fake-png-bytes' > "$t/ref.png"
  out=$("$0" --url "file://$t/ref.png" --dir "$t/out" --model m1 --slug test --cost 0.05 \
    --prompt 'a "quoted" prompt
with a newline')
  [ -s "$out" ] || { echo "FAIL: asset not downloaded to $out" >&2; exit 1; }
  python3 - "$t/out/Generations.jsonl" <<'PY'
import json, sys
recs = [json.loads(line) for line in open(sys.argv[1])]
assert len(recs) == 1, recs
r = recs[0]
assert r["file"] == "001-test.png", r
assert r["model"] == "m1", r
assert r["est_cost_usd"] == 0.05, r
# the escaping this script exists to get right:
assert '"quoted"' in r["prompt"] and "\n" in r["prompt"], r
print("self-check OK")
PY
  rm -rf "$t"
}

url= dir= model= prompt= cost= slug=asset
while [ $# -gt 0 ]; do
  case "$1" in
    --self-check) self_check; exit 0 ;;
    --url)    url=$2;    shift 2 ;;
    --dir)    dir=$2;    shift 2 ;;
    --model)  model=$2;  shift 2 ;;
    --prompt) prompt=$2; shift 2 ;;
    --cost)   cost=$2;   shift 2 ;;
    --slug)   slug=$2;   shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$url" ] || [ -z "$dir" ] || [ -z "$model" ] || [ -z "$prompt" ]; then
  echo "usage: save-generation.sh --url URL --dir DIR --model M --prompt P [--cost C] [--slug S]" >&2
  exit 2
fi

mkdir -p "$dir"

ext=${url%%\?*}; ext=${ext##*.}
case "$ext" in png|jpg|jpeg|webp|gif|mp4|webm|mp3|wav) ;; *) ext=bin ;; esac

n=$(find "$dir" -maxdepth 1 -type f ! -name '*.jsonl' | wc -l | tr -d ' ')
name=$(printf '%03d-%s.%s' "$((n + 1))" "$slug" "$ext")

curl -fsSL "$url" -o "$dir/$name"

python3 - "$dir/Generations.jsonl" "$name" "$model" "$prompt" "${cost:-}" "$url" <<'PY'
import datetime, json, sys
log, name, model, prompt, cost, url = sys.argv[1:7]
record = {
    "file": name,
    "model": model,
    "prompt": prompt,
    "source_url": url,
    "est_cost_usd": float(cost) if cost else None,
    "at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
}
with open(log, "a") as f:
    f.write(json.dumps(record) + "\n")
PY

echo "$dir/$name"
