#!/usr/bin/env bash
# tests/test_02_zeroclaw.sh — zeroclaw gateway checks
# Verifies the zeroclaw layer is healthy after boot/recovery.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

suite "zeroclaw-control-plane"

# --- CLI available ---
if require_cmd zeroclaw; then
    pass "zeroclaw CLI in PATH"
else
    skip "zeroclaw CLI in PATH" "not installed — run scripts/install_zeroclaw.sh"
    suite_done
    exit $?
fi

# --- Gateway daemon status ---
if zeroclaw status >/dev/null 2>&1; then
    pass "zeroclaw status returns OK"
else
    fail "zeroclaw status returns OK" "daemon might be down or unreachable"
fi

suite_done
