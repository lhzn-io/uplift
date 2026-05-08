# User Guide

How to clone, build, run, interact with, and reset the Uplift stack on
a Jetson Orin AGX. For the strategic framing of the project see
[`../README.md`](../README.md); for the methodological backbone see
[`methodology.md`](methodology.md).

## Why the stack uses forks

One of the components is consumed as a submodule pointing at a fork
under `lhzn-io`:

- [`stack/zeroclaw`](../stack/zeroclaw) → `lhzn-io/zeroclaw` on branch
  `uplift-core`. We fork the upstream `zeroclaw-labs/zeroclaw` daemon
  because we carry operational changes that aren't universally useful
  (incremental-build Dockerfile / `.dockerignore`, a `base_url`-path
  schema fix, and the Cut-2 trim of always-registered tools that
  don't fit a single-provider vLLM deployment).

The submodule pointer in this repo pins an exact SHA on that fork
branch, so `git clone --recurse-submodules` always reproduces the
state the parent repo expects. Syncing upstream changes back into our
fork branch is an occasional, intentional act — see
[`../CONTRIBUTING.md`](../CONTRIBUTING.md#developing-with-the-zeroclaw-submodule-fork).

## Cloning

```bash
git clone --recurse-submodules git@github.com:lhzn-io/uplift.git
cd uplift

# If you already cloned without --recurse-submodules:
git submodule update --init --recursive
```

## Building the ZeroClaw daemon

Because we deploy on an edge device where compiling inside Docker is
prohibitively slow, the binary is compiled natively on the host and
then `COPY`'d into the container image.

```bash
./stack/build_zeroclaw.sh
```

This runs `cargo build --profile release-fast` in
`stack/zeroclaw/` and drops the binary at
`stack/zeroclaw/target/release-fast/zeroclaw`. Expect ~6–7 minutes
for a cold build on Orin AGX, ~1–2 minutes for incremental changes.

## Starting the stack

```bash
./start_stack.sh                    # Gemma4-26B-A4B (default)
./start_stack.sh --model nemotron   # Nemotron-3-Nano-30B-A3B
```

`start_stack.sh`:

1. Sources [`scripts/env.sh`](../scripts/env.sh) to export
   `VLLM_IMAGE` / `VLLM_MODEL` / `VLLM_SERVED_MODEL_NAME` / etc. for
   the chosen model.
2. Runs [`scripts/apply_config.sh`](../scripts/apply_config.sh) to
   regenerate `.zeroclaw/config.toml` from the template — the
   daemon's model name always matches what vLLM is actually serving.
3. Rebuilds the `zeroclaw:latest` image using the pre-compiled
   binary and launches `reasoning-engine` + `zeroclaw` via
   `docker compose`.

Stop with `./stop_stack.sh` (full stop) or
`./stop_stack.sh zeroclaw` (daemon-only; leaves vLLM warm).

## Pairing the dashboard

The browser UI at `http://127.0.0.1:42617` requires a one-time pairing
code. Generate one by invoking the daemon inside the container:

```bash
docker exec uplift-zeroclaw-1 zeroclaw gateway get-paircode --new
```

Open the dashboard, enter the 6-digit code it emits, and the browser
stores a token for subsequent connects.

For a remote tunnel from a laptop:

```bash
ssh -L 18790:127.0.0.1:42617 <jetson-host>
# then open http://localhost:18790/chat?session=main#token=<gateway_token>
```

## Using the agent

### One-shot from the command line

Useful for quick smoke tests and for anything scriptable:

```bash
docker exec uplift-zeroclaw-1 zeroclaw agent -m "What's the current GPU temperature?"
```

The agent answers via the `jetson-status` skill, which reads
tegrastats / thermal zones / nvpmodel directly through its built-in
shell tool. This is the same code path that the Slack channel and the
dashboard both dispatch through, so it's the cleanest single-turn
sanity check.

### Over Slack

If `[channels.slack] enabled = true` in the config template and
`SLACK_APP_TOKEN` / `SLACK_BOT_TOKEN` are set in `.env`, the daemon
listens in Socket Mode. Messaging the bot in Slack runs the same
agent loop as the CLI one-shot.

### Benchmarking the agent round-trip

After any non-trivial change to the config template or the zeroclaw
submodule, run the regression benchmark:

```bash
python3 tests/benchmarks/agent_overhead.py --iterations 10
```

Records prompt-token count, per-iteration latency, and
`mean / median / p95 / stdev` to
`tests/benchmarks/results/agent_overhead_<UTC>.json`, plus an
always-current `agent_overhead_latest.json` pointer. See the
`git log` on that directory for the cut-by-cut history.

## Verification harness

```bash
./scripts/verify_stack.sh
```

Runs host-prerequisite checks, inference reachability, zeroclaw
control-plane health, and an end-to-end chat completion. It sources
`scripts/env.sh` automatically, so you don't need to export VLLM_*
vars beforehand.

Useful subsets:

```bash
./scripts/verify_stack.sh --host-only
./scripts/verify_stack.sh --skip-e2e
```

Results land in `tests/results/` as JSON.

## Resetting agent state

When you want to start clean — wipe memory, sessions, and workspace
scratch without re-pairing the browser:

```bash
./scripts/neuralyzer.sh
```

(The name is a Men-in-Black reference: it *neuralyzes* the agent's
memory of prior interactions.) It stops the running daemon, removes
state files under `.zeroclaw/workspace/state/`, and is safe to run at
any time.

For a stack-level restart without a state wipe:

```bash
./stop_stack.sh zeroclaw && ./start_stack.sh
```

## Quick failure map

| Symptom | Likely cause | Next step |
|---|---|---|
| Dashboard shows "Health Offline" | Gateway forward died | `docker restart uplift-zeroclaw-1` |
| `HTTP 503: inference service unavailable` | vLLM is loading or crashed | `docker logs --tail 100 uplift-reasoning-engine-1` |
| `The model 'X' does not exist (404)` | Daemon and vLLM disagree on model name | `./scripts/apply_config.sh && docker compose restart zeroclaw` |
| `docker compose ps` errors with VLLM_* | Shell doesn't have env vars | `source scripts/env.sh` |
