#!/usr/bin/env bash
# tests/test_03_neuralyzer.sh — Neuralyzer hard wipe smoke test
# Destructive test: verifies /api/maintenance/neuralyze with mode=hard removes
# conversation namespace entries from the operator memory DB.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

GATEWAY_URL="${GATEWAY_URL:-http://127.0.0.1:42617}"
ADMIN_URL="${ADMIN_URL:-http://[::1]:42617}"
DB_PATH="${DB_PATH:-.zeroclaw-operator/workspace/memory/brain.db}"
TEST_KEY="copilot-neuralyzer-smoke"

suite "neuralyzer-hard-wipe"

if [[ "${ENABLE_NEURALYZER_WIPE_TEST:-0}" != "1" ]]; then
    skip "destructive wipe test enabled" "set ENABLE_NEURALYZER_WIPE_TEST=1 to run"
    suite_done
    exit $?
fi

if [[ ! -f "${DB_PATH}" ]]; then
    fail "memory DB exists" "missing: ${DB_PATH}"
    suite_done
    exit $?
fi

if docker ps --filter "name=zeroclaw-operator" --filter "status=running" --format '{{.Names}}' 2>/dev/null | grep -q 'zeroclaw-operator'; then
    pass "zeroclaw-operator container up"
else
    fail "zeroclaw-operator container up" "run: ./start_stack.sh"
    suite_done
    exit $?
fi

if http_ok "${GATEWAY_URL}/api/health" 5; then
    pass "gateway health endpoint reachable"
else
    fail "gateway health endpoint reachable" "url=${GATEWAY_URL}/api/health"
    suite_done
    exit $?
fi

pair_code_resp="$(curl -sS -X POST "${ADMIN_URL}/admin/paircode/new" 2>/dev/null || echo '{}')"
pair_code="$(echo "${pair_code_resp}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pairing_code',''))" 2>/dev/null || true)"
if [[ -n "${pair_code}" ]]; then
    pass "generated pairing code"
else
    fail "generated pairing code" "response: ${pair_code_resp:0:200}"
    suite_done
    exit $?
fi

pair_resp="$(curl -sS -X POST -H "X-Pairing-Code: ${pair_code}" "${GATEWAY_URL}/pair" 2>/dev/null || echo '{}')"
token="$(echo "${pair_resp}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('token',''))" 2>/dev/null || true)"
if [[ -n "${token}" ]]; then
    pass "paired and received bearer token"
else
    fail "paired and received bearer token" "response: ${pair_resp:0:200}"
    suite_done
    exit $?
fi

before_count="$(python3 - <<PY
import sqlite3, time, uuid
path = "${DB_PATH}"
key = "${TEST_KEY}"
conn = sqlite3.connect(path)
cur = conn.cursor()
cur.execute("DELETE FROM memories WHERE key=?", (key,))
cur.execute(
    "INSERT INTO memories (id, key, content, category, namespace, created_at, updated_at, importance) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
    (str(uuid.uuid4()), key, "smoke row for hard wipe", "conversation", "conversation", int(time.time()), int(time.time()), 0.1),
)
conn.commit()
cur.execute("SELECT COUNT(*) FROM memories WHERE key=? AND namespace='conversation'", (key,))
print(cur.fetchone()[0])
PY
)"
if [[ "${before_count}" == "1" ]]; then
    pass "seeded conversation memory row"
else
    fail "seeded conversation memory row" "count=${before_count}"
    suite_done
    exit $?
fi

wipe_resp="$(curl -sS -X POST "${GATEWAY_URL}/api/maintenance/neuralyze" -H "Authorization: Bearer ${token}" -H 'Content-Type: application/json' -d '{"mode":"hard"}' 2>/dev/null || echo '{}')"
wipe_status="$(echo "${wipe_resp}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status',''))" 2>/dev/null || true)"
if [[ "${wipe_status}" == "success" ]]; then
    pass "maintenance neuralyze hard call returns success"
else
    fail "maintenance neuralyze hard call returns success" "response: ${wipe_resp:0:260}"
    suite_done
    exit $?
fi

after_count="$(python3 - <<PY
import sqlite3
path = "${DB_PATH}"
key = "${TEST_KEY}"
conn = sqlite3.connect(path)
cur = conn.cursor()
cur.execute("SELECT COUNT(*) FROM memories WHERE key=? AND namespace='conversation'", (key,))
print(cur.fetchone()[0])
PY
)"
if [[ "${after_count}" == "0" ]]; then
    pass "hard wipe removed conversation memory row"
else
    fail "hard wipe removed conversation memory row" "count=${after_count}"
fi

suite_done
