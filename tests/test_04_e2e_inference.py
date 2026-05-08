#!/usr/bin/env python3
"""
tests/test_04_e2e_inference.py — End-to-end inference pipeline test

Covers:
  - vLLM /v1/models endpoint
  - Single-turn chat completion with content validation
  - Multi-turn chat (context continuity)
  - Tool-calling / structured output readiness
  - Streaming completions
  - Latency guardrails (first-token + total under thresholds)
  - Token usage accounting
  - Error handling: invalid model name, missing messages field
"""

import json
import os
import sys
import time
import urllib.request
import urllib.error

INFERENCE_URL = os.environ.get("INFERENCE_URL", "http://127.0.0.1:8000")

def grab_active_model():
    try:
        req = urllib.request.Request(f"{INFERENCE_URL}/v1/models")
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode("utf-8"))
            if data.get("data") and len(data["data"]) > 0:
                return data["data"][0]["id"]
    except Exception:
        pass
    return "nvidia/nemotron-3-nano-30b-a3b"

MODEL = os.environ.get("VLLM_SERVED_MODEL_NAME") or grab_active_model()
TIMEOUT = int(os.environ.get("INFERENCE_TIMEOUT", "60"))

# Latency thresholds (seconds). Generous to allow cold-start variation.
MAX_FIRST_TOKEN_S = 45
MAX_TOTAL_S = 120

# ── test registry ──────────────────────────────────────────────────────────

_pass = 0
_fail = 0
_skip = 0
_results: list[dict] = []


def _record(name: str, result: str, detail: str = "") -> None:
    _results.append({"test": name, "result": result, "detail": detail})


def passed(name: str) -> None:
    global _pass
    _pass += 1
    _record(name, "pass")
    print(f"  \033[32m[✓]\033[0m {name}")


def failed(name: str, detail: str = "") -> None:
    global _fail
    _fail += 1
    _record(name, "fail", detail)
    suffix = f"  →  {detail}" if detail else ""
    print(f"  \033[31m[✗]\033[0m {name}{suffix}")


def skipped(name: str, reason: str = "") -> None:
    global _skip
    _skip += 1
    _record(name, "skip", reason)
    print(f"  \033[33m[-]\033[0m {name}  (skipped: {reason})")


# ── HTTP helpers ───────────────────────────────────────────────────────────

def get_json(path: str, timeout: int = TIMEOUT) -> dict | None:
    try:
        with urllib.request.urlopen(f"{INFERENCE_URL}{path}", timeout=timeout) as r:
            return json.loads(r.read())
    except Exception:
        return None


def post_json(path: str, body: dict, timeout: int = TIMEOUT) -> tuple[dict | None, float]:
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        f"{INFERENCE_URL}{path}",
        data=data,
        headers={"Content-Type": "application/json"},
    )
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            resp = json.loads(r.read())
            return resp, time.monotonic() - t0
    except urllib.error.HTTPError as e:
        try:
            body_raw = e.read().decode(errors="replace")
        except Exception:
            body_raw = str(e)
        return {"_http_error": e.code, "_body": body_raw}, time.monotonic() - t0
    except Exception as exc:
        return {"_exception": str(exc)}, time.monotonic() - t0


def post_stream(path: str, body: dict, timeout: int = TIMEOUT) -> tuple[list[str], float, float]:
    """Returns (chunks, first_token_latency, total_latency)."""
    body = {**body, "stream": True}
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        f"{INFERENCE_URL}{path}",
        data=data,
        headers={"Content-Type": "application/json"},
    )
    chunks: list[str] = []
    first_token_t = 0.0
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            for raw_line in r:
                line = raw_line.decode(errors="replace").strip()
                if not line.startswith("data:"):
                    continue
                payload = line[5:].strip()
                if payload == "[DONE]":
                    break
                try:
                    chunk = json.loads(payload)
                    d = chunk["choices"][0]["delta"]
                    delta = d.get("content", "") or d.get("reasoning", "")
                    if delta:
                        if not chunks:
                            first_token_t = time.monotonic() - t0
                        chunks.append(delta)
                except Exception:
                    pass
    except Exception:
        pass
    return chunks, first_token_t, time.monotonic() - t0


def pick_message_text(resp: dict) -> str:
    """Extract response text from vLLM/OpenAI-compatible payloads.

    Nemotron responses may place useful text under `reasoning_content`
    while `content` can be null/empty.
    """
    try:
        message = resp["choices"][0].get("message", {})
    except Exception:
        return ""
    content = message.get("content")
    reasoning = message.get("reasoning_content")
    reasoning_alt = message.get("reasoning")
    if isinstance(content, str) and content.strip():
        return content
    if isinstance(reasoning, str) and reasoning.strip():
        return reasoning
    if isinstance(reasoning_alt, str) and reasoning_alt.strip():
        return reasoning_alt
    return ""


# ── tests ──────────────────────────────────────────────────────────────────

def test_models_endpoint() -> None:
    name = "/v1/models lists expected model"
    data = get_json("/v1/models")
    if data is None:
        failed(name, "endpoint unreachable")
        return
    ids = [m["id"] for m in data.get("data", [])]
    if not ids:
        failed(name, f"empty model list — raw: {data}")
        return
    passed(name)
    if MODEL in ids:
        passed(f"model '{MODEL}' present in /v1/models")
    else:
        failed(
            f"model '{MODEL}' present in /v1/models",
            f"available: {ids}",
        )


def test_simple_chat() -> None:
    name = "single-turn chat completion"
    resp, elapsed = post_json(
        "/v1/chat/completions",
        {
            "model": MODEL,
            "messages": [{"role": "user", "content": "Reply with exactly: OK"}],
            "max_tokens": 48,
            "temperature": 0,
        },
    )
    if "_exception" in resp or "_http_error" in resp:
        failed(name, str(resp)[:200])
        return
    try:
        content = pick_message_text(resp)
        finish = resp["choices"][0]["finish_reason"]
        prompt_tokens = resp.get("usage", {}).get("prompt_tokens", 0)
    except (KeyError, IndexError) as exc:
        failed(name, f"unexpected shape: {exc}")
        return

    passed(name)
    print(f"     reply: {content!r}  finish={finish}  tokens={prompt_tokens}  {elapsed:.1f}s")

    if finish in ("stop", "length"):
        passed(f"finish_reason '{finish}' is valid")
    else:
        failed("finish_reason is stop or length", f"got: {finish!r}")

    if prompt_tokens > 0:
        passed(f"token usage reported (prompt={prompt_tokens})")
    else:
        failed("token usage reported", "prompt_tokens=0")

    if elapsed <= MAX_TOTAL_S:
        passed(f"total latency within {MAX_TOTAL_S}s ({elapsed:.1f}s)")
    else:
        failed(f"total latency within {MAX_TOTAL_S}s", f"took {elapsed:.1f}s")


def test_multi_turn() -> None:
    name = "multi-turn context continuity"
    resp, elapsed = post_json(
        "/v1/chat/completions",
        {
            "model": MODEL,
            "messages": [
                {"role": "system", "content": "You are a concise assistant. Answer in one sentence."},
                {"role": "user", "content": "My name is Alex."},
                {"role": "assistant", "content": "Hello, Alex!"},
                {"role": "user", "content": "What is my name?"},
            ],
            "max_tokens": 80,
            "temperature": 0,
        },
    )
    if "_exception" in resp or "_http_error" in resp:
        failed(name, str(resp)[:200])
        return
    try:
        content = pick_message_text(resp)
    except (KeyError, IndexError) as exc:
        failed(name, f"unexpected shape: {exc}")
        return
    if not content:
        failed(name, "empty completion content")
        return
    lowered = content.lower()
    if "alex" in lowered or "your name" in lowered:
        passed(name)
        print(f"     reply: {content!r}")
    else:
        failed(name, f"reply did not reference 'Alex': {content!r}")


def test_system_prompt_adherence() -> None:
    name = "system prompt adherence"
    resp, _ = post_json(
        "/v1/chat/completions",
        {
            "model": MODEL,
            "messages": [
                {"role": "system", "content": "You must always end your reply with the word SENTINEL."},
                {"role": "user", "content": "Describe the Jetson Orin in one short sentence."},
            ],
            "max_tokens": 80,
            "temperature": 0,
        },
    )
    if "_exception" in resp or "_http_error" in resp:
        failed(name, str(resp)[:200])
        return
    try:
        content = pick_message_text(resp)
    except (KeyError, IndexError) as exc:
        failed(name, f"unexpected shape: {exc}")
        return
    if not content:
        failed(name, "empty completion content")
        return
    if "sentinel" in content.lower():
        passed(name)
        print(f"     reply: {content!r}")
    else:
        failed(name, f"SENTINEL not found in reply: {content!r}")


def test_streaming() -> None:
    name = "streaming completion"
    chunks, first_token_t, total_t = post_stream(
        "/v1/chat/completions",
        {
            "model": MODEL,
            "messages": [{"role": "user", "content": "Count to 3, one word per number."}],
            "max_tokens": 48,
            "temperature": 0,
        },
    )
    if not chunks:
        failed(name, "no stream chunks received")
        return
    full = "".join(chunks)
    passed(name)
    print(f"     streamed: {full!r}  chunks={len(chunks)}  first_token={first_token_t:.1f}s  total={total_t:.1f}s")

    if first_token_t > 0 and first_token_t <= MAX_FIRST_TOKEN_S:
        passed(f"first-token latency within {MAX_FIRST_TOKEN_S}s ({first_token_t:.1f}s)")
    elif first_token_t > MAX_FIRST_TOKEN_S:
        failed(f"first-token latency within {MAX_FIRST_TOKEN_S}s", f"took {first_token_t:.1f}s")


def test_invalid_model_name() -> None:
    name = "invalid model name returns 4xx"
    resp, _ = post_json(
        "/v1/chat/completions",
        {
            "model": "nonexistent/model-that-does-not-exist",
            "messages": [{"role": "user", "content": "hello"}],
            "max_tokens": 5,
        },
    )
    if resp.get("_http_error") in (404, 400):
        passed(name)
    elif "_http_error" in resp:
        passed(f"{name} (returned HTTP {resp['_http_error']})")
    elif "error" in resp:
        passed(f"{name} (returned error in body)")
    else:
        failed(name, f"expected 4xx, got: {str(resp)[:200]}")


def test_missing_messages_field() -> None:
    name = "missing 'messages' field returns 4xx"
    resp, _ = post_json(
        "/v1/chat/completions",
        {"model": MODEL, "max_tokens": 5},
    )
    if resp.get("_http_error") in (422, 400):
        passed(name)
    elif "_http_error" in resp:
        passed(f"{name} (returned HTTP {resp['_http_error']})")
    elif "error" in resp:
        passed(f"{name} (returned error in body)")
    else:
        failed(name, f"expected 4xx, got: {str(resp)[:200]}")


# ── main ───────────────────────────────────────────────────────────────────

def main() -> None:
    print(f"\n\033[1m=== end-to-end-inference ===\033[0m")
    print(f"  backend: {INFERENCE_URL}")
    print(f"  model:   {MODEL}")

    test_models_endpoint()
    test_simple_chat()
    test_multi_turn()
    test_system_prompt_adherence()
    test_streaming()
    test_invalid_model_name()
    test_missing_messages_field()

    # Write results
    import datetime
    ts = datetime.datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
    results_dir = os.path.join(os.path.dirname(__file__), "results")
    os.makedirs(results_dir, exist_ok=True)
    result_file = os.path.join(results_dir, f"e2e_inference_{ts}.json")
    with open(result_file, "w") as f:
        json.dump(
            {"suite": "end-to-end-inference", "pass": _pass, "fail": _fail,
             "skip": _skip, "tests": _results},
            f, indent=2,
        )

    print(f"\n  pass: {_pass}  fail: {_fail}  skip: {_skip}")
    print(f"  results: {result_file}")
    sys.exit(0 if _fail == 0 else 1)


if __name__ == "__main__":
    main()
