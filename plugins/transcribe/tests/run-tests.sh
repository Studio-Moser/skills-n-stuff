#!/usr/bin/env bash
# Run every transcribe test.
set -euo pipefail
cd "$(dirname "$0")"
bats *.bats
