#!/usr/bin/env bash
# stop_stack.sh - Sovereign Stack Shutdown
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf '\n[WARN] %s\n' "$*" >&2; }

# Provide dummy defaults so docker-compose.yml parses successfully
export VLLM_IMAGE=${VLLM_IMAGE:-"dummy"}
export VLLM_MODEL=${VLLM_MODEL:-"dummy"}
export VLLM_SERVED_MODEL_NAME=${VLLM_SERVED_MODEL_NAME:-"dummy"}
export VLLM_GPU_MEMORY_UTILIZATION=${VLLM_GPU_MEMORY_UTILIZATION:-"dummy"}
export VLLM_EXTRA_ARGS=${VLLM_EXTRA_ARGS:-"dummy"}

if [[ "${1:-}" == "--zeroclaw-only" || "${1:-}" == "zeroclaw" ]]; then
    log "Stopping ONLY zeroclaw"
    docker compose stop zeroclaw >/dev/null || \
        warn "docker compose stop zeroclaw reported a problem"
    echo ""
    echo "ZeroClaw stopped (vLLM reasoning-engine is still running)."
    echo ""
else
    log "Stopping reasoning-engine, zeroclaw, and telemetry nodes"
    docker compose stop >/dev/null || \
        warn "docker compose stop reported a problem"

    echo ""
    echo "Sovereign Stack is down."
    echo ""
fi
echo "  Start again with: ./start_stack.sh"