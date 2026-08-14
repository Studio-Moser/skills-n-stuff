#!/usr/bin/env bash
# Run every .bats file under plugins/machine/tests/.
set -euo pipefail
cd "$(dirname "$0")"
bats *.bats
