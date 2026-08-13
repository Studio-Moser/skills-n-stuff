#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/fetch-model-data.sh"
}

@test "exits 3 and warns when API key is unset" {
  unset ARTIFICIAL_ANALYSIS_API_KEY
  run "$SCRIPT"
  [ "$status" -eq 3 ]
}

@test "emits normalized TSV from the v2 nested shape" {
  export ARTIFICIAL_ANALYSIS_API_KEY=dummy
  fixture="${BATS_TEST_TMPDIR}/models.json"
  cat > "$fixture" <<'JSON'
{"data":[{"name":"Model X","model_creator":{"name":"Acme"},"pricing":{"price_1m_input_tokens":1.5,"price_1m_output_tokens":6},"evaluations":{"artificial_analysis_coding_index":72,"artificial_analysis_agentic_index":55}}]}
JSON
  export AA_MODELS_URL="file://$fixture"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Model X"* ]]
  [[ "$output" == *"Acme"* ]]
  [[ "$output" == *"72"* ]]
  [[ "$output" == *"55"* ]]
}

@test "still reads the pre-v2 flat shape" {
  export ARTIFICIAL_ANALYSIS_API_KEY=dummy
  fixture="${BATS_TEST_TMPDIR}/flat.json"
  cat > "$fixture" <<'JSON'
{"data":[{"name":"Model Y","model_creator":{"name":"Acme"},"price_1m_input_tokens":2,"price_1m_output_tokens":8,"artificial_analysis_coding_index":60,"artificial_analysis_agentic_index":40}]}
JSON
  export AA_MODELS_URL="file://$fixture"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"60"* ]]
}

@test "a model with no published figures is fine alongside one that has them" {
  export ARTIFICIAL_ANALYSIS_API_KEY=dummy
  fixture="${BATS_TEST_TMPDIR}/mixed.json"
  cat > "$fixture" <<'JSON'
{"data":[{"name":"Bare","model_creator":{"name":"Acme"}},{"name":"Full","model_creator":{"name":"Acme"},"pricing":{"price_1m_input_tokens":5,"price_1m_output_tokens":25},"evaluations":{"artificial_analysis_coding_index":77,"artificial_analysis_agentic_index":58.4}}]}
JSON
  export AA_MODELS_URL="file://$fixture"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bare"* ]]
  [[ "$output" == *"77"* ]]
}

# The regression guard: an unrecognized shape used to yield a full page of "?"
# and exit 0, so callers wrote a rubric from nothing and never knew.
@test "exits 5 when no row yields any figure (schema drift)" {
  export ARTIFICIAL_ANALYSIS_API_KEY=dummy
  fixture="${BATS_TEST_TMPDIR}/drifted.json"
  cat > "$fixture" <<'JSON'
{"data":[{"name":"Model Z","model_creator":{"name":"Acme"},"cost":{"in":1,"out":2},"scores":{"coding":70}}]}
JSON
  export AA_MODELS_URL="file://$fixture"
  run "$SCRIPT"
  [ "$status" -eq 5 ]
  [[ "$output" == *"shape has likely changed"* ]]
}
