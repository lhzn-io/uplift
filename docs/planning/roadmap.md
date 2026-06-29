# Uplift Core Roadmap

The strategic framing for this roadmap lives in
[`../methodology.md`](../methodology.md). Every milestone below is
either *shipped*, *next* (committed), or *later* (parked until the
preceding rows land). We do not list aspirational work for its own
sake.

## Shipped

### v0.1 — bootstrap

- **Sovereign inference default.** Single-node vLLM with Gemma4-26B as
  default, with Gemma4-12B and Nemotron-3-Nano as options (via `./start_stack.sh --model <alias>`). Config template, env helper, and docker-compose all
  driven from a single source of truth at
  [`scripts/env.sh`](../../scripts/env.sh).
- **Trim pass on the agent prompt.** System-prompt tokens per turn
  cut from 10,380 → ~7,050 (−32%), round-trip 6.68 s → ~4.31 s
  (−35%), measured reproducibly via
  [`tests/benchmarks/agent_overhead.py`](../../tests/benchmarks/agent_overhead.py).
  The cuts live in two forks:
  - Config: [`configs/zeroclaw.toml.template`](../../configs/zeroclaw.toml.template)
    (skills compact mode, browser off, MCP deferred, integration
    catalog cleanup).
  - ZeroClaw runtime: `lhzn-io/zeroclaw @ uplift-core` —
    17 unconditional tool registrations pruned from the LLM schema.
- **Local GPU/CUDA telemetry surface.** The `jetson-status` skill
  reads tegrastats / thermal zones / nvpmodel directly via the agent's
  built-in shell tool; no MCP server required.
- **Verification harness** — `./scripts/verify_stack.sh` plus the
  test suite (`tests/test_*.sh`, `test_04_e2e_inference.py`) and the
  regression benchmark at `tests/benchmarks/`.
- **Operator UX basics** — one-shot agent CLI, Slack channel,
  browser dashboard (paired via `zeroclaw gateway get-paircode`),
  neuralyzer state-wipe utility.

### v0.2 — completed

- **W1: Lazy-load native tools** (parent commit `0d1b777`,
  fork commit `lhzn-io/zeroclaw@b1bb4ee1`). Native tools tagged
  for deferral by `is_eager_native_tool()` register as stubs in
  the system prompt's `<available-deferred-tools>` block; the
  LLM activates their full schemas on demand by calling
  `tool_search`. The pattern mirrors the existing
  `DeferredMcpToolSet`.
- **W2: `on_turn_complete` hook + `UpliftObserver`.** Generic
  void-hook in the zeroclaw fork firing a neutral `TurnRecord`. 
  Parent-side `UpliftObserver` consumes the hook and writes JSONL 
  with treatment labels. Second writer of trace data; complements 
  the proxy for tool-call attribution.
- **W3: `crates/uplift` trace schema & analysis.** `TraceRecord` type
  with JSONL reader, Parquet writer (via `arrow`/`parquet` crates),
  `naive_ate` estimator, and `uplift-trace convert <jsonl> <parquet>` CLI.
- **W4: `python/uplift` package.** `pyproject.toml` (uv-managed), `read_parquet`,
  `naive_ate`, thin wrappers over causal estimators behind feature flags,
  and the `uplift` CLI for real traces.
- **W5: vLLM instrumentation proxy.** Python FastAPI proxy on `:8100` forwarding
  to vLLM on `:8000`, capturing every `/v1/chat/completions` request + response
  and emitting one JSONL trace record per request to `state/uplift-trace.jsonl`.
- **W6: Release reporting and Anchor Docs.** `docs/deployments/aquaculture.md` and 
  `docs/deployments/food-bank.md` deployed definitions. `release_report.py` entry point 
  plus `generate_release_report.sh` wrapper to upload the markdown summary via `gh release edit`.
- **Functional lazy-load assertion** — `tests/test_05_lazy_load.py` proves
  `tool_search` activates a deferred tool. Wired into `scripts/verify_stack.sh`.
- **Verified Scale**: Round-trip mean optimized to ~3.29s, with prompt footprint clamped to ~6,584 tokens.

## Next (v0.3)

The base measurement pipeline is active. The next iteration focuses on actual 
engagement metrics, deeper model integration, and workflow capabilities:

- **Decant Aquaculture Expert Model.** Upgrade the `reasoning-engine` from default to `lhzn-io/imta-expert-gemma4-26b-a4b-it-awq` (an aquaculture expert model).
  - *Shipped*: 48.1 GB model weights consolidated into standard global cache path under `/home/lhzn/.cache/huggingface`.
  - *Shipped*: Bypassed vLLM `AttributeError` by mounting `patches/gemma4_patch.py` and `patches/gemma4_mm_patch.py` to mock `"vision_config"` and enable LoRA on multimodal Gemma 4 architectures.
  - *Shipped*: Resolved Marlin MoE loader constraint (`AssertionError: Only symmetric quantization is supported for MoE`) by applying standard MoE Marlin assertion bypass in `patches/fused_moe_patch.py` and configuring Triton MoE backend (`--moe-backend triton`) in `docker-compose.yml` environment.
  - *Shipped*: Integrated `scripts/zeroclaw_entrypoint.sh` to dynamically register the decanted expert model choices in the ZeroClaw Web UI.

## Later (v0.3+)

- **Literature review populated.** Sections §§1–6 of
  [`../methodology.md`](../methodology.md) filled in from a real
  academic pass (Ai2 Asta brief already lives in that document).
  Paper-by-paper "why this matters to us" notes.
- **Estimator interoperability.** Beyond the naive-ATE baseline,
  `uplift/` grows real integration points for scikit-uplift /
  upliftml / CausalML estimators — this is where the project
  genuinely becomes a downstream consumer rather than just
  rhetorically claiming to be one.
- **Operator skill pack for the sandboxed agent.** Narrowly-scoped
  deterministic skills (stack health diagnosis, safe recovery,
  reboot checklist) layered on top of the trimmed tool surface.
- **Browser-automation capability.** Read-only UI probes first,
  then guarded write actions.
- **MolmoWeb evaluation.** Decision gate between direct skill
  integration vs. a thin bridge layer — commits only after the
  v0.2 floor is in place.

## North Star (1 year from v0.1)

This is the bar Uplift Core holds itself to, not a speculative
forecast. Verbatim from the day-one position:

- The stack is deployed at **both** anchor sites with real
  operators.
- Each release reports a **causal Key Metric per site**, with
  confidence intervals, including the bad numbers.
- At least one external researcher from the causal-ML or human–AI-
  teaming community has engaged with the project — as a reviewer,
  collaborator, or co-author on a write-up.
- The `uplift/` module has matured from "naive ATE on two run sets"
  into a real bridge between agent traces and standard causal-ML
  estimators.
- The project can answer, with evidence, the question: **"did this
  stack lever up a human operator in the field, and for whom did it
  work best?"**

If we cannot answer that question by then, the mission has not been
delivered, regardless of how good the architecture is or how many
stars the repo has.

## Out of scope

- Re-introducing the legacy pre-fork orchestrator/vision container
  paths.
- Competing with `scikit-uplift` / `upliftml` / CausalML on
  estimator implementation.
- Aggregate agent-benchmark leaderboarding as a primary evaluation
  signal.
## Status: v0.2 completion finished
