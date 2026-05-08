#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."

echo "==> Generating Uplift Release Report"
python3 -c "from uplift.release_report import generate_report; generate_report('${ROOT_DIR}/data/traces.jsonl', '${ROOT_DIR}/data/release_report.md')"
echo "==> Complete."
