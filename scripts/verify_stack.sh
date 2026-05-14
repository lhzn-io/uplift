#!/usr/bin/env bash
# scripts/verify_stack.sh — full stack verification harness
#
# Runs text-based integrity tests for host, inference, zeroclaw agents,
# and end-to-end chat completions.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${ROOT_DIR}/tests"
RESULTS_DIR="${TEST_DIR}/results"
mkdir -p "${RESULTS_DIR}"

# Ensure VLLM_* env vars are set so any docker-compose invocation downstream
# can parse docker-compose.yml. Harmless if the caller already sourced env.sh.
if [ -z "${VLLM_SERVED_MODEL_NAME:-}" ]; then
    # shellcheck disable=SC1091
    source "${ROOT_DIR}/scripts/env.sh" "${MODEL_CHOICE:-gemma4}"
fi

RUN_INFERENCE="true"
RUN_ZEROCLAW="true"
RUN_E2E="true"
RUN_LAZY_LOAD="true"

usage() {
  cat <<'HELP'
Usage:
  ./scripts/verify_stack.sh [options]

Options:
  --host-only            Run only host prerequisite checks
  --skip-inference       Skip test_01_inference.sh
  --skip-zeroclaw        Skip test_02_zeroclaw.sh
  --skip-e2e             Skip test_04_e2e_inference.py
  --skip-lazy-load       Skip test_05_lazy_load.py (functional tool_search test)
  -h, --help             Show this help
HELP
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host-only)
      RUN_INFERENCE="false"
      RUN_ZEROCLAW="false"
      RUN_E2E="false"
      RUN_LAZY_LOAD="false"
      shift
      ;;
    --skip-inference)
      RUN_INFERENCE="false"
      shift
      ;;
    --skip-zeroclaw)
      RUN_ZEROCLAW="false"
      shift
      ;;
    --skip-e2e)
      RUN_E2E="false"
      shift
      ;;
    --skip-lazy-load)
      RUN_LAZY_LOAD="false"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

FAILS=0

run_suite() {
  local name="$1"
  local cmd="$2"

  echo ""
  echo "==> Running ${name}"
  set +e
  bash -lc "${cmd}"
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    echo "    [PASS] ${name}"
  else
    echo "    [FAIL] ${name} (exit=${rc})"
  fi
  return $rc
}

wait_for_inference_ready() {
  local timeout_sec="${1:-420}"
  local deadline=$(( $(date +%s) + timeout_sec ))

  # Check either directly or via proxy (8100)
  echo "==> Waiting for inference API readiness (timeout: ${timeout_sec}s)"
  while [[ $(date +%s) -lt ${deadline} ]]; do
    if curl -fsS --max-time 4 "http://127.0.0.1:8100/v1/models" >/dev/null 2>&1 || \
       curl -fsS --max-time 4 "http://127.0.0.1:8000/v1/models" >/dev/null 2>&1; then
      echo "    inference API is ready"
      return 0
    fi
    sleep 5
  done

  echo "    inference API did not become ready within ${timeout_sec}s"
  return 1
}

# If reasoning-engine is not up, try to start it for inference/e2e tests.
if [[ "${RUN_INFERENCE}" == "true" || "${RUN_E2E}" == "true" ]]; then
  if ! docker compose -f "${ROOT_DIR}/docker-compose.yml" ps reasoning-engine 2>/dev/null | grep -q 'Up'; then
    echo "==> Starting reasoning-engine"
    docker compose -f "${ROOT_DIR}/docker-compose.yml" up -d reasoning-engine >/dev/null
  fi

  # vLLM startup on Jetson may include model load + torch.compile warmup.
  # Wait here so inference/e2e suites do not fail due to transient startup.
  if ! wait_for_inference_ready 420; then
    FAILS=$((FAILS + 1))
  fi
fi

if [[ "${RUN_ZEROCLAW}" == "true" ]]; then
  if ! docker compose -f "${ROOT_DIR}/docker-compose.yml" ps jetson-telemetry 2>/dev/null | grep -q 'Up'; then
    echo "==> Starting jetson-telemetry container"
    docker compose -f "${ROOT_DIR}/docker-compose.yml" up -d jetson-telemetry >/dev/null
  fi
  
  if ! docker compose -f "${ROOT_DIR}/docker-compose.yml" ps zeroclaw-operator 2>/dev/null | grep -q 'Up'; then
    echo "==> Starting zeroclaw-operator container"
    docker compose -f "${ROOT_DIR}/docker-compose.yml" up -d zeroclaw-operator >/dev/null
  fi

  if ! docker compose -f "${ROOT_DIR}/docker-compose.yml" ps zeroclaw-admin 2>/dev/null | grep -q 'Up'; then
    echo "==> Starting zeroclaw-admin container"
    docker compose -f "${ROOT_DIR}/docker-compose.yml" up -d zeroclaw-admin >/dev/null
  fi
fi

run_suite "host" "cd '${ROOT_DIR}' && ./tests/test_00_host.sh" || FAILS=$((FAILS + 1))

if [[ "${RUN_INFERENCE}" == "true" ]]; then
  run_suite "inference" "cd '${ROOT_DIR}' && ./tests/test_01_inference.sh" || FAILS=$((FAILS + 1))
fi

if [[ "${RUN_ZEROCLAW}" == "true" ]]; then
  run_suite "zeroclaw" "cd '${ROOT_DIR}' && ./tests/test_02_zeroclaw.sh" || FAILS=$((FAILS + 1))
fi

if [[ "${RUN_E2E}" == "true" ]]; then
  run_suite "e2e-inference" "cd '${ROOT_DIR}' && python3 ./tests/test_04_e2e_inference.py" || FAILS=$((FAILS + 1))
fi

if [[ "${RUN_LAZY_LOAD}" == "true" ]]; then
  # Functional assertion that the deferred-loading path (tool_search →
  # activate → call) works end-to-end.
  run_suite "lazy-load" "cd '${ROOT_DIR}' && python3 ./tests/test_05_lazy_load.py" || FAILS=$((FAILS + 1))
fi

echo ""
echo "==> Stack verification complete"
echo "    failures: ${FAILS}"
echo "    results dir: ${RESULTS_DIR}"

if [[ ${FAILS} -eq 0 ]]; then
  echo ""
  echo "Sovereign Stack verified and running."
else
  echo ""
  echo "/!\\ Warning: Stack verified with ${FAILS} failure(s). The UI might be degraded."
fi

# Get tokens from both agents if possible
OP_TOKEN=$(docker compose -f "${ROOT_DIR}/docker-compose.yml" exec zeroclaw-operator zeroclaw gateway list-paired-tokens 2>/dev/null | grep -v "2026-" | head -n 1 || true)
ADMIN_TOKEN=$(docker compose -f "${ROOT_DIR}/docker-compose.yml" exec zeroclaw-admin zeroclaw gateway list-paired-tokens 2>/dev/null | grep -v "2026-" | head -n 1 || true)

echo ""
BROWSER_NODE_STATUS="Down or Missing"
if docker compose -f "${ROOT_DIR}/docker-compose.yml" ps browser-node 2>/dev/null | grep -q 'Up'; then
    BROWSER_NODE_STATUS="Up"
fi

JETSON_MCP_STATUS="Down or Missing"
if docker compose -f "${ROOT_DIR}/docker-compose.yml" ps jetson-telemetry 2>/dev/null | grep -q 'Up'; then
    JETSON_MCP_STATUS="Up (Listening on :8765)"
fi

echo "  Operator UI:    http://$(hostname -I | awk '{print $1}'):42617"
echo "  Admin UI:       http://$(hostname -I | awk '{print $1}'):42618 (Turbo Pascal Theme)"
echo "  Browser Node:   ${BROWSER_NODE_STATUS}"
echo "  Jetson MCP:     ${JETSON_MCP_STATUS}"
echo "  Inference logs: docker logs -f reasoning-engine"
echo ""

if [[ ${FAILS} -eq 0 ]]; then
  exit 0
fi

exit 1
