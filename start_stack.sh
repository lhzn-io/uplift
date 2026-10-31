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
            if [ -n "${2:-}" ]; then
                "${SCRIPT_DIR}/scripts/use_model.sh" "$2"
            else
                die "--model requires an argument"
            fi
            shift ;;
        *) die "Unknown parameter passed: $1" ;;
    esac
    shift
done

# Ensure .env is populated with *some* defaults if it doesn't have VLLM_IMAGE
if ! grep -q "^VLLM_IMAGE=" "${SCRIPT_DIR}/.env" 2>/dev/null; then
    log "No model configuration found in .env, defaulting to Gemma4."
    "${SCRIPT_DIR}/scripts/use_model.sh" gemma4-26b-a4b
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
    sync && (echo 3 | sudo -n tee /proc/sys/vm/drop_caches > /dev/null 2>&1 || warn "Could not drop caches (non-fatal)")

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
    docker compose up -d zeroclaw-operator zeroclaw-admin
fi

# The agents reach vLLM through the instrumentation proxy on 127.0.0.1:8100.
# Prefer the user systemd unit from scripts/install_vllm_proxy.sh; fall back to
# its venv. The system python3 lacks the proxy's dependencies.
PROXY_VENV="${SCRIPT_DIR}/scripts/.vllm-proxy-venv/bin/python"
if systemctl --user cat vllm-proxy.service >/dev/null 2>&1; then
    log "Starting vLLM proxy (systemd user unit)..."
    systemctl --user start vllm-proxy.service || warn "vllm-proxy service failed to start"
elif ! pgrep -f "vllm_proxy.py" > /dev/null; then
    if [ -x "$PROXY_VENV" ]; then
        log "Starting vLLM proxy (venv)..."
        (cd "${SCRIPT_DIR}/scripts" && nohup "$PROXY_VENV" vllm_proxy.py > "${SCRIPT_DIR}/vllm_proxy.log" 2>&1 &)
    else
        warn "vLLM proxy is not installed; run ./scripts/install_vllm_proxy.sh"
    fi
fi

echo ""
echo "Sovereign Stack is up."
echo ""
echo "  Dashboards:     http://127.0.0.1:42617 (operator), :42618 (admin), via SSH tunnel"
echo "  Endpoints:      http://127.0.0.1:8000/v1 (vLLM) | :8100/v1 (proxy)"
echo "  Inference logs: docker compose logs -f reasoning-engine"
echo "  Agent logs:     docker compose logs -f zeroclaw-operator zeroclaw-admin"
echo "  Traces:         ${SCRIPT_DIR}/traces/"
echo ""
