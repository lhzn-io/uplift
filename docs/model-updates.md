# Model Update Workflow (Offline Mode)

Uplift runs the `reasoning-engine` in **Full Offline Mode** (`HF_HUB_OFFLINE=1`). This ensures fast, deterministic startup times and eliminates external network dependencies during runtime.

As a result, model updates must be **intentional** and performed manually by an Administrator.

## Workflow: Updating a Model

### 1. Enable Online Mode Temporarily
To fetch a new snapshot, you must allow the container to reach the HuggingFace Hub. Update your `.env` file:

```bash
HF_HUB_OFFLINE=0
TRANSFORMERS_OFFLINE=0
```

### 2. Update the Model ID
In `scripts/env.sh` (or your `.env`), change the `VLLM_MODEL` to the short name of the repo you want to pull (e.g., `cyankiwi/gemma-4-26B-A4B-it-AWQ-4bit`).

### 3. Pull the New Snapshot
Restart the reasoning engine. vLLM will detect the missing files (or newer version) and download them to the cache.

```bash
docker compose up -d reasoning-engine
docker logs -f uplift-reasoning-engine-1
```
*Wait for the download to complete and the engine to start.*

### 4. Re-Pin for Offline Mode
Once the model is downloaded, you should pin it back to the absolute path to ensure speed.

1.  **Find the new snapshot path**:
    ```bash
    docker exec uplift-reasoning-engine-1 find /data/models/huggingface -name "config.json"
    ```
    This will return a path like: `/data/models/huggingface/models--user--repo/snapshots/<NEW_SHA>/config.json`.

2.  **Update `scripts/env.sh`**:
    Update the `VLLM_MODEL` variable for your model choice with the new absolute path (the directory containing `config.json`).

3.  **Restore Offline Flags**:
    Set the flags back to `1` in your `.env`:
    ```bash
    HF_HUB_OFFLINE=1
    TRANSFORMERS_OFFLINE=1
    ```

4.  **Final Restart**:
    ```bash
    ./scripts/apply_config.sh
    docker compose up -d reasoning-engine
    ```

## Automated Update Checks

The `./scripts/verify_stack.sh` command performs a non-blocking check against the HuggingFace API if a network connection is available.

- It will **not** block the verification if HuggingFace is unreachable.
- If a new version is detected, it will print a notice at the end of the verification report:
  > `[NOTICE] Model update available for Gemma-4: <NEW_SHA>`

This allows you to stay informed about available improvements without compromising the air-gapped performance of the stack.
