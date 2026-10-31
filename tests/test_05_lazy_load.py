#!/usr/bin/env python3
"""
tests/test_05_lazy_load.py — Functional test of the native deferred-loading
path: an agent prompt that requires a deferred tool must successfully invoke
`tool_search`, activate the right tool, and produce a substantive response.

This sits alongside `tests/benchmarks/agent_overhead.py` (which measures
prompt-token regression) and complements `verify_stack.sh` (which exercises
the stack but bypasses the agent loop). None of those positively assert that
the lazy-load code path *functionally* works — that's this test's job.

Assertions:

  1. The agent invokes `tool_search` during the turn (proves the deferred
     stub list in the system prompt is actually being consumed).
  2. The agent loop runs a multi-step turn (>=2 vLLM calls), evidence that
     a tool was activated and then called.
  3. The agent's reply is substantive (not a refusal / not empty).

Run:
  python3 tests/test_05_lazy_load.py
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import time
import urllib.request

CONTAINER = os.environ.get("ZEROCLAW_CONTAINER", "uplift-zeroclaw-operator-1")
INFERENCE_URL = os.environ.get("INFERENCE_URL", "http://127.0.0.1:8100")
MODEL = os.environ.get("VLLM_SERVED_MODEL_NAME", "gemma-4-26b-a4b")

AGENT = os.environ.get("ZEROCLAW_AGENT", "default")

# Prompt designed to *require* a deferred native tool. cron_list is deferred by
# deferred_builtin_tools and works offline (web_search would need a search API
# key). Naming the tool biases the model toward the lazy-load path
# (tool_search, then cron_list), which is what we want to exercise.
PROMPT = (
    "Use the cron_list tool to list the scheduled jobs, then reply with one "
    "full sentence stating how many scheduled jobs exist."
)

# ZeroClaw v0.8.5 prints recorded logs on the terminal only with --verbose, and
# --log-level debug records the tool_search activation lines this test parses.
# Log lines are prefixed with "[system]".
LOG_PREFIX = "[system]"
ANSI = re.compile(r"\x1b\[[0-9;]*m")  # log lines carry colour codes


# Since ZeroClaw v0.8.6 a standalone `zeroclaw agent` refuses to start while the agent daemon in the container
# owns the config state, so a one-shot turn runs on a scratch copy of the agent's config (same model, tools,
# MCP servers and UPLIFT_TRACE_PATH; separate sessions and memory).
def oneshot_cmd(container: str, agent_args: list[str], zeroclaw_flags: list[str] = ()) -> list[str]:
    import shlex

    run = " ".join(shlex.quote(a) for a in ["zeroclaw", "--config-dir", "/tmp/zc-oneshot", *zeroclaw_flags, *agent_args])
    script = (
        "set -e; src=/zeroclaw-data/.zeroclaw; rm -rf /tmp/zc-oneshot; mkdir -p /tmp/zc-oneshot; "
        "cp $src/config.toml $src/.secret_key /tmp/zc-oneshot/; "
        "[ -f $src/identity.json ] && cp $src/identity.json /tmp/zc-oneshot/; "
        f"cd /tmp && exec {run}"
    )
    return ["docker", "exec", container, "sh", "-c", script]


def vllm_request_count() -> float:
    """Sum vllm:request_success_total across all finish_reason labels."""
    total = 0.0
    with urllib.request.urlopen(f"{INFERENCE_URL}/metrics", timeout=10) as r:
        for line in r.read().decode().splitlines():
            if (
                line.startswith("vllm:request_success_total")
                and f'model_name="{MODEL}"' in line
            ):
                try:
                    total += float(line.rsplit(" ", 1)[1])
                except (IndexError, ValueError):
                    continue
    return total


def main() -> int:
    print("=" * 60)
    print("test_05_lazy_load — functional deferred-loading assertion")
    print("=" * 60)
    print(f"  container:     {CONTAINER}")
    print(f"  inference_url: {INFERENCE_URL}")
    print(f"  model:         {MODEL}")

    requests_before = vllm_request_count()
    print(f"\n  vLLM successful requests before: {requests_before:.0f}")

    print(f"\n  prompt: {PROMPT}")
    print("  invoking agent (timeout 120s) …")
    t0 = time.monotonic()
    try:
        proc = subprocess.run(
            oneshot_cmd(CONTAINER, ["agent", "--agent", AGENT, "-m", PROMPT],
                        ["--verbose", "--log-level", "debug"]),
            capture_output=True,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        print("\n  FAIL — agent timed out at 120s")
        return 1
    elapsed = time.monotonic() - t0

    requests_after = vllm_request_count()
    delta = int(requests_after - requests_before)

    stdout = proc.stdout
    stderr = proc.stderr
    # With --verbose, log lines ("[system] ...") and the agent's reply share
    # the terminal; the reply is the last non-log line.
    reply_tail = ""
    for line in reversed(stdout.splitlines()):
        if line.strip() and not line.lstrip().startswith(LOG_PREFIX):
            reply_tail = line.strip()
            break

    print(f"\n  agent finished in {elapsed:.1f}s (exit {proc.returncode})")
    print(f"  vLLM successful requests after:  {requests_after:.0f}  (Δ={delta})")
    print(f"  agent reply tail: {reply_tail[:300]!r}")

    fails: list[str] = []

    # 1. Agent didn't crash.
    if proc.returncode != 0:
        fails.append(
            f"agent exited {proc.returncode}; stderr tail: "
            f"{stderr[-400:].strip()!r}"
        )

    # 2. tool_search was invoked AND activated at least one tool.
    # The debug line lands in stdout (alongside the agent reply) and looks like
    #   tool_search select: requested=1, activated=1, not_found=0
    # or
    #   tool_search: query="...", matched=N, activated=K
    haystack = stdout + "\n" + stderr
    # ZeroClaw v0.8.7 logs "tool_search select: requested=R, activated=A, not_found=N". A deferred built-in
    # tool (cron_list here) is returned from the built-in schema set without counting as activated, which
    # counts newly loaded MCP tools only; so the path is engaged when any requested schema was returned.
    select = re.search(
        r"tool_search select: requested=(\d+), activated=(\d+), not_found=(\d+)", ANSI.sub("", haystack))
    if select and (int(select.group(1)) > int(select.group(3)) or int(select.group(2)) >= 1):
        print(
            f"\n  ✓ tool_search select returned a deferred schema "
            f"(requested={select.group(1)}, activated={select.group(2)}, not_found={select.group(3)})"
        )
    else:
        # Surface a snippet so failing runs are debuggable.
        snippet = "\n    ".join(
            line for line in stdout.splitlines()[-30:] if line.strip()
        )
        fails.append(
            "tool_search was not invoked (or did not activate any tool) "
            "during the turn. Either the deferred-tools section in the system "
            "prompt is not being consumed, or the model decided to bypass "
            "the lazy-load path. stdout tail:\n    "
            f"{snippet}"
        )

    # 3. Multi-step agent loop — at least 2 vLLM calls in the turn.
    # A non-tool-using turn would be 1; a turn that uses one deferred tool
    # via tool_search → activated_tool → response is typically 3+.
    if delta >= 2:
        print(f"  ✓ multi-step agent loop fired ({delta} vLLM calls)")
    else:
        fails.append(
            f"only {delta} vLLM call(s) in the turn; expected >=2 for a "
            f"tool-using turn. Either the agent answered without calling any "
            f"tool, or the metric scrape race-conditioned with the request."
        )

    # 4. Response is substantive (not a refusal / not empty).
    refusal_signals = (
        "i cannot", "i am unable", "i don't have access", "i can't access",
        "i don't have the ability", "i'm unable",
    )
    looks_like_refusal = any(s in reply_tail.lower() for s in refusal_signals)
    # The cron_list answer is one short sentence ("There are 0 scheduled jobs.").
    if len(reply_tail) >= 15 and not looks_like_refusal:
        print(f"  ✓ response is substantive ({len(reply_tail)} chars, not a refusal)")
    else:
        fails.append(
            f"response looks like a refusal or empty (length={len(reply_tail)}): "
            f"{reply_tail[:300]!r}"
        )

    print()
    if fails:
        print("  FAIL — assertions did not hold:")
        for i, f in enumerate(fails, 1):
            print(f"    {i}. {f}")
        return 1
    print("  PASS — lazy-load path is functionally correct.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
