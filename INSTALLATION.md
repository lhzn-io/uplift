# Long Horizon Uplift Platform — Installation

Optimized for Jetson Orin AGX on JetPack 6.x. The [README](README.md) covers the architectural overview and the day-to-day operator path; this document covers deeper install steps, edge cases, and troubleshooting.

## 1. One-time Host Provisioning

After flashing the Jetson:

```bash
chmod +x jetson/provision_orin.sh start_stack.sh stop_stack.sh \
         scripts/install_zeroclaw.sh scripts/verify_stack.sh \
         scripts/neuralyzer.sh stack/build_zeroclaw.sh
./jetson/provision_orin.sh
sudo reboot
```

[jetson/provision_orin.sh](jetson/provision_orin.sh) covers:

- **Hardware tuning:** `nvpmodel -m 0` (max power), `jetson_clocks`
- **Swap:** creates `/swapfile` (64 GiB) if missing, adds it to `/etc/fstab`
- **Docker NVIDIA runtime:** `nvidia-ctk runtime configure --runtime=docker`
- **cgroups:** writes `default-cgroupns-mode=host` into `/etc/docker/daemon.json` and restarts Docker
- **Networking:** loads `br_netfilter`, enables bridge sysctls, switches to `iptables-legacy` (JetPack 6 / 5.15 Tegra kernel does not handle nf_tables properly)
- **Verify:** prints status of each of the above

Reboot afterwards to pick up the Docker daemon changes and persist the kernel-module config.

## 2. Build the zeroclaw Container Image

The container image bakes in upstream zeroclaw with the Uplift observer patched in. [stack/build_zeroclaw.sh](stack/build_zeroclaw.sh) clones the pinned upstream into `stack/zeroclaw/`, applies the observer patches, and builds the runtime with Cargo before the Docker build picks up the artifact.

```bash
./stack/build_zeroclaw.sh
docker compose build zeroclaw
```

The first run is slow (full Cargo `release-fast` build of `zeroclaw-runtime`). The build has a `trap` that restores all patched files on exit, so the source tree should be clean after either success or failure.

If you want to skip the full Cargo build and just rebuild the Docker layer (e.g., after a Dockerfile-only change), `docker compose build zeroclaw` alone is enough as long as the build artifact is already on disk.

## 3. Optional: Install the Host zeroclaw CLI

Most operators don't need this — `start_stack.sh` runs zeroclaw as a container. Install the host CLI only if you want to interact with zeroclaw outside the compose stack.

```bash
./scripts/install_zeroclaw.sh
source ~/.bashrc
```

[scripts/install_zeroclaw.sh](scripts/install_zeroclaw.sh) clones `zeroclaw-labs/zeroclaw` to a temp dir, runs upstream `install.sh`, and builds the web dashboard into `~/.zeroclaw/web_dist`.

### Troubleshooting: Node.js dpkg conflict

If `install_zeroclaw.sh` fails with:

```
trying to overwrite '/usr/include/node/common.gypi', which is also in package libnode-dev 12.x
```

your host has legacy Ubuntu Node 12 dev packages installed. The installer auto-remediates the common case; if apt is already left in a broken state:

```bash
sudo dpkg --configure -a
sudo apt-get remove -y libnode-dev libnode72 nodejs npm
sudo apt-get -f install -y
sudo apt-get autoremove -y
./scripts/install_zeroclaw.sh
```

## 4. First-time Bring-up

```bash
./start_stack.sh
```

On a clean `.env` this defaults to Gemma4. Watch the relevant logs:

```bash
docker compose logs -f reasoning-engine    # vLLM model load (slow first time)
docker compose logs -f zeroclaw            # agent startup
tail -f vllm_proxy.log                     # capability shim
```

The dashboard becomes reachable at `http://127.0.0.1:42617` once zeroclaw is healthy.

### Rendered config

`.zeroclaw/config.toml` is rendered from [configs/zeroclaw.toml.template](configs/zeroclaw.toml.template) by [scripts/apply_config.sh](scripts/apply_config.sh), which substitutes `${VLLM_SERVED_MODEL_NAME}`, Slack tokens, and the Brave API key. Re-run it after editing `.env` or the template:

```bash
./scripts/apply_config.sh
docker compose restart zeroclaw
```

The container also reads `DEFAULT_MODEL` (set from `VLLM_SERVED_MODEL_NAME` in `.env`) directly via env, so a model change is normally picked up by `start_stack.sh` without needing to call `apply_config.sh` by hand.

## 5. Remote Access

To reach the dashboard from a laptop:

```bash
ssh -L 42617:127.0.0.1:42617 <jetson-host>
```

Then open `http://localhost:42617` in the browser.

### Pairing

The gateway runs with `require_pairing = true` ([configs/zeroclaw.toml.template](configs/zeroclaw.toml.template)). On first connect from a fresh browser profile, the dashboard walks you through pairing via the `[gateway.pairing_dashboard]` flow. Once paired, the token is cached in browser localStorage and reused on subsequent connects from the same profile.

If you need the pairing token from the host side, look at the rendered config:

```bash
grep paired_tokens .zeroclaw/config.toml
```

(Tokens are encrypted with the `enc2:` envelope. The normal operator path is to copy the URL printed by the dashboard or pair through the UI rather than constructing the URL by hand.)

## 6. Verification

```bash
./scripts/verify_stack.sh
```

Modes:

```bash
./scripts/verify_stack.sh --host-only        # host prerequisites only
./scripts/verify_stack.sh --skip-e2e         # everything except chat round-trip
./scripts/verify_stack.sh --skip-zeroclaw    # inference-only
./scripts/verify_stack.sh --skip-lazy-load   # skip tool_search functional test
```

JSON results land in `tests/results/`. The individual tests can also be run directly:

```bash
bash tests/test_00_host.sh
bash tests/test_01_inference.sh
bash tests/test_02_zeroclaw.sh
python3 tests/test_04_e2e_inference.py
python3 tests/test_05_lazy_load.py
```

If only `host-prerequisites` fails, re-run the provisioner and reboot:

```bash
./jetson/provision_orin.sh
sudo reboot
```

## 7. Switching Models

```bash
./stop_stack.sh
./start_stack.sh --model gemma4    # default — Gemma4-26B-A4B
./start_stack.sh --model nemotron  # alternate — Nemotron-3-Nano-30B-A3B
```

Under the hood:

- [scripts/use_gemma4.sh](scripts/use_gemma4.sh) / [scripts/use_nemotron.sh](scripts/use_nemotron.sh) rewrite the `VLLM_*` block in `.env`
- `start_stack.sh` brings up the matching vLLM image (`ghcr.io/nvidia-ai-iot/vllm:gemma4-jetson-orin` vs `:latest-jetson-orin`) and waits for the model to load
- The zeroclaw container reads `VLLM_SERVED_MODEL_NAME` via `DEFAULT_MODEL` env

Model weights are mounted into the vLLM container at `/data/models/huggingface` via `HF_HOME`. Pre-downloading both repos under `models/huggingface/` makes the swap fully offline.

If the dashboard later returns `The model '<name>' does not exist. (404)`, the rendered `.zeroclaw/config.toml` has drifted from what vLLM is actually serving. Re-sync:

```bash
VLLM_SERVED_MODEL_NAME=$(curl -s http://127.0.0.1:8000/v1/models \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["data"][0]["id"])') \
  ./scripts/apply_config.sh
docker compose restart zeroclaw
```

## 8. Resetting Agent State

The standard reset path is [scripts/neuralyzer.sh](scripts/neuralyzer.sh) — it stops the zeroclaw container, prompts for a wipe level (state-only, +sessions, or full lobotomy), and prints the restart command. See the [Resetting Agent State](README.md#resetting-agent-state) section in the README for the level table.

> **After any state-level wipe, also clear browser localStorage** for `127.0.0.1:42617` (or use a fresh browser profile). The cached pairing won't match the freshly-wiped server side, and the dashboard will hang on `device identity required` or `Disconnected from gateway` until you do.

## 9. Troubleshooting

### Dashboard shows `Disconnected from gateway` or `device identity required`

The browser has a stale pairing in localStorage from a previous run, or the server-side pairings were wiped (e.g., by `scripts/neuralyzer.sh` at level 1+). Either:

- Clear localStorage for `127.0.0.1:42617` (DevTools → Application → Local Storage), or
- Open the dashboard in a fresh browser profile or incognito window

then re-pair through the UI.

### Dashboard works locally but fails through SSH tunnel

If the websocket fails after the page itself loads, the browser origin doesn't match the gateway's allowed origins. The simplest fix is to always tunnel onto the same port the gateway listens on (`42617`) so the origin matches:

```bash
ssh -L 42617:127.0.0.1:42617 <jetson-host>
```

If you need to remap to a different local port, you'll need to adjust the gateway's allowed-origin list in `configs/zeroclaw.toml.template`, re-render, and restart zeroclaw.

### `HTTP 503: inference service unavailable`

The dashboard path is up but vLLM is unhealthy. Check, in order:

```bash
docker compose ps
docker logs --tail 100 reasoning-engine
curl -fsS http://127.0.0.1:8000/v1/models    # native vLLM
curl -fsS http://127.0.0.1:8100/v1/models    # capability proxy
```

- `:8000` dead → `reasoning-engine` crashed or model didn't finish loading. Restart it: `docker compose restart reasoning-engine`.
- `:8100` dead but `:8000` alive → `vllm_proxy.py` didn't start. The launch is at the tail of `start_stack.sh`; re-run `./start_stack.sh` or launch the proxy by hand:
  ```bash
  nohup python3 scripts/vllm_proxy.py --listen-port 8100 --vllm-port 8000 \
      > vllm_proxy.log 2>&1 &
  ```
- Both alive but chat still fails → daemon's configured model has drifted from what vLLM serves; see the re-sync command in [§7 Switching Models](#7-switching-models).

### `reasoning-engine` first start takes forever

Expected on a fresh model. Gemma4 / Nemotron weights have to be downloaded (if not pre-placed) and loaded onto the GPU. `start_stack.sh` waits up to 7 minutes for `:8000/v1/models` to respond before giving up and starting zeroclaw anyway. If it consistently times out, check `docker logs reasoning-engine` for HuggingFace download progress or AWQ load errors.

### zeroclaw container restarts in a loop

```bash
docker compose logs --tail 200 zeroclaw
```

Common causes:

- `.zeroclaw/config.toml` is missing or invalid — re-render with `./scripts/apply_config.sh`
- `host.docker.internal` not resolving — confirm the `extra_hosts` block in `docker-compose.yml` and that Docker has `default-cgroupns-mode=host` (run `provision_orin.sh` again)
- corrupt SQLite state under `workspace/` — try `./scripts/neuralyzer.sh` at level 1
