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
   regenerate `.zeroclaw-operator/config.toml` and `.zeroclaw-admin/config.toml`
   from the templates — the agents' model name always matches what vLLM is actually serving.
3. Rebuilds the `zeroclaw:latest` image using the pre-compiled
   binary and launches `reasoning-engine` + tiered agents via
   `docker compose`.

Stop with `./stop_stack.sh`.

## Pairing the Dashboards

The stack runs two separate agents with isolated browser UIs:

| Agent | Port | Theme | Purpose |
| :--- | :--- | :--- | :--- |
| **Operator** | `42617` | Cyan (Default) | General lab tasks, supervised. |
| **Admin** | `42618` | Yellow/Blue | DevOps, autonomous, SSH access. |

Each requires a one-time pairing code. Generate them by invoking the internal APIs:

```bash
# Operator Agent
docker exec uplift-zeroclaw-operator-1 curl -X POST http://localhost:42617/api/pairing/initiate

# Admin Agent
docker exec uplift-zeroclaw-admin-1 curl -X POST http://localhost:42618/api/pairing/initiate
```

Open the dashboards at the respective ports, enter the 6-digit code, and the browser stores a token for subsequent connects.

## Using the Agents

### One-shot from the command line

Useful for quick smoke tests:

```bash
# Messaging the Operator
docker exec uplift-zeroclaw-operator-1 zeroclaw agent -m "GPU temp?"

# Messaging the Admin
docker exec uplift-zeroclaw-admin-1 zeroclaw agent -m "Check status of karone.local"
```

### Over Slack

If you provide separate Slack tokens in `.env`, both agents will listen in Socket Mode.
- Messaging `@uplift-operator` reaches the **Operator Agent**.
- Messaging `@uplift-admin` reaches the **Admin Agent**.

### Remote Access (SSH)

The **Admin Agent** is specifically configured to manage other machines on your local network using SSH.

See [**SSH Setup for ZeroClaw Agent**](ssh-setup.md) for the full configuration guide.

## Verification harness

```bash
./scripts/verify_stack.sh
```

Runs host-prerequisite checks, inference reachability, and health checks for both agents.

## Resetting agent state

When you want to start clean — wipe memory and sessions for **both** tiers:

```bash
./scripts/neuralyzer.sh
```

It stops the running agents, removes state files under their respective tiered directories, and is safe to run at any time.

## Quick failure map

| Symptom | Likely cause | Next step |
|---|---|---|
| Dashboard shows "Health Offline" | Gateway forward died | `docker compose restart zeroclaw-operator` |
| `HTTP 503: inference service unavailable` | vLLM is loading or crashed | `docker logs --tail 100 uplift-reasoning-engine-1` |
| `[Error] All providers failed` | Network misconfig or vLLM loading | Wait 5 mins for `torch.compile` or check `scripts/apply_config.sh` |
| `The model 'X' does not exist (404)` | Daemon and vLLM disagree on model name | `./scripts/apply_config.sh && docker compose restart` |
