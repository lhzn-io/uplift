#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Wiping Agent memory and session state..."

WIPE_STATE=true
WIPE_SESSIONS=false
WIPE_MEMORY=false

# NEURALYZER_LEVEL=1|2|3 selects the wipe level without a prompt (used by
# tests/test_03_neuralyzer.sh and other automation).
if [ -n "${NEURALYZER_LEVEL:-}" ]; then
    case "$NEURALYZER_LEVEL" in
        1) WIPE_STATE=true ;;
        2) WIPE_STATE=true; WIPE_SESSIONS=true ;;
        3) WIPE_STATE=true; WIPE_SESSIONS=true; WIPE_MEMORY=true ;;
        *) echo "NEURALYZER_LEVEL must be 1, 2 or 3" >&2; exit 2 ;;
    esac
    echo "Wipe level ${NEURALYZER_LEVEL} selected via NEURALYZER_LEVEL."
elif [ -t 0 ] && [ -t 1 ]; then
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

# ZeroClaw config schema V3 layout: .zeroclaw-<tier>/ is the install root and
# runtime state lives under data/. The agent workspace (agents/default/workspace)
# and the uplift traces (./traces/<tier>/) are deliberately left untouched.
AGENT_BASES=("${PROJECT_ROOT}/.zeroclaw-operator" "${PROJECT_ROOT}/.zeroclaw-admin")

for base in "${AGENT_BASES[@]}"; do
    data="${base}/data"
    echo "--- Wiping ${base##*/} ---"

    if [ "$WIPE_STATE" = true ]; then
        echo "- Wiping physical state files and pairings..."
        if [ -d "$data/state" ]; then
            rm -rf "${data}/state/"*
        fi
        rm -f "${data}/devices.db"*
    fi

    if [ "$WIPE_SESSIONS" = true ]; then
        echo "- Wiping chat sessions..."
        if [ -d "$data/sessions" ]; then
            rm -rf "${data}/sessions/"*
        fi
    fi

    if [ "$WIPE_MEMORY" = true ]; then
        echo "- Wiping long-term memory (knowledge)..."
        if [ -d "$data/memory" ]; then
            rm -rf "${data}/memory/"*
        fi
    fi
done

echo ""
echo "Neuralyzer complete. Bring the stack back up with:"
echo "  ./scripts/apply_config.sh && docker compose up -d"
echo "  (or ./start_stack.sh)"
