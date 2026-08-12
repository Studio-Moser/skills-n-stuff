#!/usr/bin/env bash
# Pull current LLM cost + intelligence from the Artificial Analysis API.
# Requires ARTIFICIAL_ANALYSIS_API_KEY (free key: https://artificialanalysis.ai/data-api).
# Emits TSV: name \t creator \t input_$/M \t output_$/M \t coding_index \t agentic_index
# Exit 3 = no key (caller should fall back to manual/vendor docs).
# Exit 4 = request failed.
# Exit 5 = response parsed but no row yielded any figure — schema drift, not empty data.
set -euo pipefail

key="${ARTIFICIAL_ANALYSIS_API_KEY:-}"
if [ -z "$key" ]; then
  echo "ARTIFICIAL_ANALYSIS_API_KEY not set — skipping live model data; fall back to vendor docs/judgment." >&2
  exit 3
fi

url="${AA_MODELS_URL:-https://artificialanalysis.ai/api/v2/language/models/free}"
resp="$(curl -fsS -H "x-api-key: $key" "$url")" || { echo "Artificial Analysis API request failed." >&2; exit 4; }

# v2 nests figures under .pricing and .evaluations. The flat fallbacks cover
# pre-v2 payloads; drop them once no caller pins an older AA_MODELS_URL.
out="$(echo "$resp" | jq -r '
  (.data // .)
  | (if type=="array" then . else [.] end)[]
  | [ .name,
      (.model_creator.name // .model_creator // "?"),
      (.pricing.price_1m_input_tokens  // .price_1m_input_tokens  // "?"),
      (.pricing.price_1m_output_tokens // .price_1m_output_tokens // "?"),
      (.evaluations.artificial_analysis_coding_index  // .artificial_analysis_coding_index  // "?"),
      (.evaluations.artificial_analysis_agentic_index // .artificial_analysis_agentic_index // "?") ]
  | @tsv')"

# A row with "?" is normal — AA omits figures for plenty of models. Every row
# missing every figure is not: that is the shape having moved under us, which
# previously surfaced as a full page of "?" and exit 0.
if [ -n "$out" ] && ! printf '%s\n' "$out" | cut -f3-6 | grep -qv '^?	?	?	?$'; then
  echo "Artificial Analysis returned rows but no pricing or index figures — the API shape has likely changed. Update the jq paths in $(basename "$0")." >&2
  exit 5
fi

printf '%s\n' "$out"
