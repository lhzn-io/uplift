#!/usr/bin/env bash
# tests/lib/common.sh — shared test framework
# Source this file from each test module:
#   source "$(dirname "$0")/lib/common.sh"

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${TESTS_DIR}/results"
FIXTURES_DIR="${TESTS_DIR}/fixtures"
mkdir -p "${RESULTS_DIR}"

# State accumulated across a test run
_SUITE_NAME=""
_PASS=0
_FAIL=0
_SKIP=0
_RESULTS=()      # array of JSON objects

# ---------------------------------------------------------------------------
# Suite setup
# ---------------------------------------------------------------------------
suite() {
    _SUITE_NAME="$1"
    _PASS=0; _FAIL=0; _SKIP=0
    _RESULTS=()
    printf '\n\033[1m=== %s ===\033[0m\n' "${_SUITE_NAME}"
}

# ---------------------------------------------------------------------------
# Individual test reporting
# ---------------------------------------------------------------------------
pass() {
    local name="$1"
    _PASS=$((_PASS + 1))
    _RESULTS+=("{\"test\":$(json_str "${name}"),\"result\":\"pass\"}")
    printf '  \033[32m[✓]\033[0m %s\n' "${name}"
}

fail() {
    local name="$1"
    local detail="${2:-}"
    _FAIL=$((_FAIL + 1))
    _RESULTS+=("{\"test\":$(json_str "${name}"),\"result\":\"fail\",\"detail\":$(json_str "${detail}")}")
    printf '  \033[31m[✗]\033[0m %s' "${name}"
    [[ -n "${detail}" ]] && printf '  →  %s' "${detail}"
    printf '\n'
}

skip() {
    local name="$1"
    local reason="${2:-}"
    _SKIP=$((_SKIP + 1))
    _RESULTS+=("{\"test\":$(json_str "${name}"),\"result\":\"skip\",\"detail\":$(json_str "${reason}")}")
    printf '  \033[33m[-]\033[0m %s  (skipped: %s)\n' "${name}" "${reason}"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
json_str() {
    # Minimal JSON string escaping
    local s="${1//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//	/\\t}"
    s="${s//$'\n'/\\n}"
    printf '"%s"' "${s}"
}

require_cmd() {
    local cmd="$1"
    command -v "${cmd}" >/dev/null 2>&1
}

http_ok() {
    # Returns 0 if HTTP GET to URL returns 2xx
    local url="$1"
    local timeout="${2:-5}"
    local code
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time "${timeout}" "${url}" 2>/dev/null)"
    [[ "${code}" =~ ^2 ]]
}

http_json() {
    # Returns JSON body from GET, or empty string on failure
    local url="$1"
    local timeout="${2:-10}"
    curl -s --max-time "${timeout}" "${url}" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Suite finalizer — writes results JSON, prints summary, returns exit code
# ---------------------------------------------------------------------------
suite_done() {
    local ts
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    local result_file="${RESULTS_DIR}/${_SUITE_NAME// /_}_${ts}.json"

    local json_arr
    json_arr="$(IFS=','; echo "${_RESULTS[*]}")"
    printf '{"suite":%s,"pass":%d,"fail":%d,"skip":%d,"tests":[%s]}\n' \
        "$(json_str "${_SUITE_NAME}")" "${_PASS}" "${_FAIL}" "${_SKIP}" "${json_arr}" \
        > "${result_file}"

    printf '\n  pass: %d  fail: %d  skip: %d\n' "${_PASS}" "${_FAIL}" "${_SKIP}"
    printf '  results: %s\n' "${result_file}"

    [[ "${_FAIL}" -eq 0 ]]   # non-zero exit if any failures
}
