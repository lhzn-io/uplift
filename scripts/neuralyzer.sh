#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Wiping Agent memory and session state..."

WIPE_STATE=true
WIPE_SESSIONS=false
WIPE_MEMORY=false

if [ -t 0 ] && [ -t 1 ]; then
    echo "=========================================================="
    echo "                  ZeroClaw Neuralyzer                     "
    echo "=========================================================="
    echo "Select the level of memory wipe you want to perform:"
    echo "  1) State Only (Active connections, pairings, locks)"
    echo "  2) State + Chat Sessions (Clears current conversation history)"
    echo "  3) Full Lobotomy (State + Sessions + Long-term Memory/Knowledge)"
    echo ""
    echo "  0) Cancel"
    echo -n "Enter choice [0-3]: "
    read -r choice

    case "$choice" in
        1) WIPE_STATE=true ;;
        2) WIPE_STATE=true; WIPE_SESSIONS=true ;;
        3) WIPE_STATE=true; WIPE_SESSIONS=true; WIPE_MEMORY=true ;;
        0|*) echo "Operation cancelled."; exit 0 ;;
    esac
else
    echo "Non-interactive terminal detected. Defaulting to State Wipe Only."
fi

echo "Preparing to wipe selected memory..."

# Stop daemon/container if running to release database locks
echo "Stopping Agent services..."
(cd "$PROJECT_ROOT" && docker compose stop zeroclaw-operator zeroclaw-admin 2>/dev/null) || true

AGENT_BASES=("${PROJECT_ROOT}/.zeroclaw-operator" "${PROJECT_ROOT}/.zeroclaw-admin")

for base in "${AGENT_BASES[@]}"; do
    workspace="${base}/workspace"
    echo "--- Wiping ${base##*/} ---"
    
    if [ "$WIPE_STATE" = true ]; then
        echo "- Wiping physical state files and pairings..."
        if [ -d "$workspace/state" ]; then
            rm -rf "${workspace}/state/"*
        fi
        if [ -f "$workspace/devices.db" ]; then
            rm -f "$workspace/devices.db"*
        fi
        rm -f "${base}/daemon_state.json"
    fi

    if [ "$WIPE_SESSIONS" = true ]; then
        echo "- Wiping chat sessions..."
        if [ -d "$workspace/sessions" ]; then
            rm -rf "${workspace}/sessions/"*
        fi
    fi

    if [ "$WIPE_MEMORY" = true ]; then
        echo "- Wiping long-term memory (knowledge)..."
        if [ -d "$workspace/memory" ]; then
            rm -rf "${workspace}/memory/"*
        fi
    fi
done

echo ""
echo "Neuralyzer complete. Bring the stack back up with:"
echo "  ./scripts/apply_config.sh && docker compose up -d"
echo "  (or ./start_stack.sh)"
