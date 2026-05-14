#!/usr/bin/env bash
# tests/test_02_zeroclaw.sh — zeroclaw agent checks
# Verifies both Operator and Admin agents are healthy.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

suite "zeroclaw-agents"

# --- Operator Agent status ---
if docker compose exec zeroclaw-operator zeroclaw status >/dev/null 2>&1; then
    pass "Operator Agent status returns OK"
else
    fail "Operator Agent status returns OK" "container might be down or unreachable"
fi

# --- Admin Agent status ---
if docker compose exec zeroclaw-admin zeroclaw status >/dev/null 2>&1; then
    pass "Admin Agent status returns OK"
else
    fail "Admin Agent status returns OK" "container might be down or unreachable"
fi

suite_done
