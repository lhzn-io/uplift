#!/usr/bin/env bash
# start_stack.sh - Sovereign Stack Launcher
#
# First run: ./scripts/install_zeroclaw.sh (after provision_orin.sh + reboot)
# Subsequent boots: this script handles the backend.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf '\n[WARN] %s\n' "$*" >&2; }
die()  { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }

# Check arguments for setting model config
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --model) 
            if [ "$2" = "gemma4" ] || [ "$2" = "nemotron" ]; then
                "${SCRIPT_DIR}/scripts/use_$2.sh"
            else
                die "Unknown model choice: $2"
            fi
            shift ;;
        *) die "Unknown parameter passed: $1" ;;
    esac
    shift
done

# Ensure .env is populated with *some* defaults if it doesn't have VLLM_IMAGE
if ! grep -q "^VLLM_IMAGE=" "${SCRIPT_DIR}/.env" 2>/dev/null; then
    log "No model configuration found in .env, defaulting to Gemma4."
    "${SCRIPT_DIR}/scripts/use_gemma4.sh"
fi

# ---------------------------------------------------------------------------
# Backend: Inference Engine
# ---------------------------------------------------------------------------

# Check if services are already running
is_running=false
if docker compose ps | grep -q "reasoning-engine.*Up"; then
    log "Docker compose services appear to be Up already."
    is_running=true
fi

if [ "$is_running" = false ]; then
    log "Freeing memory/caches before boot..."
    # sync && echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null

    log "Starting sovereign stack reasoning-engine via Docker Compose..."
    echo ""
    docker compose up -d reasoning-engine

    log "Waiting for reasoning-engine to become ready on http://localhost:8000/v1/models (this may take a few minutes)..."
    deadline=$(( $(date +%s) + 420 ))
    inference_ready=false
    while [[ $(date +%s) -lt ${deadline} ]]; do
        if curl -fsS --max-time 4 "http://127.0.0.1:8000/v1/models" >/dev/null 2>&1; then
            log "reasoning-engine is ready!"
            inference_ready=true
            break
        fi
        sleep 5
    done
    
    if [ "$inference_ready" = false ]; then
        warn "reasoning-engine did not become ready within 7 minutes. Starting zeroclaw anyway..."
    fi

    log "Starting supplementary nodes (browser, jetson-telemetry)..."
    docker compose up -d browser-node jetson-telemetry

    log "Starting zeroclaw..."
    docker compose up -d zeroclaw
fi

echo ""
echo "  logs: docker compose logs -f reasoning-engine"
echo "  or:   docker compose logs -f"
echo ""

if ! pgrep -f "vllm_proxy.py" > /dev/null; then
    echo "  Starting vLLM proxy for capability translation..."
    nohup python3 "${SCRIPT_DIR}/scripts/vllm_proxy.py" --listen-port 8100 --vllm-port 8000 > "${SCRIPT_DIR}/vllm_proxy.log" 2>&1 &
fi
echo "  Logs:     docker logs -f reasoning-engine"
echo "  Endpoint: http://localhost:8000/v1 (Native) | :8100/v1 (Proxy)"

# ---------------------------------------------------------------------------
# if ! pgrep -f "zeroclaw daemon" > /dev/null && ! nc -z 127.0.0.1 42617 2>/dev/null ; then
#     log "Starting ZeroClaw... (not found on port 42617)..."
#     nohup zeroclaw daemon --config-dir "${SCRIPT_DIR}/.zeroclaw" > "${SCRIPT_DIR}/zeroclaw_daemon.log" 2>&1 &
# fi
# 

echo ""
echo "Sovereign Stack is up."
echo ""
echo "  Dashboard:      http://127.0.0.1:42617"
echo "  Inference logs: docker logs -f reasoning-engine"
echo "  Daemon logs:    tail -f ${SCRIPT_DIR}/zeroclaw_daemon.log"
echo ""
