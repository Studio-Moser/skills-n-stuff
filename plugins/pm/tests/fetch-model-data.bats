#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/fetch-model-data.sh"
}

@test "exits 3 and warns when API key is unset" {
  unset ARTIFICIAL_ANALYSIS_API_KEY
  run "$SCRIPT"
  [ "$status" -eq 3 ]
}

@test "emits normalized TSV from AA-shaped JSON" {
  export ARTIFICIAL_ANALYSIS_API_KEY=dummy
  fixture="${BATS_TEST_TMPDIR}/models.json"
  cat > "$fixture" <<'JSON'
{"data":[{"name":"Model X","model_creator":{"name":"Acme"},"price_1m_input_tokens":1.5,"price_1m_output_tokens":6,"artificial_analysis_coding_index":72,"artificial_analysis_agentic_index":55}]}
JSON
  export AA_MODELS_URL="file://$fixture"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Model X"* ]]
  [[ "$output" == *"Acme"* ]]
  [[ "$output" == *"72"* ]]
  [[ "$output" == *"55"* ]]
}
