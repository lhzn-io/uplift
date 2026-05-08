# Long Horizon Uplift Platform (Core)

![License](https://img.shields.io/badge/license-Apache_2.0-blue)
![Platform](https://img.shields.io/badge/platform-Jetson%20Orin%20AGX-76b900?logo=nvidia&logoColor=white)
![JetPack](https://img.shields.io/badge/JetPack-6.2.2-76b900?logo=nvidia&logoColor=white)
![Model](https://img.shields.io/badge/model-Gemma4--26B--A4B-00c4cc)

Uplift is a sovereign edge platform that enables small organizations to decant autonomous agents directly into the field — and to **measure, causally, how much those agents actually lever up the human operators using them**. This core repository is optimized for NVIDIA Jetson Orin AGX. The **zeroclaw** agent and supporting MCP services run as containers in a single `docker compose` stack, with local inference via **vLLM + Gemma4** by default (Nemotron-3-Nano available as a documented swap-in).

## Thesis

The product question for an operational AI-agent stack is not "did the agent complete the benchmark task." It is: *how much, and for whom, did this stack measurably lever up a human operator in the field, versus their unaided baseline.* That is a treatment-effect question — the same one that uplift modeling, heterogeneous treatment effect estimation, and causal ML have spent fifteen-plus years answering rigorously in marketing and medicine. Uplift Core brings that methodology into field-deployed LLM agent stacks on edge hardware, where evaluation is currently dominated by aggregate benchmark win-rates and vibes.

Anchor deployments: an **aquaculture platform** and a **food bank** — both with scarce, measurable operator time, heterogeneous operator populations, and stakeholders who care whether the AI is actually helping.

We are enthusiastic downstream consumers of [scikit-uplift](https://github.com/maks-sh/scikit-uplift), [upliftml](https://github.com/bookingcom/upliftml), and CausalML — not competitors. We are not a causal inference library; we are an operational stack that takes its own efficacy seriously enough to instrument it causally on real operators in real deployments. The full position piece lives in [`../uplift_position.md`](../uplift_position.md), and the methodology / literature notes live in [`docs/methodology.md`](docs/methodology.md) (stub).

## Collaborators wanted

We arrive on the scene as enthusiasts and adopters of the uplift modeling and human–AI teaming literatures, not as reinventors. If you work in any of the following areas and the mission resonates, we would love to hear from you — as a reviewer, a co-author on a write-up, or a partner on one of the anchor deployments. Open an issue, or reach out directly.

- **Counterfactual evaluation of LLM agent traces.** Off-policy evaluation, credit assignment over tool calls, "what would have happened if the agent had chosen differently at step k."
- **Heterogeneous treatment effects of AI assistance on real operators.** Especially work on *who* AI assistance helps and *who* it hurts, in operational rather than benchmark settings.
- **Field measurement methodology in low-resource / high-stakes deployments.** How to do honest causal evaluation when clean RCTs are impractical — aquaculture, fisheries, food security, humanitarian logistics, community health workers, smallholder agriculture.
- **Trace schema design** that preserves the option to do causal analysis downstream without forcing every contributor to think like a statistician.
- **Anchor deployment partners.** If you run an aquaculture platform, a food bank, or a similarly resource-constrained operation where AI assistance to human operators is on the table and you would value rigorous measurement of whether it actually helps — we want to talk.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for how to engage with the codebase.

## Architecture

The stack is a single Docker Compose project on the Jetson host. There is no nested sandbox: zeroclaw runs as a regular container alongside the other services, with its in-process sandbox disabled (`ZEROCLAW_NO_SANDBOX=1`).

```text
docker-compose.yml
  ├── reasoning-engine    vLLM serving the active model on :8000          [GPU]
  ├── zeroclaw            agent + dashboard on :42617
  ├── browser-node        Selenium Chromium on :4444  (browser tools)
  └── jetson-telemetry    MCP server on :8765        (thermal / power / clocks)

host:
  └── vllm_proxy.py       capability translation proxy on :8100 → :8000
```

The zeroclaw container talks to the host inference endpoint at `http://host.docker.internal:8100/v1` (the proxy), which forwards to vLLM on `:8000`. Agent state lives in two host directories that are bind-mounted into the container and persist across restarts:

- [.zeroclaw/](.zeroclaw/) → `/zeroclaw-data/.zeroclaw` (rendered config, daemon state, secret key, web dist)
- [workspace/](workspace/) → `/zeroclaw-data/workspace` (memory, sessions, skills, scratch)

Both are gitignored. The rendered config at `.zeroclaw/config.toml` comes from [configs/zeroclaw.toml.template](configs/zeroclaw.toml.template) via [scripts/apply_config.sh](scripts/apply_config.sh).

### Models

vLLM serves one model at a time. `start_stack.sh` writes the matching `VLLM_*` block into `.env`:

| Choice | Served name | Image | Selected by |
|---|---|---|---|
| **Gemma4 (default)** | `gemma-4-26b-a4b` | `ghcr.io/nvidia-ai-iot/vllm:gemma4-jetson-orin` | `./start_stack.sh` (no args) or `--model gemma4` |
| Nemotron-3-Nano | `nemotron-3-nano` | `ghcr.io/nvidia-ai-iot/vllm:latest-jetson-orin` | `./start_stack.sh --model nemotron` |

The model-switch helpers — [scripts/use_gemma4.sh](scripts/use_gemma4.sh) and [scripts/use_nemotron.sh](scripts/use_nemotron.sh) — only edit `.env`; restart the stack to apply.

- **OS:** JetPack 6.2.2 / L4T 36.x (Ubuntu 22.04)
- **Inference:** Gemma4-26B-A4B (AWQ) by default; Nemotron-3-Nano-30B-A3B (AWQ) as swap-in
- **Agent:** zeroclaw, built from [stack/zeroclaw/](stack/zeroclaw/) with the Uplift observer patched in by [stack/build_zeroclaw.sh](stack/build_zeroclaw.sh)

---

## First Run (after flash)

### 1. Provision the host

```bash
./jetson/provision_orin.sh
sudo reboot
```

Sets max power mode (`nvpmodel -m 0`, `jetson_clocks`), creates a 64 GiB swap file, configures Docker (`default-cgroupns-mode=host`, NVIDIA runtime), loads `br_netfilter`, sets the bridge sysctls, and pins the legacy `iptables` backend (required on JetPack 6 / 5.15 kernel).

### 2. Bring up the stack

```bash
./start_stack.sh
```

On a clean `.env` this defaults to Gemma4. The script:

1. Writes the Gemma4 (or Nemotron) `VLLM_*` block into `.env`.
2. Brings up `reasoning-engine` and waits for `http://127.0.0.1:8000/v1/models` (up to 7 minutes — first-time model load).
3. Brings up `browser-node`, `jetson-telemetry`, then `zeroclaw`.
4. Starts `scripts/vllm_proxy.py` on `:8100`.

To explicitly pick a model:

```bash
./start_stack.sh --model gemma4
./start_stack.sh --model nemotron
```

### 3. Open the dashboard

```text
http://127.0.0.1:42617
```

From a remote laptop, tunnel first:

```bash
ssh -L 42617:127.0.0.1:42617 <jetson-host>
```

---

## On Every Reboot

```bash
./start_stack.sh
```

Compose restart policies (`unless-stopped`) bring the stack back automatically on host reboot, so this is usually only needed if you ran `./stop_stack.sh` or something failed.

To stop just zeroclaw and keep vLLM warm:

```bash
./stop_stack.sh --zeroclaw-only
```

To stop everything:

```bash
./stop_stack.sh
```

---

## Verify the Stack

The harness validates host prerequisites, inference, zeroclaw, and end-to-end chat. Results are written to `tests/results/`.

```bash
./scripts/verify_stack.sh
```

Useful flags:

```bash
./scripts/verify_stack.sh --host-only        # host prerequisites only
./scripts/verify_stack.sh --skip-e2e         # skip the chat round-trip
./scripts/verify_stack.sh --skip-zeroclaw    # inference-only verification
./scripts/verify_stack.sh --skip-lazy-load   # skip tool_search functional test
```

### Manual checks

```bash
# Host
lsmod | grep br_netfilter
sysctl net.bridge.bridge-nf-call-iptables
docker info | grep -i cgroup

# Inference
docker compose ps
docker logs --tail 50 reasoning-engine
curl -fsS http://127.0.0.1:8000/v1/models
curl -fsS http://127.0.0.1:8100/v1/models   # capability proxy

# Agent
docker logs --tail 50 zeroclaw
curl -I http://127.0.0.1:42617/
```

Fast failure mapping:

- `:8000` dead: `reasoning-engine` container — `docker logs reasoning-engine`
- `:8100` dead but `:8000` alive: `vllm_proxy.py` not running — re-run `./start_stack.sh` or relaunch it manually from the [start_stack.sh](start_stack.sh) snippet
- `:42617` dead: `zeroclaw` container — `docker compose logs zeroclaw`
- Dashboard opens but chat replies fail: provider misconfigured in `.zeroclaw/config.toml` — check the `[providers.models.vllm]` `base_url` and `model` against `VLLM_SERVED_MODEL_NAME` in `.env`

---

## Switching Models

Stop the stack, switch, restart:

```bash
./stop_stack.sh
./start_stack.sh --model nemotron
# or
./start_stack.sh --model gemma4
```

`use_gemma4.sh` / `use_nemotron.sh` only rewrite the `VLLM_*` block in `.env` — they don't touch running containers, which is why the restart is required.

---

## Resetting Agent State

State lives in two host directories bind-mounted into the zeroclaw container: `.zeroclaw/` (rendered config, daemon state, secrets, web dist) and `workspace/` (memory, sessions, skills, scratch, `devices.db`). The standard reset path is [scripts/neuralyzer.sh](scripts/neuralyzer.sh) — it stops the container, prompts for a wipe level, and tells you how to restart.

```bash
./scripts/neuralyzer.sh
```

| Level | Wipes | Use when |
|---|---|---|
| 1. State only | pairings, locks, `devices.db`, `daemon_state.json` | Re-pair the browser or clear stuck connections |
| 2. State + sessions | adds `workspace/sessions/` | Throw out current chat history too |
| 3. Full lobotomy | adds `workspace/memory/` | Wipe long-term memory and start cold |

Then bring zeroclaw back:

```bash
./start_stack.sh
```

### Browser local storage

The web UI on `:42617` caches the gateway token and device pairing in browser localStorage. After any State-level wipe (level 1 or higher), the cached pairing no longer matches anything on the server, and the dashboard will show `Disconnected from gateway` or `device identity required`. Either:

- Clear localStorage for the dashboard origin (DevTools → Application → Local Storage → delete the `127.0.0.1:42617` entry), or
- Use a fresh browser profile / incognito window

Then reconnect with the tokenized URL on first hit (the frontend stashes the token from the `#token=...` hash).

### Manual nuclear reset

If `neuralyzer.sh` can't reach the state for some reason, stop zeroclaw and wipe both dirs by hand. This also drops the rendered config and web dist; the next `./start_stack.sh` re-renders config from [configs/zeroclaw.toml.template](configs/zeroclaw.toml.template).

```bash
./stop_stack.sh --zeroclaw-only
rm -rf .zeroclaw/ workspace/
./start_stack.sh
```

---

## Reference

- [stack/build_zeroclaw.sh](stack/build_zeroclaw.sh) — how zeroclaw is built with the Uplift observer patched in
- [scripts/vllm_proxy.py](scripts/vllm_proxy.py) — the `:8100` capability shim sitting in front of vLLM
- [stack/jetson-telemetry-mcp/](stack/jetson-telemetry-mcp/) — Jetson health and thermal MCP server
- [INSTALLATION.md](INSTALLATION.md) — extended install notes and troubleshooting
