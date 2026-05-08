#!/usr/bin/env bash
# tests/test_01_inference.sh — vLLM reasoning-engine checks
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

INFERENCE_URL="${INFERENCE_URL:-http://127.0.0.1:8000}"
MODEL="${VLLM_SERVED_MODEL_NAME:-gemma-4-26b-a4b}"
TIMEOUT=30

suite "inference-engine"

# Use `docker ps` directly — `docker compose ps` requires the VLLM_* env vars
# referenced in docker-compose.yml, which aren't in scope for the test runner.
if docker ps --filter "name=reasoning-engine" --filter "status=running" --format '{{.Names}}' 2>/dev/null | grep -q 'reasoning-engine'; then
    pass "reasoning-engine container up"
else
    fail "reasoning-engine container up" "run: ./start_stack.sh"
fi

if curl -s --max-time 5 "${INFERENCE_URL}/health" >/dev/null 2>&1 \
   || curl -s --max-time 5 "${INFERENCE_URL}/v1/models" >/dev/null 2>&1; then
    pass "port 8000 reachable"
else
    fail "port 8000 reachable" "model may still be loading — retry after a few minutes"
    suite_done
    exit $?
fi

models_json="$(curl -s --max-time "${TIMEOUT}" "${INFERENCE_URL}/v1/models" 2>/dev/null || echo '{}')"
if echo "${models_json}" | python3 -c \
    "import json,sys; d=json.load(sys.stdin); ids=[m['id'] for m in d.get('data',[])]; print('\n'.join(ids)); sys.exit(0 if ids else 1)" 2>/dev/null; then
    pass "/v1/models returns model list"
else
    fail "/v1/models returns model list" "response: ${models_json:0:200}"
fi

request='{"model":"'"${MODEL}"'","messages":[{"role":"user","content":"Reply with exactly one token: OK"}],"max_tokens":8,"temperature":0}'
response='{}'

# The very first completion after startup can occasionally return an empty
# body while the engine finishes warm paths. Retry a few times.
for _ in 1 2 3; do
    response="$(curl -s --max-time "${TIMEOUT}" -H 'Content-Type: application/json' -d "${request}" "${INFERENCE_URL}/v1/chat/completions" 2>/dev/null || echo '{}')"
    if echo "${response}" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('choices') else 1)" 2>/dev/null; then
        break
    fi
done

finish_reason="$(echo "${response}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['choices'][0]['finish_reason'])" 2>/dev/null || echo '')"
content="$(echo "${response}" | python3 -c "import json,sys; d=json.load(sys.stdin); m=d['choices'][0].get('message',{}); txt=m.get('content') or m.get('reasoning_content') or m.get('reasoning') or ''; print(txt if txt is not None else '')" 2>/dev/null || echo '')"

if [[ -n "${content}" ]]; then
    pass "chat completion returns content"
    printf '     model reply: %s\n' "${content}"
else
    fail "chat completion returns content" "response: ${response:0:300}"
fi

if [[ "${finish_reason}" == "stop" || "${finish_reason}" == "length" ]]; then
    pass "finish_reason is stop or length (got: ${finish_reason})"
else
    fail "finish_reason is stop or length" "got: '${finish_reason}'"
fi

req2='{"model":"'"${MODEL}"'","messages":[{"role":"system","content":"You are a concise AI assistant."},{"role":"user","content":"What does NVIDIA stand for? Answer in one sentence."}],"max_tokens":80,"temperature":0}'
resp2="$(curl -s --max-time "${TIMEOUT}" -H 'Content-Type: application/json' -d "${req2}" "${INFERENCE_URL}/v1/chat/completions" 2>/dev/null || echo '{}')"
content2="$(echo "${resp2}" | python3 -c "import json,sys; d=json.load(sys.stdin); m=d['choices'][0].get('message',{}); txt=m.get('content') or m.get('reasoning_content') or m.get('reasoning') or ''; print(txt if txt is not None else '')" 2>/dev/null || echo '')"
if [[ -n "${content2}" ]]; then
    pass "factual reasoning test returns content"
    printf '     model reply: %s\n' "${content2}"
else
    fail "factual reasoning test returns content" "${resp2:0:220}"
fi

usage="$(echo "${response}" | python3 -c "import json,sys; d=json.load(sys.stdin); u=d.get('usage',{}); print(u.get('prompt_tokens',0))" 2>/dev/null || echo '0')"
if [[ "${usage}" -le 0 ]]; then
    usage="$(echo "${resp2}" | python3 -c "import json,sys; d=json.load(sys.stdin); u=d.get('usage',{}); print(u.get('prompt_tokens',0))" 2>/dev/null || echo '0')"
fi
if [[ "${usage}" -gt 0 ]]; then
    pass "token usage reported (prompt_tokens=${usage})"
else
    fail "token usage reported" "usage field missing or zero"
fi

suite_done
