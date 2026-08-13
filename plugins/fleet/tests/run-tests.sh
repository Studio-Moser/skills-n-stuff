#!/usr/bin/env bash
# Run every .bats file under plugins/fleet/tests/.
set -euo pipefail
cd "$(dirname "$0")"
bats *.bats
