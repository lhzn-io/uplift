# Uplift Installation

Optimized for NVIDIA Jetson Orin AGX on JetPack 6.x. The [README](README.md) covers the day-to-day operator path; this document details the host provisioning, build process, and troubleshooting.

## 1. Host Provisioning

After flashing the Jetson, run the provisioning script to tune the hardware and configure the Docker runtime:

```bash
chmod +x jetson/provision_orin.sh start_stack.sh stop_stack.sh \
         scripts/*.sh stack/build_zeroclaw.sh
./jetson/provision_orin.sh
sudo reboot
```

[jetson/provision_orin.sh](jetson/provision_orin.sh) handles:
- **Hardware tuning**: Sets `nvpmodel -m 0` (max power) and `jetson_clocks`.
- **Swap**: Creates a 64 GiB `/swapfile` required for local LLM inference.
- **Docker NVIDIA runtime**: Configures `nvidia-ctk` and cgroups.
- **Networking**: Configures `br_netfilter` and pins `iptables-legacy` (required for JetPack 6).

## 2. Build Agent Image

The `zeroclaw` image is built by patching the upstream daemon with the **Uplift Observer**.

```bash
./stack/build_zeroclaw.sh
docker compose build zeroclaw
```

The first build is slow as it performs a full Cargo `release-fast` build. The build script uses a `trap` to restore patched files on exit, keeping the submodule tree clean.

## 3. Optional: Host CLI

Most users should run the agent via Docker. Install the host-side CLI only if you need to manage the daemon outside the compose stack:

```bash
./scripts/install_zeroclaw.sh
source ~/.bashrc
```

### Troubleshooting: Node.js Conflicts
If the installer fails due to a `libnode-dev` conflict (common on older JetPack flashes):

```bash
sudo dpkg --configure -a
sudo apt-get remove -y libnode-dev libnode72 nodejs npm
sudo apt-get -f install -y
sudo apt-get autoremove -y
./scripts/install_zeroclaw.sh
```

## 4. Configuration

The file `.zeroclaw/config.toml` is rendered from [configs/zeroclaw.toml.template](configs/zeroclaw.toml.template) by `scripts/apply_config.sh`. This process substitutes environment variables (Slack tokens, Brave API keys, model names).

To manually re-render after a config change:
```bash
./scripts/apply_config.sh
docker compose restart zeroclaw
```

## 5. Remote Dashboard Access


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
./start_stack.sh --model gemma4-26b-a4b      # default — Gemma4-26B-A4B
./start_stack.sh --model gemma4-12b          # alternate — Gemma4-12B
./start_stack.sh --model nemotron3-30b-a3b   # alternate — Nemotron-3-Nano
```

Under the hood:

- [scripts/use_model.sh](scripts/use_model.sh) rewrites the `VLLM_*` block in `.env`
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

Expected on a fresh model. Model weights have to be downloaded (if not pre-placed) and loaded onto the GPU. `start_stack.sh` waits up to 7 minutes for `:8000/v1/models` to respond before giving up and starting zeroclaw anyway. If it consistently times out, check `docker logs reasoning-engine` for HuggingFace download progress or AWQ load errors.

### zeroclaw container restarts in a loop

```bash
docker compose logs --tail 200 zeroclaw
```

Common causes:

- `.zeroclaw/config.toml` is missing or invalid — re-render with `./scripts/apply_config.sh`
- `host.docker.internal` not resolving — confirm the `extra_hosts` block in `docker-compose.yml` and that Docker has `default-cgroupns-mode=host` (run `provision_orin.sh` again)
- corrupt SQLite state under `workspace/` — try `./scripts/neuralyzer.sh` at level 1
