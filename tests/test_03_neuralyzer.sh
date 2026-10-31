#!/usr/bin/env bash
# tests/test_03_neuralyzer.sh: scripts/neuralyzer.sh wipe smoke test
# Destructive test: runs the offline neuralyzer at level 3 (state, sessions and
# long-term memory) against the operator's ZeroClaw V3 install root, and checks
# that the agent workspace and the uplift traces survive. Restarts the agents.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${ROOT_DIR}/.zeroclaw-operator"
PROBE="neuralyzer-probe"

suite "neuralyzer-wipe"

if [[ "${ENABLE_NEURALYZER_WIPE_TEST:-0}" != "1" ]]; then
    skip "destructive wipe test enabled" "set ENABLE_NEURALYZER_WIPE_TEST=1 to run"
    suite_done
    exit $?
fi

if [[ ! -d "${BASE}/data" ]]; then
    fail "operator data dir exists" "missing: ${BASE}/data (start the stack once first)"
    suite_done
    exit $?
fi

# Probes that must be wiped, and probes that must survive.
WIPED=("${BASE}/data/state/${PROBE}" "${BASE}/data/sessions/${PROBE}" "${BASE}/data/memory/${PROBE}")
KEPT=("${BASE}/agents/default/workspace/${PROBE}" "${ROOT_DIR}/traces/operator/${PROBE}")
for f in "${WIPED[@]}" "${KEPT[@]}"; do
    mkdir -p "$(dirname "$f")" && echo probe > "$f"
done
pass "seeded probe files"

if NEURALYZER_LEVEL=3 "${ROOT_DIR}/scripts/neuralyzer.sh" > /dev/null 2>&1; then
    pass "neuralyzer.sh level 3 exits 0"
else
    fail "neuralyzer.sh level 3 exits 0" "re-run: NEURALYZER_LEVEL=3 ./scripts/neuralyzer.sh"
fi

for f in "${WIPED[@]}"; do
    if [[ ! -e "$f" ]]; then pass "wiped ${f#${ROOT_DIR}/}"; else fail "wiped ${f#${ROOT_DIR}/}" "still present"; fi
done
for f in "${KEPT[@]}"; do
    if [[ -e "$f" ]]; then pass "kept ${f#${ROOT_DIR}/}"; else fail "kept ${f#${ROOT_DIR}/}" "removed"; fi
    rm -f "$f"
done

(cd "${ROOT_DIR}" && docker compose up -d zeroclaw-operator zeroclaw-admin > /dev/null 2>&1) \
    && pass "agents restarted" || fail "agents restarted" "run: docker compose up -d zeroclaw-operator zeroclaw-admin"

suite_done
