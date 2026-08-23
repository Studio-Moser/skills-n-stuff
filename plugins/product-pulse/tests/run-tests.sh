#!/usr/bin/env bash
# Run every Product Pulse contract test.
set -euo pipefail
cd "$(dirname "$0")"
bats *.bats
