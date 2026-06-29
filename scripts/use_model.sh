#!/usr/bin/env bash
# scripts/use_model.sh — configure the active served model in .env.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

MODEL_CHOICE="${1:-gemma4-26b-a4b}"

# Verify that the model choice is supported by env.sh
# We temporarily disable unbound variable check because env.sh might check $1
set +u
if ! source "scripts/env.sh" "${MODEL_CHOICE}" >/dev/null 2>&1; then
    printf '[ERROR] Unsupported model choice: %s\n' "${MODEL_CHOICE}" >&2
    exit 1
fi
set -u

echo "Setting model to ${MODEL_CHOICE}..."

# Safely remove old model configs from .env if it exists
if [ -f .env ]; then
    grep -v '^VLLM_' .env | grep -v '^TRANSFORMERS_OFFLINE' | grep -v '^HF_DATASETS_OFFLINE' | grep -v '^HF_HUB_OFFLINE' > .env.tmp || true
else
    touch .env.tmp
fi

# Source env.sh to get model identifiers again
set +u
source "scripts/env.sh" "${MODEL_CHOICE}"
set -u

# Append the model configuration
cat << ENVEOF >> .env.tmp
VLLM_IMAGE=${VLLM_IMAGE}
VLLM_MODEL=${VLLM_MODEL}
VLLM_SERVED_MODEL_NAME=${VLLM_SERVED_MODEL_NAME}
VLLM_GPU_MEMORY_UTILIZATION=${VLLM_GPU_MEMORY_UTILIZATION}
VLLM_EXTRA_ARGS="${VLLM_EXTRA_ARGS}"
HF_HUB_OFFLINE=${HF_HUB_OFFLINE:-1}
TRANSFORMERS_OFFLINE=${TRANSFORMERS_OFFLINE:-1}
HF_DATASETS_OFFLINE=${HF_DATASETS_OFFLINE:-1}
ENVEOF

mv .env.tmp .env
