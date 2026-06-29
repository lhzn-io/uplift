# Uplift: Sovereign Agent Measurement

![License](https://img.shields.io/badge/license-Apache_2.0-blue)
![Platform](https://img.shields.io/badge/platform-Jetson%20Orin%20AGX-76b900?logo=nvidia&logoColor=white)
![JetPack](https://img.shields.io/badge/JetPack-6.2.2-76b900?logo=nvidia&logoColor=white)
![Model](https://img.shields.io/badge/model-Gemma4--26B--A4B-00c4cc)

Uplift is a sovereign edge platform for deploying autonomous agents into the field and measuring, causally, how much they actually lever up human operators. 

The stack is optimized for NVIDIA Jetson Orin AGX, running the **zeroclaw** agent and supporting MCP services as a single `docker compose` project. By default, it uses **vLLM + Gemma4** for local inference.

## Thesis

Uplift asks a treatment-effect question: *how much did this stack measurably lever up a human operator, versus their unaided baseline?* 

Current AI evaluation is dominated by aggregate benchmarks and vibes. We bring the methodology of uplift modeling and causal ML into field-deployed agent stacks, instrumenting efficacy on real operators in deployments like **aquaculture platforms** and **food banks**. 

We are enthusiasts of [scikit-uplift](https://github.com/maks-sh/scikit-uplift), [upliftml](https://github.com/bookingcom/upliftml), and CausalML. Uplift is not a causal inference library; it is an operational stack that takes its own impact seriously. See [docs/methodology.md](docs/methodology.md) for details.

## Collaborators Wanted

Uplift is built on research in uplift modeling and human–AI collaboration. We are looking for contributors, reviewers, and deployment partners focused on:

- **Counterfactual evaluation of LLM agent traces.** Off-policy evaluation, credit assignment over tool calls, and trajectory analysis.
- **Heterogeneous treatment effects of AI assistance.** Research into who AI assistance helps (or hinders) in operational settings.
- **Field measurement methodology.** Rigorous evaluation in high-stakes, low-resource environments (aquaculture, food security, humanitarian logistics).
- **Trace schema design.** Preserving downstream causal analysis options without inflating contributor overhead.
- **Anchor deployment partners.** Resource-constrained operations interested in measuring the true lever-up of AI assistance.

See [CONTRIBUTING.md](CONTRIBUTING.md) to get involved.

## Architecture

The stack runs as a Docker Compose project on a Jetson host. 

```text
docker-compose.yml
  ├── reasoning-engine    vLLM (Gemma4-26B/Gemma4-12B/Nemotron3)      [GPU]
  ├── zeroclaw            Agent + Dashboard                           [:42617]
  ├── browser-node        Selenium Chromium (Reference Implementation) [:4444]
  └── jetson-telemetry    MCP Server (Pattern Example)                [:8765]

host:
  └── vllm_proxy.py       FastAPI Instrumentation Proxy               [:8100]
```

- **Inference**: vLLM serving AWQ-quantized weights. `vllm_proxy.py` captures raw chat traces for tool-call attribution.
- **Tools**: `browser-node` provides a standard Selenium base; we are evaluating **Ai2 MolmoWeb** as a multimodal upgrade. `jetson-telemetry` serves as both a utility for thermal/power monitoring and a working design pattern for integrating external MCP tools into the `zeroclaw` runtime.

### Persistence
Agent state lives in two host directories bind-mounted into the containers:
- [workspace/](workspace/) -> Memory and session data.
- [.zeroclaw/](.zeroclaw/) -> Daemon state and rendered configs.

### Configuration
Run `scripts/apply_config.sh` to render the configuration from `configs/zeroclaw.toml.template`.

---

## Setup

### 1. Provision Host
```bash
./jetson/provision_orin.sh
sudo reboot
```
Configures power modes, swap, and Docker for the Jetson Orin.

### 2. Start Stack
```bash
./start_stack.sh
```
This defaults to Gemma4-26B. The script handles model loading, proxy startup, and service orchestration.

### 3. Verification
```bash
./scripts/verify_stack.sh
```
Runs the health checks and end-to-end inference tests. 


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

## Development & Reset

### Switching Models
You can configure the active served model using the model configurator script:
```bash
./scripts/use_model.sh gemma4-26b-a4b        # Gemma-4-26B (default)
./scripts/use_model.sh gemma4-12b            # Gemma-4-12B
./scripts/use_model.sh nemotron3-30b-a3b      # Nemotron-3-Nano
```
Or pass full Hugging Face repository paths directly:
```bash
./start_stack.sh --model cyankiwi/gemma-4-26B-A4B-it-AWQ-4bit
```
The model choice is persisted in `.env`.

### Resetting Agent State
State is stored in `.zeroclaw/` and `workspace/`. Use `neuralyzer.sh` for guided wipes:
```bash
./scripts/neuralyzer.sh
```
- **Level 1**: Clear pairings/locks (keep history).
- **Level 2**: Level 1 + wipe chat sessions.
- **Level 3**: Full wipe including long-term memory.

### Manual Reset
```bash
./stop_stack.sh --zeroclaw-only
rm -rf .zeroclaw/ workspace/
./start_stack.sh
```

---

## Collaborators Wanted

Uplift is built on research in uplift modeling and human–AI collaboration. We are looking for contributors, reviewers, and deployment partners focused on:

