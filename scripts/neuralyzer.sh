#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Wiping ZeroClaw memory and session state..."

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
echo "Stopping zeroclaw process and docker container..."
(cd "$PROJECT_ROOT" && docker compose stop zeroclaw 2>/dev/null) || true
pkill -f zeroclaw || true

if [ "$WIPE_STATE" = true ]; then
    echo "- Wiping physical state files and pairings..."
    for base in "${PROJECT_ROOT}/workspace" "${PROJECT_ROOT}/.zeroclaw/workspace"; do
        if [ -d "$base/state" ]; then
            rm -rf "${base}/state/"*
        fi
        if [ -f "$base/devices.db" ]; then
            rm -f "$base/devices.db"
            rm -f "$base/devices.db-wal"
            rm -f "$base/devices.db-shm"
        fi
    done
    rm -f "${PROJECT_ROOT}/.zeroclaw/daemon_state.json"
    echo "  Ok. State and pairings wiped successfully."
fi

if [ "$WIPE_SESSIONS" = true ]; then
    echo "- Wiping chat sessions..."
    for base in "${PROJECT_ROOT}/workspace" "${PROJECT_ROOT}/.zeroclaw/workspace"; do
        if [ -d "$base/sessions" ]; then
            rm -rf "${base}/sessions/"*
        fi
    done
    echo "  Ok. Chat sessions purged."
fi

if [ "$WIPE_MEMORY" = true ]; then
    echo "- Wiping long-term memory (knowledge)..."
    for base in "${PROJECT_ROOT}/workspace" "${PROJECT_ROOT}/.zeroclaw/workspace"; do
        if [ -d "$base/memory" ]; then
            rm -rf "${base}/memory/"*
        fi
    done
    echo "  Ok. Long-term memory purged."
fi

echo ""
echo "Neuralyzer complete. Bring the stack back up with:"
echo "  docker compose restart zeroclaw"
echo "  (or ./start_stack.sh)"
