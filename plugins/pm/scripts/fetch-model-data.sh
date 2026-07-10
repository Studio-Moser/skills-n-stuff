#!/usr/bin/env bash
# Pull current LLM cost + intelligence from the Artificial Analysis API.
# Requires ARTIFICIAL_ANALYSIS_API_KEY (free key: https://artificialanalysis.ai/data-api).
# Emits TSV: name \t creator \t input_$/M \t output_$/M \t coding_index \t agentic_index
# Exit 3 = no key (caller should fall back to manual/vendor docs).
set -euo pipefail

key="${ARTIFICIAL_ANALYSIS_API_KEY:-}"
if [ -z "$key" ]; then
  echo "ARTIFICIAL_ANALYSIS_API_KEY not set — skipping live model data; fall back to vendor docs/judgment." >&2
  exit 3
fi

url="${AA_MODELS_URL:-https://artificialanalysis.ai/api/v2/language/models/free}"
resp="$(curl -fsS -H "x-api-key: $key" "$url")" || { echo "Artificial Analysis API request failed." >&2; exit 4; }

echo "$resp" | jq -r '
  (.data // .)
  | (if type=="array" then . else [.] end)[]
  | [ .name,
      (.model_creator.name // .model_creator // "?"),
      (.price_1m_input_tokens // "?"),
      (.price_1m_output_tokens // "?"),
      (.artificial_analysis_coding_index // "?"),
      (.artificial_analysis_agentic_index // "?") ]
  | @tsv'
