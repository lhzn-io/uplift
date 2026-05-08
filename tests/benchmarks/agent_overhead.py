#!/usr/bin/env python3
"""
tests/benchmarks/agent_overhead.py — zeroclaw agent round-trip vs bare vLLM.

Measures the cost the zeroclaw agent loop adds on top of the raw model server
for a minimal prompt ("say hello"). The dominant component is prefill of the
agent's default system prompt (tool schemas, agent instructions, session
state), so this benchmark is the regression signal for prompt-surgery work.

Outputs two artifacts under tests/benchmarks/results/:
  - agent_overhead_latest.json           (overwritten; easy to diff vs HEAD)
  - agent_overhead_<UTC timestamp>.json  (archived; one per run)

Usage:
  python3 tests/benchmarks/agent_overhead.py                 # N=10
  python3 tests/benchmarks/agent_overhead.py --iterations 30
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import statistics
import subprocess
import sys
import time
import urllib.error
import urllib.request

PROMPT = "say hello"
INFERENCE_URL_DEFAULT = "http://127.0.0.1:8000"
CONTAINER_DEFAULT = "uplift-zeroclaw-1"
MAX_TOKENS = 8
TEMPERATURE = 0.0


def get_json(url: str, timeout: float = 30.0) -> dict:
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return json.loads(r.read())


def post_json(url: str, body: dict, timeout: float = 120.0) -> tuple[dict, float]:
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        url, data=data, headers={"Content-Type": "application/json"}
    )
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read()), time.monotonic() - t0
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"vLLM HTTP {e.code}: {e.read().decode(errors='replace')[:200]}") from e


def get_metrics(inference_url: str, model: str) -> dict[str, float]:
    """Snapshot vLLM Prometheus counters for the target model."""
    with urllib.request.urlopen(f"{inference_url}/metrics", timeout=10) as r:
        raw = r.read().decode()
    out: dict[str, float] = {}
    wanted = {
        "vllm:prompt_tokens_total": "prompt_tokens",
        "vllm:generation_tokens_total": "generation_tokens",
    }
    for line in raw.splitlines():
        if not line or line.startswith("#"):
            continue
        for metric, label in wanted.items():
            if line.startswith(metric) and f'model_name="{model}"' in line:
                try:
                    out[label] = float(line.rsplit(" ", 1)[1])
                except ValueError:
                    pass
    # Count successful requests for this model, across all finish reasons
    succ = 0.0
    for line in raw.splitlines():
        if line.startswith("vllm:request_success_total") and f'model_name="{model}"' in line:
            try:
                succ += float(line.rsplit(" ", 1)[1])
            except ValueError:
                pass
    out["request_success"] = succ
    return out


def detect_model(inference_url: str) -> str:
    data = get_json(f"{inference_url}/v1/models")
    items = data.get("data") or []
    if not items:
        raise RuntimeError(f"{inference_url}/v1/models returned no models")
    return items[0]["id"]


def warmup_vllm(inference_url: str, model: str) -> None:
    post_json(
        f"{inference_url}/v1/chat/completions",
        {
            "model": model,
            "messages": [{"role": "user", "content": "warm"}],
            "max_tokens": 4,
            "temperature": 0.0,
        },
        timeout=60,
    )


def bench_direct(inference_url: str, model: str, iterations: int) -> list[dict]:
    rows = []
    for i in range(1, iterations + 1):
        resp, latency = post_json(
            f"{inference_url}/v1/chat/completions",
            {
                "model": model,
                "messages": [{"role": "user", "content": PROMPT}],
                "max_tokens": MAX_TOKENS,
                "temperature": TEMPERATURE,
            },
        )
        usage = resp.get("usage", {})
        rows.append(
            {
                "iter": i,
                "latency_s": round(latency, 4),
                "prompt_tokens": usage.get("prompt_tokens"),
                "completion_tokens": usage.get("completion_tokens"),
            }
        )
        print(
            f"  direct #{i:02d}  {latency:6.3f}s  "
            f"prompt={usage.get('prompt_tokens')} completion={usage.get('completion_tokens')}"
        )
    return rows


def bench_agent(
    container: str, inference_url: str, model: str, iterations: int
) -> list[dict]:
    rows = []
    for i in range(1, iterations + 1):
        before = get_metrics(inference_url, model)
        t0 = time.monotonic()
        proc = subprocess.run(
            ["docker", "exec", container, "zeroclaw", "agent", "-m", PROMPT],
            capture_output=True,
            text=True,
            timeout=120,
        )
        latency = time.monotonic() - t0
        after = get_metrics(inference_url, model)

        d_prompt = int(round(after["prompt_tokens"] - before["prompt_tokens"]))
        d_gen = int(round(after["generation_tokens"] - before["generation_tokens"]))
        d_req = int(round(after["request_success"] - before["request_success"]))
        reply_tail = (proc.stdout.splitlines()[-1] if proc.stdout.strip() else "").strip()[:100]

        rows.append(
            {
                "iter": i,
                "latency_s": round(latency, 4),
                "vllm_calls": d_req,
                "prompt_tokens": d_prompt,
                "completion_tokens": d_gen,
                "cli_exit": proc.returncode,
                "reply_preview": reply_tail,
            }
        )
        print(
            f"  agent  #{i:02d}  {latency:6.3f}s  "
            f"calls={d_req} prompt={d_prompt} completion={d_gen}  :: {reply_tail!r}"
        )
    return rows


def summarize(rows: list[dict], key: str) -> dict:
    xs = [r[key] for r in rows if isinstance(r.get(key), (int, float))]
    if not xs:
        return {}
    xs_sorted = sorted(xs)
    return {
        "n": len(xs),
        "mean": round(statistics.mean(xs), 4),
        "median": round(statistics.median(xs), 4),
        "stdev": round(statistics.stdev(xs), 4) if len(xs) > 1 else 0.0,
        "min": round(min(xs), 4),
        "max": round(max(xs), 4),
        "p95": round(xs_sorted[max(0, int(0.95 * len(xs_sorted)) - 1)], 4),
    }


def short_sha(cwd: str) -> str | None:
    try:
        out = subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"], cwd=cwd, stderr=subprocess.DEVNULL
        )
        return out.decode().strip()
    except Exception:
        return None


def dirty_tree(cwd: str) -> bool | None:
    try:
        subprocess.check_output(
            ["git", "diff", "--quiet"], cwd=cwd, stderr=subprocess.DEVNULL
        )
        return False
    except subprocess.CalledProcessError:
        return True
    except Exception:
        return None


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    p.add_argument("--iterations", "-n", type=int, default=10)
    p.add_argument("--inference-url", default=os.environ.get("INFERENCE_URL", INFERENCE_URL_DEFAULT))
    p.add_argument("--container", default=os.environ.get("ZEROCLAW_CONTAINER", CONTAINER_DEFAULT))
    p.add_argument("--model", default=os.environ.get("VLLM_SERVED_MODEL_NAME"))
    p.add_argument(
        "--out-dir",
        default=os.path.join(os.path.dirname(__file__), "results"),
    )
    args = p.parse_args()

    model = args.model or detect_model(args.inference_url)
    repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

    print(f"model:          {model}")
    print(f"inference_url:  {args.inference_url}")
    print(f"container:      {args.container}")
    print(f"iterations:     {args.iterations}\n")

    print("warming vLLM …")
    warmup_vllm(args.inference_url, model)

    print("\n== direct vLLM ==")
    direct_rows = bench_direct(args.inference_url, model, args.iterations)

    print("\n== zeroclaw agent ==")
    agent_rows = bench_agent(args.container, args.inference_url, model, args.iterations)

    direct_lat = summarize(direct_rows, "latency_s")
    direct_pt = summarize(direct_rows, "prompt_tokens")
    agent_lat = summarize(agent_rows, "latency_s")
    agent_pt = summarize(agent_rows, "prompt_tokens")

    overhead_mean = round(agent_lat["mean"] - direct_lat["mean"], 4)
    prompt_ratio = (
        round(agent_pt["mean"] / direct_pt["mean"], 2)
        if direct_pt.get("mean")
        else None
    )

    result = {
        "schema_version": 1,
        "run_id_utc": dt.datetime.utcnow().strftime("%Y%m%dT%H%M%SZ"),
        "git": {
            "short_sha": short_sha(repo_root),
            "dirty": dirty_tree(repo_root),
        },
        "stack": {
            "inference_url": args.inference_url,
            "container": args.container,
            "model": model,
        },
        "params": {
            "iterations": args.iterations,
            "prompt": PROMPT,
            "max_tokens": MAX_TOKENS,
            "temperature": TEMPERATURE,
        },
        "direct_vllm": {
            "latency_s": direct_lat,
            "prompt_tokens": direct_pt,
            "completion_tokens": summarize(direct_rows, "completion_tokens"),
            "rows": direct_rows,
        },
        "zeroclaw_agent": {
            "latency_s": agent_lat,
            "prompt_tokens": agent_pt,
            "completion_tokens": summarize(agent_rows, "completion_tokens"),
            "vllm_calls_per_turn": summarize(agent_rows, "vllm_calls"),
            "rows": agent_rows,
        },
        "overhead": {
            "latency_mean_s": overhead_mean,
            "latency_fraction_of_agent": round(overhead_mean / agent_lat["mean"], 3)
            if agent_lat.get("mean")
            else None,
            "prompt_token_ratio": prompt_ratio,
        },
    }

    os.makedirs(args.out_dir, exist_ok=True)
    archive = os.path.join(args.out_dir, f"agent_overhead_{result['run_id_utc']}.json")
    latest = os.path.join(args.out_dir, "agent_overhead_latest.json")
    with open(archive, "w") as f:
        json.dump(result, f, indent=2)
    with open(latest, "w") as f:
        json.dump(result, f, indent=2)

    print("\n== summary ==")
    print(
        f"  direct vLLM:     mean={direct_lat['mean']:.3f}s  "
        f"prompt_tokens_mean={direct_pt['mean']:.0f}"
    )
    print(
        f"  zeroclaw agent:  mean={agent_lat['mean']:.3f}s  "
        f"prompt_tokens_mean={agent_pt['mean']:.0f}"
    )
    print(
        f"  overhead:        {overhead_mean:+.3f}s "
        f"({result['overhead']['latency_fraction_of_agent']:.1%} of agent round-trip)"
    )
    print(f"  prompt-token bloat factor: {prompt_ratio}×")
    print(f"\n  archive: {archive}")
    print(f"  latest:  {latest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
