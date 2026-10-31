#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
TRACE_DIR="${ROOT_DIR}/traces"
COMBINED="${TRACE_DIR}/combined.jsonl"

# Per-turn records come from the agents (traces/operator, traces/admin) and
# per-request records from the vLLM proxy (traces/proxy); merge them for the report.
shopt -s nullglob
SOURCES=("${TRACE_DIR}"/*/uplift-trace.jsonl)
if [ ${#SOURCES[@]} -eq 0 ]; then
    echo "No trace files under ${TRACE_DIR}/*/uplift-trace.jsonl" >&2
    exit 1
fi
cat "${SOURCES[@]}" > "${COMBINED}"

echo "==> Generating Uplift Release Report from ${#SOURCES[@]} trace file(s)"
python3 -c "from uplift.release_report import generate_report; generate_report('${COMBINED}', '${ROOT_DIR}/data/release_report.md')"
echo "==> Complete."
